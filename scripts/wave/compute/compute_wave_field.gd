class_name ComputeWaveField
extends WaveField

## Compute 波场后端。
##
## 每个声源两块 480×270 的 RGBA16F 存储纹理（R = u, G = u-1, B = 包络），
## 用主 RenderingDevice 的 compute shader 推进一步。和 SubViewport 后端的区别：
##
##   · 一帧可以推 N 步（`advance(n)`），所以声速不再被渲染帧率封顶；
##   · 每步是一个 dispatch，多个 dispatch 记进**同一个 compute list**，
##     中间 `compute_list_add_barrier()`，不 submit / 不 sync；
##   · 显示用 Texture2DRD 指向最后一步写出的纹理，canvas 着色器照常采样。
##
## 所有 RD 资源都在 `RenderingServer.call_on_render_thread()` 里创建/释放——
## 主设备不允许从 GDScript 直接 submit/sync。
##
## 几何/显示纹理来自渲染器的 ViewportTexture，必须经
## `RenderingServer.texture_get_rd_texture()` 换成主 RD 的纹理 RID 才能进 uniform set。

const WAVE_SHADER_PATH := "res://shaders/compute/wave_step_compute.glsl"
const STRIDE := 4.0
const CFL := 0.48
const ABSORB_GAIN := 0.03
const GROUP := 8

## 一帧最多推几步。8 步 ≈ 1330 u/s；再高就靠这个值往上调。
@export var max_steps := 8

var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()
var _tex_rds: Array[RID] = [RID(), RID()]
var _sets: Array[RID] = [RID(), RID()]
var _env_set := RID()
var _sampler := RID()
var _inited := false
var _init_requested := false
var _retry := 0
var _bound := false
var _next := 0
var _steps := 0
var _amp := 0.0
var _emit_pos := Vector2.ZERO
var _tex: Texture2DRD
var _blank: Texture2D


func setup(p_geo: Texture2D, p_alpha: Texture2D) -> void:
	super.setup(p_geo, p_alpha)
	_tex = Texture2DRD.new()
	_blank = blank_texture()
	set_process(true)


func _process(_delta: float) -> void:
	if _inited or _init_requested:
		return
	# 场纹理的 RID 要等几何视口渲染过一帧才有效；没拿到就下一帧再试。
	_retry += 1
	if _retry < 2:
		return
	_init_requested = true
	var geo_rd := RID()
	var alpha_rd := RID()
	if geo_tex != null:
		geo_rd = RenderingServer.texture_get_rd_texture(geo_tex.get_rid())
	if alpha_tex != null:
		alpha_rd = RenderingServer.texture_get_rd_texture(alpha_tex.get_rid())
	if not geo_rd.is_valid() or not alpha_rd.is_valid():
		_init_requested = false
		return
	RenderingServer.call_on_render_thread(_init_compute.bind(geo_rd, alpha_rd))


# ---------------------------------------------------------------- 对外

func inject(pos: Vector2, amp: float, steps: int, clear_before: bool) -> void:
	_emit_pos = pos
	_amp = amp
	if clear_before and _inited:
		# 清场但保留即将注入的步数（和 canvas 版的 clear_frames 同义）
		_next = 0
		_tex.texture_rd_rid = _tex_rds[0]
		RenderingServer.call_on_render_thread(_clear_both)
	_steps = maxi(_steps, steps)


func clear() -> void:
	_steps = 0
	_next = 0
	if _inited:
		_tex.texture_rd_rid = _tex_rds[0]
		RenderingServer.call_on_render_thread(_clear_both)


func advance(n: int) -> void:
	if not _inited or n <= 0:
		return
	_bind_front()

	var flags: Array[bool] = []
	for i in n:
		if _steps > 0:
			flags.append(true)
			_steps -= 1
		else:
			flags.append(false)

	var src := _next
	var final := src ^ (n & 1)
	RenderingServer.call_on_render_thread(_dispatch.bind(src, _emit_pos, _amp, flags))
	_tex.texture_rd_rid = _tex_rds[final]
	_next = final


func max_steps_per_frame() -> int:
	return max_steps


func texture() -> Texture2D:
	_bind_front()
	return _tex if _bound else _blank


func read_image() -> Image:
	if not _inited:
		return null
	var data := _rd.texture_get_data(_tex_rds[_next], 0)
	if data.size() != EchoField.FW * EchoField.FH * 8:
		return null
	var img := Image.create_from_data(EchoField.FW, EchoField.FH, false,
			Image.FORMAT_RGBAH, data)
	return img


func seed_slab(img: Image, dir: Vector2i) -> void:
	if not _inited or img == null or dir == Vector2i.ZERO:
		return
	var rect := FieldSlab.rect(-dir, EchoField.FW, EchoField.FH)
	var slab := img
	if slab.get_format() != Image.FORMAT_RGBAH:
		slab = slab.duplicate()
		slab.convert(Image.FORMAT_RGBAH)
	var full := Image.create(EchoField.FW, EchoField.FH, false, Image.FORMAT_RGBAH)
	full.fill(Color(0, 0, 0, 1))
	full.blit_rect(slab, Rect2i(Vector2i.ZERO, slab.get_size()), rect.position)
	_next = 0
	_tex.texture_rd_rid = _tex_rds[0]
	RenderingServer.call_on_render_thread(_upload_seed.bind(full.get_data()))


# ---------------------------------------------------------------- 渲染线程

