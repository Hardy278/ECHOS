extends Node2D

class_name EchoSource

## 一个发声物体的声道。
##
## 每个能出声的东西（角色、钟、以后的水滴 / 敌人……）挂一个，就拥有**一份独立的**
## 与世界等大的波动方程（SubViewport + wave_step_fb，尺寸见 EchoField），在自己的墙上跑。
## 发声只是往这个场里注入一次能量（一个 inject_r 大小的高斯），
## **没有遮罩**：一声能传多远，由 damp、房间声学和中间撞上什么决定。
##
## 所有声源在世界那边（EchoWorld）按各自的音色（tint / gain）叠加成总的照亮。
##
## 场只在发声后推进 LIVE_SEC，然后停掉 SubViewport 。

const STEP_SHADER := preload("res://shaders/wave_step_fb.gdshader")
const VIEW_SHADER := preload("res://shaders/source_view.gdshader")
## 一帧一步，每步跨 STRIDE 个 texel。波速 = STRIDE × √cfl × 60 世界单位/秒。
const STRIDE := 4.0
## 模拟固定 60 步/秒。波速 = stride × √cfl × 步率；
## 每帧都推进的话，高刷屏上的波会比 60Hz 屏上快一倍多。
const STEPS_HZ := 60.0
const TICK_DT := 1.0 / STEPS_HZ
## 一次发声后，场还值得推进多久；过了就停
const LIVE_SEC := 4
## 清场要写两帧（一帧写不满整张 HDR 缓冲的边角）
const CLEAR_FRAMES := 2
## 开口边的吸声层宽度（texel）：必须和着色器里的 sponge_w 是同一个数
const SPONGE_W := 28.0
## 切房时搬运的薄片宽度（texel）：至少要盖住一个 stencil
const SEED_W := 12
## 搬过来的能量打个折：只有开口那一部分该穿过去
const SEED_GAIN := 0.7

@export var damp := 0.9955          ## 模拟里每步的振幅衰减
@export var env_decay := 0.966      ## 模拟里包络（余晖）的衰减
@export var emit_radius := 14.0     ## 注入的高斯半径（这个物体的"嗓子"粗细）
## 到达听者耳朵多响算"听得清"：低于它的声音，它的整个波都不会画给玩家看
@export var hear_ref := 0.05
## 战争迷雾：true = 听不见就不画这一层（角色自己的声道这样用，才有"回声散掉"）。
## false = 不管听不听得见，波照画（钟、机关、门这些"别的声源"就该一直亮着）。
@export var hear_gate := false
@export var tint := Color(0.62, 0.82, 1.0)
@export var gain := 1.2
## 每次发声前把场清空。周期性的声音通常关掉：上一发的余晖还在，接着发才连贯。
@export var clear_before_emit := false

var _vps: Array = []             ## 两块场缓冲，轮流当"正面"
var _mats: Array = []            ## 和两块缓冲对应的步进材质
var _front := 0                   ## 当前正面是 _vps[_front]
var _mat: ShaderMaterial        ## 步进 + 注入（= _mats[0]，只用来判空/取 _mat 的引用）
var _view_mat: ShaderMaterial
var _world: Node
var _room_system: Node
var _step_acc := 0.0
var _live := 0.0
var _amp := 0.0
var _steps := 0
var _clear_frames := 0
var _seed_frames := 0
var _emit_pos := Vector2.ZERO
var _listener := Vector2.ZERO


func _enter_tree() -> void:
	add_to_group("echo_sources")


func _ready() -> void:
	# 场景里的子节点比 Main._ready 先 ready；推迟一帧，等 EchoWorld 建好再挂
	_setup.call_deferred()


func _exit_tree() -> void:
	# 房间被销毁时声源跟着走：把合成层里那一份也摘掉，别留死视图
	if _world != null and is_instance_valid(_world) and _world.has_method("unregister"):
		_world.unregister(self)


