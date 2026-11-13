extends Node2D

class_name EchoSource

## 一个发声物体的声道。
##
## 每个能出声的东西（角色、钟、以后的水滴 / 敌人……）挂一个，就拥有**一份独立的**
## 与世界等大的波动方程。场怎么算交给后端（`WaveField`）：
##   · ViewportWaveField —— 原来的 SubViewport ping-pong，一帧一步
##   · ComputeWaveField  —— 主 RenderingDevice，一帧 N 步
##
## 这里只剩"什么时候发声、什么时候停、听者在哪"，以及把后端产出的纹理交给
## canvas 合成层。发声只是往场里注入一次能量（一个 emit_radius 大小的高斯），
## **没有遮罩**：一声能传多远，由 damp、房间声学和中间撞上什么决定。
##
## 所有声源在世界那边（EchoWorld）按各自的音色（tint / gain）叠加成总的照亮。
## 场只在发声后推进 LIVE_SEC，然后停掉后端。

const VIEW_SHADER := preload("res://shaders/source_view.gdshader")
const VIEWPORT_FIELD := preload("res://scripts/wave/viewport/viewport_wave_field.gd")
const COMPUTE_FIELD_PATH := "res://scripts/wave/compute/compute_wave_field.gd"

## 一次发声后，场还值得推进多久；过了就停
const LIVE_SEC := 4.0
## 波速 = STRIDE × √cfl × 步率；两份后端共用同一组数
const STRIDE := 4.0
const CFL := 0.48
const BASE_SPEED := 166.2769

@export var damp := 0.9955          ## 模拟里每步的振幅衰减
@export var env_decay := 0.966      ## 模拟里包络（余晖）的衰减
@export var emit_radius := 14.0     ## 注入的高斯半径（这个物体的"嗓子"粗细）
## 到达听者耳朵多响算"听得清"：低于它的声音，它的整个波都不会画给玩家看
@export var hear_ref := 0.05
## 战争迷雾：true = 听不见就不画这一层
@export var hear_gate := false
@export var tint := Color(0.62, 0.82, 1.0)
@export var gain := 1.2
## 每次发声前把场清空。周期性的声音通常关掉
@export var clear_before_emit := false
## 声速是**全局**的：只认 EchoWorld.wave_speed（见 main.tscn 的 EchoWorld）。
## 声源不再有独立的 wave_speed，避免同一个世界里两种波速。

var _field: WaveField
var _view_mat: ShaderMaterial
var _world: Node
var _room_system: Node
var _step_acc := 0.0
var _live := 0.0
var _steps_per_second := 60.0
var _listener := Vector2.ZERO
var _compute_reason := ""


func _enter_tree() -> void:
	add_to_group("echo_sources")


func _ready() -> void:
	# 场景里的子节点比 Main._ready 先 ready；推迟一帧，等 EchoWorld 建好再挂
	_setup.call_deferred()


func _exit_tree() -> void:
	# 房间被销毁时声源跟着走：把合成层里那一份也摘掉，别留死视图
	if _world != null and is_instance_valid(_world) and _world.has_method("unregister"):
		_world.unregister(self)


# ---------------------------------------------------------------- 对外

## 在自己身上发声（用默认参数）
func emit(amp: float = 1.0, steps_wanted: int = 1) -> void:
	emit_at(global_position, amp, steps_wanted)


## 发声：amp 是注入振幅，steps 是连续注入的帧数。
func emit_at(origin: Vector2, amp: float = 1.0, steps_wanted: int = 1) -> void:
	if _field == null:
		return
	var clear_before := _live <= 0.0 or clear_before_emit
	_live = LIVE_SEC
	_field.inject(origin, amp, steps_wanted, clear_before)


## 统一发声入口：挂在它下面的 SoundAbility 通过这里发进来
func emit_sound(origin: Vector2, amp: float, steps_wanted: int) -> void:
	emit_at(origin, amp, steps_wanted)


## 外部清场（切房间时用）
func clear_field() -> void:
	_live = 0.0
	_step_acc = 0.0
	if _field != null:
		_field.clear()


## 切房前把"正在穿出房间"的那一薄片抄下来（Image）。
func capture_slab(dir: Vector2i) -> Image:
	return _field.capture_slab(dir) if _field != null else null


## 切房后把薄片写进新房间的入口侧。
func seed_slab(img: Image, dir: Vector2i) -> void:
	if _field == null or img == null or dir == Vector2i.ZERO:
		return
	_field.seed_slab(img, dir)
	_live = LIVE_SEC
	_step_acc = 0.0


func field_texture() -> Texture2D:
	return _field.texture() if _field != null else null


## CPU 采样入口（SoundSampler / 门 / 草）：后端自己决定从哪读。
func read_image() -> Image:
	return _field.read_image() if _field != null else null


## 听者位置：这一层要按"它在我耳朵这儿有多响"来决定整层的闸门
func set_listener(pos: Vector2) -> void:
	_listener = pos
	if _view_mat != null:
		_view_mat.set_shader_parameter("listener_px", pos)


func listener_position() -> Vector2:
	return _listener


## 切房后由 RoomSystem 调：声学和开口都按新房间重设
func refresh_room() -> void:
	_update_speed()
	if _field != null:
		_field.set_room(_room_acoustics(), _room_edges())


# ---------------------------------------------------------------- 装配

