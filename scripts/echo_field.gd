extends Node2D

## 回响场（射线法）：跑射线模拟 → 把命中压进 480x270 纹理 → 着色器合成波前与残影。
##
## 决定项 A = 硬清空：每次发声重建整张命中纹理，不保留上一场的残影。
## 因此残影可以用解析式算出（e * pow(k, now - t_arrive)），不需要反馈缓冲。
##
## 铺点方式：端点圆片 + 同圈相邻命中连线。
## 只铺圆片会在远处留下等距断点（相邻射线落点间距 = dist * 角步长），
## 连线后覆盖率与角度分辨率无关，表面是连续的。

const FW := 480
const FH := 270
const MAX_T := 2.0

var geom: LevelGeometry
var half_life := 2.5          # 残影半衰（秒）
var dist_k := 160.0           # 距离衰减常数 K
var win := 0.12
var front_gain := 1.5

var _data := PackedByteArray()
var _img: Image
var _tex: ImageTexture
var _mat: ShaderMaterial
var _sub: SubViewport
var _layer: CanvasLayer
var _now := 99.0

# 统计
var last_hits := 0
var last_cast_ms := 0.0
var last_splat_ms := 0.0
var last_summary := "—"


func _ready() -> void:
	geom = LevelGeometry.new()

	_data.resize(FW * FH * 4)
	_img = Image.create(FW, FH, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 1))
	_tex = ImageTexture.create_from_image(_img)

	var sh: Shader = load("res://shaders/echo_field.gdshader")
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("hits", _tex)
	_mat.set_shader_parameter("now", _now)
	_mat.set_shader_parameter("max_t", MAX_T)
	_mat.set_shader_parameter("win", win)
	_mat.set_shader_parameter("half_life", half_life)
	_mat.set_shader_parameter("front_gain", front_gain)
	_mat.set_shader_parameter("field_size", Vector2(FW, FH))

	_sub = SubViewport.new()
	_sub.size = Vector2i(FW, FH)
	_sub.disable_3d = true
	_sub.transparent_bg = false
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(_sub)

	var cr := ColorRect.new()
	cr.size = Vector2(FW, FH)
	cr.material = _mat
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub.add_child(cr)

	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	_layer = layer

	var tr := TextureRect.new()
	tr.texture = _sub.get_texture()
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(tr)
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	if _now < 60.0:
		_now += delta
		_mat.set_shader_parameter("now", _now)


## 发声。
func ping(origin: Vector2) -> void:
	var t0 := Time.get_ticks_usec()
	var res := EchoSim.cast(origin, geom, EchoSim.RAYS, EchoSim.MAX_REFLECT, dist_k)
	var t1 := Time.get_ticks_usec()
	_splat(res["hits"], res["rings"], origin)
	var t2 := Time.get_ticks_usec()

	_now = 0.0
	_mat.set_shader_parameter("now", _now)

	var hits: PackedFloat32Array = res["hits"]
	last_hits = hits.size() / EchoSim.HIT_STRIDE
	last_cast_ms = (t1 - t0) / 1000.0
	last_splat_ms = (t2 - t1) / 1000.0
	last_summary = EchoSim.summarize(hits)


func _splat(hits: PackedFloat32Array, rings: Array, origin: Vector2) -> void:
	_data.fill(0)

	var n_rays := EchoSim.RAYS
	var stride := EchoSim.HIT_STRIDE

	# 1) 端点圆片：给表面一点厚度，避免 1 texel 的硬线
	var n := hits.size() / stride
	for i in n:
		var o := i * stride
		var hx := hits[o]
		var hy := hits[o + 1]
		var dist := Vector2(hx - origin.x, hy - origin.y).length()
		var r := clampf(dist * (TAU / float(n_rays)) * 0.5, 0.8, 2.0)
		var flag := 255 if hits[o + 7] > 0.5 else int(hits[o + 6])
		var x0 := maxi(0, int(hx - r))
		var x1 := mini(FW - 1, int(hx + r) + 1)
		var y0 := maxi(0, int(hy - r))
		var y1 := mini(FH - 1, int(hy + r) + 1)
		var r2 := r * r
		for yy in range(y0, y1 + 1):
			var dy := float(yy) - hy
			for xx in range(x0, x1 + 1):
				var dx := float(xx) - hx
				if dx * dx + dy * dy > r2:
					continue
				_put(xx, yy, hits[o + 4], hits[o + 5], flag)

	# 2) 同圈相邻射线连线：把断点填平（扇面是环形的，末尾连回开头）
	#    只有"打到同一条线段"的两个相邻命中才连——否则会从台子上沿直接拉一条
	#    斜线到地面。用命中面编号判定是精确的，用弦长阈值判定会在掠射角下误杀。
	var rs := EchoSim.RING_STRIDE
	for ring in rings:
		var rg: PackedFloat32Array = ring
		for i in n_rays:
			var a := i * rs
			var c := ((i + 1) % n_rays) * rs
			if not is_finite(rg[a]) or not is_finite(rg[c]):
				continue
			if rg[a + 5] != rg[c + 5]:
				continue
			_line(rg[a], rg[a + 1], rg[a + 2], rg[a + 3], int(rg[a + 4]),
				rg[c], rg[c + 1], rg[c + 2], rg[c + 3], int(rg[c + 4]))

	_img.set_data(FW, FH, false, Image.FORMAT_RGBA8, _data)
	_tex.update(_img)


## 两个命中点之间的直线填充（DDA），能量沿线路插值
func _line(x0: float, y0: float, e0: float, t0: float, f0: int,
		x1: float, y1: float, e1: float, t1: float, f1: int) -> void:
	var dx := x1 - x0
	var dy := y1 - y0
	var steps := int(maxf(absf(dx), absf(dy)))
	if steps <= 0:
		return
	var sx := dx / float(steps)
	var sy := dy / float(steps)
	var inv := 1.0 / float(steps)
	for k in steps + 1:
		var u := float(k) * inv
		_put(int(round(x0 + sx * k)), int(round(y0 + sy * k)),
			lerpf(e0, e1, u), lerpf(t0, t1, u), f0)


## 写一个 texel：能量取最大，避免叠加过曝；时间跟随最亮的那个命中
func _put(x: int, y: int, e: float, t: float, flag: int) -> void:
	if x < 0 or y < 0 or x >= FW or y >= FH:
		return
	var eb := int(clampf(e, 0.0, 1.0) * 255.0)
	if eb <= 0:
		return
	var idx := (y * FW + x) * 4
	if _data[idx] >= eb:
		return
	_data[idx] = eb
	_data[idx + 1] = int(clampf(t / MAX_T, 0.0, 1.0) * 255.0)
	_data[idx + 2] = flag
	_data[idx + 3] = 255


func set_active(v: bool) -> void:
	visible = v
	if _layer:
		_layer.visible = v
	if _sub:
		_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS if v else SubViewport.UPDATE_DISABLED


func clear() -> void:
	_data.fill(0)
	_img.set_data(FW, FH, false, Image.FORMAT_RGBA8, _data)
	_tex.update(_img)
	_now = 99.0
	_mat.set_shader_parameter("now", _now)
	last_hits = 0
	last_summary = "—"


## 调试：把命中数据存成 PNG（R=能量 G=到达时间 B=阶数/终止标记）
func save_hits(path: String) -> void:
	var err := _img.save_png(path)
	print("[hits] %s err=%d" % [path, err])