func _init_compute(geo_rd: RID, alpha_rd: RID) -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		push_error("ComputeWaveField: 没有主 RenderingDevice（需要 Forward+/Mobile）")
		return

	var file := load(WAVE_SHADER_PATH) as RDShaderFile
	if file == null:
		push_error("ComputeWaveField: 载入不了 %s" % WAVE_SHADER_PATH)
		return
	var spirv := file.get_spirv()
	var err := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not err.is_empty():
		push_error("ComputeWaveField: 编译失败：%s" % err)
		return

	_shader = _rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		push_error("ComputeWaveField: shader_create_from_spirv 失败")
		return
	_pipeline = _rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():
		push_error("ComputeWaveField: compute_pipeline_create 失败")
		return

	var fmt := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	var usage := (RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
			| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT)
	if not _rd.texture_is_format_supported_for_usage(fmt, usage):
		push_error("ComputeWaveField: RGBA16F 不支持 storage+sampling")
		return

	var tf := RDTextureFormat.new()
	tf.format = fmt
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = EchoField.FW
	tf.height = EchoField.FH
	tf.depth = 1
	tf.array_layers = 1
	tf.mipmaps = 1
	tf.usage_bits = usage

	for i in 2:
		_tex_rds[i] = _rd.texture_create(tf, RDTextureView.new(), [])
		_rd.texture_clear(_tex_rds[i], Color(0, 0, 0, 1), 0, 1, 0, 1)
	for i in 2:
		_sets[i] = _make_image_set(_tex_rds[i], _tex_rds[1 - i])

	_sampler = _rd.sampler_create(RDSamplerState.new())
	_env_set = _make_env_set(geo_rd, alpha_rd)
	_inited = true


func _make_image_set(src: RID, dst: RID) -> RID:
	var a := RDUniform.new()
	a.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	a.binding = 0
	a.add_id(src)

	var b := RDUniform.new()
	b.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	b.binding = 1
	b.add_id(dst)

	return _rd.uniform_set_create([a, b], _shader, 0)


func _make_env_set(geo_rd: RID, alpha_rd: RID) -> RID:
	var a := RDUniform.new()
	a.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	a.binding = 0
	a.add_id(_sampler)
	a.add_id(geo_rd)

	var b := RDUniform.new()
	b.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	b.binding = 1
	b.add_id(_sampler)
	b.add_id(alpha_rd)

	return _rd.uniform_set_create([a, b], _shader, 1)


## 一帧内推进 n 步：每步一个 dispatch，中间插 barrier；整段只有一个 compute list。
func _dispatch(src: int, emit_px: Vector2, amp: float, flags: Array) -> void:
	if not _inited:
		return
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	for i in flags.size():
		var s := src ^ (i & 1)
		_rd.compute_list_bind_uniform_set(list, _sets[s], 0)
		_rd.compute_list_bind_uniform_set(list, _env_set, 1)
		var pc := _push(emit_px, amp if flags[i] else 0.0)
		_rd.compute_list_set_push_constant(list, pc, pc.size())
		_rd.compute_list_dispatch(list,
				(EchoField.FW - 1) / GROUP + 1, (EchoField.FH - 1) / GROUP + 1, 1)
		if i < flags.size() - 1:
			_rd.compute_list_add_barrier(list)
	_rd.compute_list_end()


func _push(emit_px: Vector2, inject: float) -> PackedByteArray:
	# damp / env_decay / 吸声都是"每步"量，按 60 步/秒标定。
	# 步率变成 hz 时，把每步系数换成等效值，保证**每秒**的衰减和原来一致。
	var k := 60.0 / maxf(step_hz, 1.0)
	var env60 := 1.0 - (1.0 - env_decay) * (1.0 - acoustics.x * 0.9)
	var dm60 := damp * (1.0 - acoustics.y * 0.05)
	var env := pow(env60, k)
	var dm := pow(dm60, k)
	var absorb := 1.0 - pow(1.0 - ABSORB_GAIN, k)
	var sponge_absorb := 1.0 - pow(0.5, k)
	var f := PackedFloat32Array([
		float(EchoField.FW), float(EchoField.FH),
		emit_px.x, emit_px.y,
		edges.x, edges.y, edges.z, edges.w,
		inject, emit_radius, dm, env,
		CFL, STRIDE, AcousticMedium.IOR_MAX, 0.02,
		absorb, FieldSlab.SPONGE_W, sponge_absorb,
	])
	return f.to_byte_array()


func _clear_both() -> void:
	if not _inited:
		return
	for t in _tex_rds:
		_rd.texture_clear(t, Color(0, 0, 0, 1), 0, 1, 0, 1)


func _upload_seed(data: PackedByteArray) -> void:
	if not _inited:
		return
	_rd.texture_clear(_tex_rds[1], Color(0, 0, 0, 1), 0, 1, 0, 1)
	_rd.texture_update(_tex_rds[0], 0, data)


func _bind_front() -> void:
	if not _inited or _bound:
		return
	_tex.texture_rd_rid = _tex_rds[_next]
	_bound = true


func _exit_tree() -> void:
	if _tex != null:
		_tex.texture_rd_rid = RID()
	if _inited:
		RenderingServer.call_on_render_thread(_free)


func _free() -> void:
	if _rd == null or not _inited:
		return
	_inited = false
	for s in _sets:
		if s.is_valid():
			_rd.free_rid(s)
	if _env_set.is_valid():
		_rd.free_rid(_env_set)
	if _sampler.is_valid():
		_rd.free_rid(_sampler)
	if _pipeline.is_valid():
		_rd.free_rid(_pipeline)
	if _shader.is_valid():
		_rd.free_rid(_shader)
	for t in _tex_rds:
		if t.is_valid():
			_rd.free_rid(t)