func _setup() -> void:
	_world = get_tree().get_first_node_in_group("echo_world")
	_room_system = get_tree().get_first_node_in_group("room_system")
	_listener = global_position
	if _world == null:
		push_warning("EchoSource: 场景里没有 echo_world，%s 的场不会显示" % name)

	var geo_tex: Texture2D = null
	var band_tex: Texture2D = null
	var alpha_tex: Texture2D = null
	if _world != null:
		geo_tex = _world.geometry_texture()
		band_tex = _world.band_texture()
		alpha_tex = _world.display_texture()

	_field = _make_field()
	_field.name = "Field"
	_field.damp = damp
	_field.env_decay = env_decay
	_field.emit_radius = emit_radius
	add_child(_field)
	_field.setup(geo_tex, alpha_tex)
	_update_speed()
	_field.set_room(_room_acoustics(), _room_edges())

	_view_mat = ShaderMaterial.new()
	_view_mat.shader = VIEW_SHADER
	_view_mat.set_shader_parameter("env_field", _field.texture())
	_view_mat.set_shader_parameter("band_tex", band_tex)
	_view_mat.set_shader_parameter("field_size", EchoField.FIELD_SIZE)
	_view_mat.set_shader_parameter("gain", gain)
	_view_mat.set_shader_parameter("tint", tint)
	_view_mat.set_shader_parameter("hear_ref", hear_ref)
	_view_mat.set_shader_parameter("hear_gate", 1.0 if hear_gate else 0.0)
	_view_mat.set_shader_parameter("listener_px", global_position)

	if _world != null:
		_world.register(self, _view_mat)


## 后端选择。设置 `echos/wave_backend`：
##   · "viewport" → 强制旧后端（驱动有 bug 时的逃生口）
##   · 其他值（默认 "compute"）→ 先探测平台，支持就 compute，不支持才退回
## 只探测"根本跑不了"的情况；shader 编译失败这类属于 bug，应该在开发期暴露，
## 不在这里悄悄吞掉。
func _make_field() -> WaveField:
	var mode := String(ProjectSettings.get_setting("echos/wave_backend", "compute"))
	if mode == "viewport":
		return VIEWPORT_FIELD.new() as WaveField

	if _compute_supported():
		var script := load(COMPUTE_FIELD_PATH) as Script
		if script != null:
			return script.new() as WaveField
		push_warning("EchoSource: 载入不了 %s，退回 SubViewport 后端" % COMPUTE_FIELD_PATH)
	else:
		push_warning("EchoSource: %s，退回 SubViewport 后端" % _compute_reason)
	return VIEWPORT_FIELD.new() as WaveField


## 平台能力探测。会调用一次主 RenderingDevice 的格式查询（只读，不提交任何东西）。
func _compute_supported() -> bool:
	_compute_reason = ""
	if DisplayServer.get_name() == "headless":
		_compute_reason = "headless 没有 RenderingDevice"
		return false
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		_compute_reason = "当前渲染后端没有 RenderingDevice（Compatibility）"
		return false
	var usage := (RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
			| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT)
	if not rd.texture_is_format_supported_for_usage(
			RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, usage):
		_compute_reason = "RGBA16F 不支持 storage/sampling/copy/update"
		return false
	return true


## 从声速反推每秒步数。两份后端用同一组 STRIDE / CFL，所以速度定义只有一份。
## 声速是全局的：EchoWorld.wave_speed > 项目设置 > BASE_SPEED。
func _update_speed() -> void:
	var s := 0.0
	var w := _world as EchoWorld
	if w != null:
		s = w.wave_speed
	if s <= 0.0:
		s = float(ProjectSettings.get_setting("echos/wave_speed", 0.0))
	if s <= 0.0:
		s = BASE_SPEED
	_steps_per_second = s / (STRIDE * sqrt(CFL))
	if _field != null:
		# 后端跑不到请求的步率时（viewport 封顶 60），按它实际能跑的来换算每步衰减。
		_field.set_step_rate(minf(_steps_per_second, _field.max_steps_per_frame() * 60.0))


# ---------------------------------------------------------------- 帧

func _process(delta: float) -> void:
	if _field == null:
		return

	if _live > 0.0:
		_live -= delta
		if _live <= 0.0:
			_live = 0.0

	# 没在响：只剩"挂起的清场/定场"要走完，走完就收渲染
	if _live <= 0.0:
		_step_acc = 0.0
		if _field.is_busy():
			_field.advance(0)
		else:
			_field.stop()
		_set_view_texture()
		return

	# 固定步率：一帧最多走后端允许的步数。
	# 低帧率时 accumulate 会给出 >1 步；SubViewport 后端只吃 1 步（所以会变慢），
	# compute 后端可以吃满，声速不再跟帧率挂钩。
	var tick := 1.0 / maxf(_steps_per_second, 1.0)
	_step_acc += delta
	var n := 0
	var max_n := _field.max_steps_per_frame()
	while _step_acc >= tick and n < max_n:
		_step_acc -= tick
		n += 1
	# 掉帧时别把积压无限带下去
	if _step_acc > tick:
		_step_acc = tick

	if n > 0:
		_field.advance(n)
	# 必须在 advance 之后挂：SubViewport 后端每步会换正面纹理，
	# 提前挂会永远晚一帧（compute 后端的 Texture2DRD 是同一个对象，这里只是顺手）。
	_set_view_texture()


## compute 后端在初始化完成前给的是占位纹理；每帧重挂一次，初始化完成后自然切过去。
func _set_view_texture() -> void:
	if _view_mat != null:
		_view_mat.set_shader_parameter("env_field", _field.texture())


# ---------------------------------------------------------------- 房间声学

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
