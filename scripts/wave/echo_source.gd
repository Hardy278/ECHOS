extends Node2D

## 一个发声物体的声道。
##
## 每个能出声的东西（角色、钟、以后的水滴 / 敌人……）挂一个，就拥有**一份独立的**
## 与世界等大的波动方程（SubViewport + wave_step_fb，尺寸见 EchoField），在自己的墙上跑。
## 发声只是往这个场里注入一次能量：心跳、落地、喊叫是同一张嘴强弱不同的几次，
## 不存在"每个声音一个声道"这回事。遮罩半径由强度推出来（对数级）：
## R = mask_span × ln(1 + amp/mask_eps)，所以同一个场里可以既有 50 半径的心跳
## 也有 132 半径的喊叫。
##
## 所有声源在世界那边（EchoWorld）按各自的音色（tint / gain）叠加成总的照亮。
## 这里不再有"到听者的距离衰减"：遮罩已经在注入时写进波的振幅里了。
##
## 场只在发声后推进 LIVE_SEC，然后停掉 SubViewport —— 不响的物体不花 GPU。

const STEP_SHADER := preload("res://shaders/wave_step_fb.gdshader")
const VIEW_SHADER := preload("res://shaders/source_view.gdshader")
## 和主角的场一致：模拟固定 60 步/秒。波速 = stride × √cfl × 步率；
## 每帧都推进的话，高刷屏上的波会比 60Hz 屏上快一倍多。
const STEPS_HZ := 60.0
const TICK_DT := 1.0 / STEPS_HZ
## 一次发声后，场还值得推进多久；过了就停
const LIVE_SEC := 2.6

@export var damp := 0.9955          ## 模拟里每步的振幅衰减
@export var env_decay := 0.966      ## 模拟里包络（余晖）的衰减
@export var emit_radius := 14.0     ## 注入的高斯半径（这个物体的"嗓子"粗细）
## 遮罩：半径 R = mask_span × ln(1 + 振幅 / mask_eps)。
## 亮度仍然线性跟着振幅，宽度只是对数级增长，所以两者被拆开了。
## 默认 30 / 0.03 → 心跳(.045)=27、钟(.2)=61、喊叫(.3)=72。
@export var mask_span := 30.0
## 压缩强度：越小，安静端被抬得越多、响度差被压得越平
@export var mask_eps := 0.03
## 到达听者耳朵多响算"听得清"：低于它的声音，它的整个波都不会画给玩家看
@export var hear_ref := 0.05
@export var tint := Color(0.62, 0.82, 1.0)
@export var gain := 1.2
## 每次发声前把场清空。周期性的声音通常关掉：上一发的余晖还在，接着发才连贯。
@export var clear_before_emit := false

var _vp: SubViewport
var _mat: ShaderMaterial
var _view_mat: ShaderMaterial
var _world: Node
var _ready_frames := 0
var _step_acc := 0.0
var _live := 0.0
var _amp := 0.0
var _steps := 0
var _clear_frames := 0
var _resetting := true
var _emit_pos := Vector2.ZERO
var _listener := Vector2.ZERO


func _enter_tree() -> void:
	add_to_group("echo_sources")


func _ready() -> void:
	# 场景里的子节点比 Main._ready 先 ready；推迟一帧，等 EchoWorld 建好再挂
	_setup.call_deferred()


