class_name ViewportWaveField
extends WaveField

## 原来的 SubViewport ping-pong 后端。
##
## 每个声源两块 480×270 的 HDR SubViewport，互相采样对方的纹理，轮流当"正面"。
## **一帧只能推进一步**：Godot 的视口渲染排在当帧所有 _process 之后，
## 同帧里连推两步会读到上一步还没写进去的内容（所以 `max_steps_per_frame()` 是 1）。

const STEP_SHADER := preload("res://shaders/viewport/wave_step_fb.gdshader")
## 清场要写两帧（一帧写不满整张 HDR 缓冲的边角）
const CLEAR_FRAMES := 2
## 搬过来的能量打个折：只有开口那一部分该穿过去
const SEED_GAIN := 0.7
## α = 1 的材质每步损失多少振幅。60 步/秒，0.03 等于一秒掉到 0.16。
const ABSORB_GAIN := 0.03
const STRIDE := 4.0
const CFL := 0.48

var _vps: Array = []             ## 两块场缓冲，轮流当"正面"
var _mats: Array = []            ## 和两块缓冲对应的步进材质
var _front := 0                   ## 当前正面是 _vps[_front]
var _mat: ShaderMaterial        ## 步进 + 注入
var _amp := 0.0
var _steps := 0
var _clear_frames := 0
var _seed_frames := 0
var _emit_pos := Vector2.ZERO
var _seed_tex: Texture2D


func setup(p_geo: Texture2D, p_alpha: Texture2D) -> void:
	super.setup(p_geo, p_alpha)

	for k in 2:
		var vp := SubViewport.new()
		vp.name = "Field%d" % k
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
	_set_param("alpha_tex", alpha_tex)
	_set_param("absorb_gain", ABSORB_GAIN)
	_write_tuning()

	_clear_frames = CLEAR_FRAMES      # 新场从全 0 起步


func set_room(p_acoustics: Vector2, p_edges: Vector4) -> void:
	super.set_room(p_acoustics, p_edges)
	_write_tuning()


# ---------------------------------------------------------------- 对外

func inject(pos: Vector2, amp: float, steps: int, clear_before: bool) -> void:
	_emit_pos = pos
	_amp = amp
	_steps = maxi(_steps, steps)
	if clear_before:
		_clear_frames = CLEAR_FRAMES
	if _mat != null:
		_write_tuning()          # 房间可能换过了，声学跟着换
		_set_param("emit_px", _emit_pos)


func clear() -> void:
	_clear_frames = CLEAR_FRAMES
	_steps = 0


func advance(n: int) -> void:
	if _vps.is_empty():
		return
	# 清场 / 定场是挂起的：即使调用方给 0 步，也要把这两帧走完
	if _clear_frames > 0 or _seed_frames > 0:
		n = maxi(n, 1)
	if n <= 0:
		return

	# 清场优先：这两帧只把场写成 0，不注入
	if _clear_frames > 0:
		_masks(true, false)
		_step_render()
		_clear_frames -= 1
		return

	# 定场：清完之后写一帧薄片，之后交给场自己演化
	if _seed_frames > 0:
		_masks(true, true)
		_step_render()
		_seed_frames -= 1
		return

	_masks(false, false)
	if _steps > 0:
		_set_param("inject", _amp)
		_steps -= 1
	else:
		_set_param("inject", 0.0)
	_step_render()


func stop() -> void:
	if _vps.is_empty():
		return
	(_vps[_front] as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED


func is_busy() -> bool:
	return _clear_frames > 0 or _seed_frames > 0


func max_steps_per_frame() -> int:
	return 1


func texture() -> Texture2D:
	return (_vps[_front] as SubViewport).get_texture() if not _vps.is_empty() else null


func seed_slab(img: Image, dir: Vector2i) -> void:
	if _mat == null or img == null or dir == Vector2i.ZERO:
		return
	_seed_tex = ImageTexture.create_from_image(img)
	_set_param("seed_tex", _seed_tex)
	_set_param("seed_size", Vector2(img.get_width(), img.get_height()))
	var rect := FieldSlab.rect(-dir, EchoField.FW, EchoField.FH)
	_set_param("seed_at", Vector2(rect.position))
	_seed_frames = 1
	_steps = 0


# ---------------------------------------------------------------- 内部

func _make_step_material(p_geo: Texture2D, src_tex: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = STEP_SHADER
	m.set_shader_parameter("geo_tex", p_geo)
	m.set_shader_parameter("src_tex", src_tex)
	m.set_shader_parameter("field_size", EchoField.FIELD_SIZE)
	m.set_shader_parameter("stride", STRIDE)
	m.set_shader_parameter("cfl", CFL)
	m.set_shader_parameter("ior_max", AcousticMedium.IOR_MAX)
	m.set_shader_parameter("hf_damp", 0.02)
	m.set_shader_parameter("inject_r", emit_radius)
	m.set_shader_parameter("emit_px", Vector2.ZERO)
	m.set_shader_parameter("inject", 0.0)
	m.set_shader_parameter("reset", 0.0)
	m.set_shader_parameter("sponge_w", FieldSlab.SPONGE_W)
	m.set_shader_parameter("seed", 0.0)
	m.set_shader_parameter("seed_gain", SEED_GAIN)
	return m


## reset / seed 两个 uniform 的唯二写入口（见原 EchoSource 的注释）
func _masks(reset: bool, seed: bool) -> void:
	_set_param("reset", 1.0 if reset else 0.0)
	_set_param("seed", 1.0 if seed else 0.0)


## 两块缓冲轮流当"正面"：往背面写一步，然后把背面变成正面
func _step_render() -> void:
	var back := 1 - _front
	(_vps[back] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
	_front = back
	(_vps[1 - back] as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED


## 两块材质的参数一起写
func _set_param(name: StringName, v) -> void:
	for m in _mats:
		(m as ShaderMaterial).set_shader_parameter(name, v)


## 房间给倍率，物体保留自己的嗓子：reverb 让余晖拖长，absorb 让能量掉得更快。
## 顺带把"哪几条边是开口"写进去——开口那边是吸声层，不是反射壁。
func _write_tuning() -> void:
	if _mat == null:
		return
	# damp / env_decay / 吸声都是"每步"量，按 60 步/秒标定。
	# 这个后端一帧只能一步，step_hz 会被 EchoSource 封到 60，所以通常 k = 1。
	var k := 60.0 / maxf(step_hz, 1.0)
	var env60 := 1.0 - (1.0 - env_decay) * (1.0 - acoustics.x * 0.9)
	var dm60 := damp * (1.0 - acoustics.y * 0.05)
	_set_param("env_decay", pow(env60, k))
	_set_param("damp", pow(dm60, k))
	_set_param("sponge_edges", edges)
	_set_param("absorb_gain", 1.0 - pow(1.0 - ABSORB_GAIN, k))
	_set_param("sponge_absorb", 1.0 - pow(0.5, k))