## 造一份步进材质。每步跨 STRIDE 个 texel。
func _make_step_material(geo_tex: Texture2D, src_tex: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = STEP_SHADER
	m.set_shader_parameter("geo_tex", geo_tex)
	m.set_shader_parameter("src_tex", src_tex)
	m.set_shader_parameter("field_size", EchoField.FIELD_SIZE)
	m.set_shader_parameter("stride", STRIDE)
	m.set_shader_parameter("cfl", 0.48)
	m.set_shader_parameter("hf_damp", 0.02)
	m.set_shader_parameter("inject_r", emit_radius)
	m.set_shader_parameter("emit_px", _emit_pos)
	m.set_shader_parameter("inject", 0.0)
	m.set_shader_parameter("reset", 0.0)
	m.set_shader_parameter("sponge_w", SPONGE_W)
	m.set_shader_parameter("seed", 0.0)
	m.set_shader_parameter("seed_gain", SEED_GAIN)
	return m


func _setup() -> void:
	_world = get_tree().get_first_node_in_group("echo_world")
	_room_system = get_tree().get_first_node_in_group("room_system")
	_emit_pos = global_position
	_listener = global_position

	var geo_tex: Texture2D = null
	var band_tex: Texture2D = null
	if _world != null:
		geo_tex = _world.geometry_texture()
		band_tex = _world.band_texture()
	if geo_tex == null:
		geo_tex = _blank_texture()      # 没有世界 = 空气，至少别把场涂白

	# 双缓冲 ping-pong：两块 SubViewport 互相采样对方的纹理，轮流当"正面"。
	# 之前用的是 hint_screen_texture（读自己的屏幕快照），实测它每步会带进
	# 0.1~0.2 texel 的系统性偏移，累积后把波拉成一条 45° 长条。
	_vps.clear()
	_mats.clear()
	for k in 2:
		var vp := SubViewport.new()
		vp.size = EchoField.VIEW_SIZE
		vp.disable_3d = true
		vp.transparent_bg = false
		vp.use_hdr_2d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		add_child(vp)
		_vps.append(vp)

	for k in 2:
		var src_tex: Texture2D = (_vps[1 - k] as SubViewport).get_texture()
		var m := _make_step_material(geo_tex, src_tex)
		_mats.append(m)
		var cr := ColorRect.new()
		cr.size = EchoField.FIELD_SIZE
		cr.material = m
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		(_vps[k] as SubViewport).add_child(cr)
	_mat = _mats[0]
	_front = 0
	_write_tuning()

	_view_mat = ShaderMaterial.new()
	_view_mat.shader = VIEW_SHADER
	_view_mat.set_shader_parameter("env_field", field_texture())
	_view_mat.set_shader_parameter("band_tex", band_tex)
	_view_mat.set_shader_parameter("field_size", EchoField.FIELD_SIZE)
	_view_mat.set_shader_parameter("gain", gain)
	_view_mat.set_shader_parameter("tint", tint)
	_view_mat.set_shader_parameter("hear_ref", hear_ref)
	_view_mat.set_shader_parameter("hear_gate", 1.0 if hear_gate else 0.0)
	_view_mat.set_shader_parameter("listener_px", global_position)

	if _world != null:
		_world.register(self, _view_mat)

	_clear_frames = CLEAR_FRAMES      # 新场从全 0 起步


## 在自己身上发声（用默认参数）
func emit(amp: float = 1.0, steps_wanted: int = 1) -> void:
	emit_at(global_position, amp, steps_wanted)


## 发声：amp 是注入振幅，steps 是连续注入的帧数。
##
## 没有遮罩：注入就是一个 inject_r 半径的高斯，能传多远交给 damp 和几何。
func emit_at(origin: Vector2, amp: float = 1.0, steps_wanted: int = 1) -> void:
	_emit_pos = origin
	_amp = amp
	_steps = maxi(_steps, steps_wanted)
	if _live <= 0.0 or clear_before_emit:
		_clear_frames = CLEAR_FRAMES
	_live = LIVE_SEC
	if _mat != null:
		_write_tuning()          # 房间可能换过了，声学跟着换
		_set_param("emit_px", _emit_pos)


## 统一发声入口：挂在它下面的 SoundAbility 通过这里发进来
func emit_sound(origin: Vector2, amp: float, steps_wanted: int) -> void:
	emit_at(origin, amp, steps_wanted)


## 外部清场（切房间时用）：两帧把场写成 0，然后停掉，别带着旧房间的反射走
func clear_field() -> void:
	_clear_frames = CLEAR_FRAMES
	_live = 0.0
	_steps = 0
	_step_acc = 0.0


## 切房前把"正在穿出房间"的那一薄片抄下来。dir 是穿越方向。
## 走 CPU 读回一次（12×270，几毫秒）：GPU 那边同一帧里既抄又清，渲染顺序不保证。
func capture_slab(dir: Vector2i) -> Texture2D:
	if _vps.is_empty() or dir == Vector2i.ZERO:
		return null
	var tex := field_texture()
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	var rect := _slab_rect(dir, img.get_width(), img.get_height())
	if rect.position.x < 0 or rect.position.y < 0:
		return null
	if rect.end.x > img.get_width() or rect.end.y > img.get_height():
		return null
	var part := img.get_region(rect)
	if part.get_format() != Image.FORMAT_RGBAF:
		part.convert(Image.FORMAT_RGBAF)
	return ImageTexture.create_from_image(part)


## 切房后把薄片写进新房间的入口侧：刚才那一声跟着你进来。
## dir 是刚才的穿越方向，薄片贴到反方向那条边上。
func seed_slab(tex: Texture2D, dir: Vector2i) -> void:
	if _mat == null or tex == null or dir == Vector2i.ZERO:
		return
	var rect := _slab_rect(-dir, EchoField.FW, EchoField.FH)
	_set_param("seed_tex", tex)
	_set_param("seed_size", Vector2(tex.get_width(), tex.get_height()))
	_set_param("seed_at", Vector2(rect.position))
	_seed_frames = 1
	_live = LIVE_SEC          # 定场之后场还要能接着走
	_steps = 0
	_step_acc = 0.0


## 薄片贴在哪：竖片（左右出口）是 x 起点，横片（上下出口）是 y 起点
func _slab_rect(dir: Vector2i, w: int, h: int) -> Rect2i:
	var inset := int(SPONGE_W)
	if dir.x > 0:
		return Rect2i(w - inset - SEED_W, 0, SEED_W, h)
	if dir.x < 0:
		return Rect2i(inset, 0, SEED_W, h)
	if dir.y > 0:
		return Rect2i(0, h - inset - SEED_W, w, SEED_W)
	return Rect2i(0, inset, w, SEED_W)


func field_texture() -> ViewportTexture:
	return (_vps[_front] as SubViewport).get_texture() if not _vps.is_empty() else null


## 听者位置：这一层要按"它在我耳朵这儿有多响"来决定整层的闸门
func set_listener(pos: Vector2) -> void:
	_listener = pos
	if _view_mat != null:
		_view_mat.set_shader_parameter("listener_px", pos)


## 最近一次的听者位置（实体显形也用它，保证和声场同一个闸门）
func listener_position() -> Vector2:
	return _listener


func _process(delta: float) -> void:
	if _vps.is_empty():
		return

	# 清场优先：这两帧只把场写成 0，不注入
	if _clear_frames > 0:
		_set_param("reset", 1.0)
		_step_render()
		_clear_frames -= 1
		if _clear_frames == 0:
			_set_param("reset", 0.0)
		return

	# 定场：清完之后写一帧薄片，之后交给场自己演化
	if _seed_frames > 0:
		_set_param("reset", 1.0)
		_set_param("seed", 1.0)
		_step_render()
		_seed_frames -= 1
		if _seed_frames == 0:
			_set_param("reset", 0.0)
			_set_param("seed", 0.0)
		return

	if _live > 0.0:
		_live -= delta
		if _live <= 0.0:
			_live = 0.0
			_steps = 0

	if _live <= 0.0:
		_step_acc = 0.0
		_hold()
		return

	# 固定步率：一帧最多推进一步
	_step_acc += delta
	if _step_acc < TICK_DT:
		return
	_step_acc = minf(_step_acc - TICK_DT, TICK_DT)

	if _steps > 0:
		_set_param("inject", _amp)
		_steps -= 1
	else:
		_set_param("inject", 0.0)

	_step_render()


## 两块缓冲轮流当"正面"：往背面写一步，然后把背面变成正面
func _step_render() -> void:
	var back := 1 - _front
	(_vps[back] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
	_front = back
	(_vps[1 - back] as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _view_mat != null:
		_view_mat.set_shader_parameter("env_field", field_texture())


## 停掉推进，保留当前画面
func _hold() -> void:
	(_vps[_front] as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED


## 两块材质的参数一起写（每次写的是"背面"那块，不确定是哪块）
func _set_param(name: StringName, v) -> void:
	for m in _mats:
		(m as ShaderMaterial).set_shader_parameter(name, v)


# ---------------------------------------------------------------- 房间声学

## 房间给倍率，物体保留自己的嗓子：reverb 让余晖拖长，absorb 让能量掉得更快。
## 顺带把"哪几条边是开口"写进去——开口那边是吸声层，不是反射壁。
func _write_tuning() -> void:
	if _mat == null:
		return
	var a := _room_acoustics()
	var env := 1.0 - (1.0 - env_decay) * (1.0 - a.x * 0.9)
	var dm := damp * (1.0 - a.y * 0.05)
	var edges := _room_edges()
	_set_param("env_decay", env)
	_set_param("damp", dm)
	_set_param("sponge_edges", edges)


## 切房后由 RoomSystem 调：声学和开口都按新房间重设
func refresh_room() -> void:
	_write_tuning()


func _room_acoustics() -> Vector2:
	if _room_system == null or not is_instance_valid(_room_system):
		_room_system = get_tree().get_first_node_in_group("room_system") if is_inside_tree() else null
	if _room_system != null and _room_system.has_method("acoustics"):
		return _room_system.acoustics()
	return Vector2.ZERO


func _room_edges() -> Vector4:
	if _room_system == null or not is_instance_valid(_room_system):
		_room_system = get_tree().get_first_node_in_group("room_system") if is_inside_tree() else null
	if _room_system != null and _room_system.has_method("edges"):
		return _room_system.edges()
	return Vector4.ZERO


func _blank_texture() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