func _setup() -> void:
	_world = get_tree().get_first_node_in_group("echo_world")
	_emit_pos = global_position
	_listener = global_position

	var geo_tex: Texture2D = null
	var band_tex: Texture2D = null
	if _world != null:
		geo_tex = _world.geometry_texture()
		band_tex = _world.band_texture()
	if geo_tex == null:
		geo_tex = _blank_texture()      # 没有世界 = 空气，至少别把场涂白

	_vp = SubViewport.new()
	_vp.size = EchoField.VIEW_SIZE
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.use_hdr_2d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	add_child(_vp)

	_mat = ShaderMaterial.new()
	_mat.shader = STEP_SHADER
	_mat.set_shader_parameter("geo_tex", geo_tex)
	_mat.set_shader_parameter("field_size", EchoField.FIELD_SIZE)
	_mat.set_shader_parameter("stride", 4.0)
	_mat.set_shader_parameter("cfl", 0.48)
	_mat.set_shader_parameter("damp", damp)
	_mat.set_shader_parameter("env_decay", env_decay)
	_mat.set_shader_parameter("hf_damp", 0.02)
	_mat.set_shader_parameter("inject_r", emit_radius)
	_mat.set_shader_parameter("emit_px", _emit_pos)
	_mat.set_shader_parameter("mask_span", mask_span)
	_mat.set_shader_parameter("mask_eps", mask_eps)
	_mat.set_shader_parameter("emit_falloff", 1.8)
	_mat.set_shader_parameter("inject", 0.0)
	_mat.set_shader_parameter("reset", 1.0)

	var cr := ColorRect.new()
	cr.size = EchoField.FIELD_SIZE
	cr.material = _mat
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp.add_child(cr)

	_view_mat = ShaderMaterial.new()
	_view_mat.shader = VIEW_SHADER
	_view_mat.set_shader_parameter("env_field", _vp.get_texture())
	_view_mat.set_shader_parameter("band_tex", band_tex)
	_view_mat.set_shader_parameter("field_size", EchoField.FIELD_SIZE)
	_view_mat.set_shader_parameter("gain", gain)
	_view_mat.set_shader_parameter("tint", tint)
	_view_mat.set_shader_parameter("hear_ref", hear_ref)
	_view_mat.set_shader_parameter("listener_px", global_position)

	if _world != null:
		_world.register(self, _view_mat)


## 在自己身上发声（用默认参数）
func emit(amp: float = 1.0, steps_wanted: int = 1) -> void:
	emit_at(global_position, amp, steps_wanted)


## 发声：amp 是注入振幅，steps 是连续注入的帧数。
##
## 遮罩半径 R = mask_span × ln(1 + amp/mask_eps)：亮度线性、宽度对数级，
## 所以"喊得更响"不会把遮罩一起撑大；falloff（k）只决定形状，k > 1 时中心陡、
## 边缘趋平。mask_scale 是这一次发声自己的缩放（想单独收窄某一个声音时用）。
## 一个场里可以混着不同强度的几次发声，各带各的遮罩——不需要各占一个声道。
func emit_at(origin: Vector2, amp: float = 1.0, steps_wanted: int = 1,
		falloff: float = 1.8, mask_scale: float = 1.0) -> void:
	_emit_pos = origin
	_amp = amp
	_steps = maxi(_steps, steps_wanted)
	if _live <= 0.0 or clear_before_emit:
		_clear_frames = 2
	_live = LIVE_SEC
	if _mat != null:
		_mat.set_shader_parameter("emit_px", _emit_pos)
		_mat.set_shader_parameter("emit_falloff", falloff)
		_mat.set_shader_parameter("mask_span", mask_span * mask_scale)


## 统一发声入口：挂在它下面的 SoundAbility 通过这里发进来
func emit_sound(origin: Vector2, amp: float, steps_wanted: int,
		falloff: float = 1.8, mask_scale: float = 1.0) -> void:
	emit_at(origin, amp, steps_wanted, falloff, mask_scale)


func field_texture() -> ViewportTexture:
	return _vp.get_texture() if _vp != null else null


## 听者位置：这一层要按"它在我耳朵这儿有多响"来决定整层的闸门
func set_listener(pos: Vector2) -> void:
	_listener = pos
	if _view_mat != null:
		_view_mat.set_shader_parameter("listener_px", pos)


## 最近一次的听者位置（实体显形也用它，保证和声场同一个闸门）
func listener_position() -> Vector2:
	return _listener


func _process(delta: float) -> void:
	if _vp == null:
		return

	if _resetting:
		_ready_frames += 1
		if _ready_frames >= 2:
			_resetting = false
			_mat.set_shader_parameter("reset", 0.0)
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		return

	if _live > 0.0:
		_live -= delta
		if _live <= 0.0:
			_live = 0.0
			_steps = 0

	if _live <= 0.0:
		_step_acc = 0.0
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return

	if _clear_frames > 0:
		# 清场：这两帧只把场写成 0，不注入，之后才是干净的一发
		_mat.set_shader_parameter("reset", 1.0)
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_clear_frames -= 1
		if _clear_frames == 0:
			_mat.set_shader_parameter("reset", 0.0)
		return

	# 固定步率：一帧最多推进一步
	_step_acc += delta
	if _step_acc < TICK_DT:
		return
	_step_acc = minf(_step_acc - TICK_DT, TICK_DT)

	if _steps > 0:
		_mat.set_shader_parameter("inject", _amp)
		_steps -= 1
	else:
		_mat.set_shader_parameter("inject", 0.0)

	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _blank_texture() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
