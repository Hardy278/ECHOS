extends Node2D

## 回响场（GPU 波动方程），多声源 + 子帧推进。
##
## 子帧：一个 SubViewport 里按顺序画 SUBSTEPS 个全屏四边形，每个用
## hint_screen_texture 读上一个刚写的结果。同一条渲染通道内按绘制顺序执行，
## 所以一次 viewport 渲染就推进 SUBSTEPS 步。这样波速由 SUBSTEPS×帧率 决定，
## STRIDE 可以降回 2 换取细腻度（也避免跨步穿透薄墙）。
##
## 多声道：不同声源射程差 6 倍，叠加后无法按来源分开衰减，所以每个声源
## 一张独立的场纹理，显示时各自套自己的 reach/falloff 再合成。

const TILE_FIELD := preload("res://scripts/tile_field.gd")

const FW := 480
const FH := 270

const STRIDE := 4          # 邻域偏移（texel）。格点尺度 = STRIDE，波速 = STRIDE × √CFL × 60
## 三者是绑死的：格点越细 → STRIDE 越小 → 波速越慢。
##   1 → 41 单位/秒（格点最细，穿屏 12 秒）
##   2 → 83
##   4 → 166（当前）
##   6 → 249
##   8 → 333（格点明显，已到平台厚度的临界）
const CFL := 0.48          # 必须 <= 0.5
## 子帧结论：SUBSTEPS 只能是 1。
## Godot 的 2D hint_screen_texture 是每帧一次的快照，同一 viewport 内画 N 个四边形
## 读到的是同一份帧初状态，第 2..N 个会把第 1 个刚写入的脉冲覆盖掉（实测全黑）。
## 真子帧需要 RenderingDevice 计算着色器 + 显式 barrier。
const SUBSTEPS := 1
const STEPS_HZ := 60.0     # 每秒总步数（= 帧率上限，这是硬限制）

const TICK_DT := SUBSTEPS / STEPS_HZ     # 每画一次 viewport 的间隔

## 每个声源一套参数。reach/falloff 在显示层生效，env/damp 在模拟里生效。
## 参照尺度：房间 480×270，对角线 550；出生点到最远屋角约 338。
## 所以 reach 必须小于 338，否则等于全图无衰减。
const CH_PARAMS := [
	{"key": "hb", "reach": 70.0, "falloff": 2.40, "emit_r": 8.0, "env": 0.9600, "damp": 0.9950},
	{"key": "land", "reach": 127.0, "falloff": 1.90, "emit_r": 12.0, "env": 0.9660, "damp": 0.9955},
	{"key": "shout", "reach": 280.0, "falloff": 1.60, "emit_r": 24.0, "env": 0.9720, "damp": 0.9960},
]
const CH_HB := 0
const CH_LAND := 1
const CH_SHOUT := 2

## 三层 TileMapLayer（前景 / 中景 / 后景），由主场景在 add_child 之前赋值
var tilemap: TileMapLayer
var tilemap_mid: TileMapLayer
var tilemap_bg: TileMapLayer
var _chs: Array = []
var _mat_tex: ImageTexture
var _band_tex: ImageTexture
var _classes_tex: ImageTexture  # R=实体 G=单向 B=装饰，F2 调试用
var _tile_mats: Array = []      # 两个 TileMapLayer 的光照材质
var _view_mat: ShaderMaterial
var _view_tr: TextureRect
var _layer: CanvasLayer

var _active := false
var _resetting := true
var _reset_frames := 0
var _step_acc := 0.0

var last_peak := 0.0

## 显示参数：只在 _ready 应用一次，运行期不再变（要调就改默认值）
var view_params := {"bg_gain": 1.15, "edge_gain": 4.0, "bg_blur": 1.20}

## 给 HUD 的一行内部状态，_ready 里算一次
var _debug_line := ""


func _apply_view_params() -> void:
	for k in view_params:
		_view_mat.set_shader_parameter(k, view_params[k])


func _ready() -> void:
	# 几何从 TileMapLayer 的碰撞多边形烘出来：物理撞到的墙和声音反弹的墙是同一批墙
	var baked := TILE_FIELD.bake([tilemap, tilemap_mid, tilemap_bg], Vector2i(FW, FH))
	_mat_tex = baked["mat"]
	_band_tex = baked["band"]
	_classes_tex = baked["classes"]
	print("[回响场] %s" % baked["summary"])

	var step_shader: Shader = load("res://shaders/wave_step_fb.gdshader")

	for p in CH_PARAMS:
		var vp := SubViewport.new()
		vp.size = Vector2i(FW, FH)
		vp.disable_3d = true
		vp.transparent_bg = false
		vp.use_hdr_2d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
		add_child(vp)

		var mats: Array[ShaderMaterial] = []
		for k in SUBSTEPS:
			var m := ShaderMaterial.new()
			m.shader = step_shader
			m.set_shader_parameter("mat_tex", _mat_tex)
			m.set_shader_parameter("field_size", Vector2(FW, FH))
			m.set_shader_parameter("stride", float(STRIDE))
			m.set_shader_parameter("cfl", CFL)
			m.set_shader_parameter("damp", p["damp"])
			m.set_shader_parameter("env_decay", p["env"])
			m.set_shader_parameter("hf_damp", 0.02)   # 抑制棋盘格，别开太大否则会吃掉物理波
			m.set_shader_parameter("inject_r", p["emit_r"])
			m.set_shader_parameter("emit_px", Vector2(240, 238))
			m.set_shader_parameter("inject", 0.0)
			m.set_shader_parameter("reset", 1.0)
			mats.append(m)

			var cr := ColorRect.new()
			cr.size = Vector2(FW, FH)
			cr.material = m
			cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cr.position = Vector2.ZERO
			vp.add_child(cr)

		_chs.append({
			"vp": vp, "mats": mats,
			"amp": 0.0, "steps": 0,
			"emit_px": Vector2(240, 238),
			"src_px": Vector2(240, 238),
		})

	_layer = CanvasLayer.new()
	_layer.layer = -1
	add_child(_layer)

	_view_mat = ShaderMaterial.new()
	_view_mat.shader = load("res://shaders/wave_view.gdshader")
	_view_mat.set_shader_parameter("mat_tex", _mat_tex)
	_view_mat.set_shader_parameter("band_tex", _band_tex)
	_view_mat.set_shader_parameter("field_size", Vector2(FW, FH))
	_view_mat.set_shader_parameter("field_hb", _chs[CH_HB]["vp"].get_texture())
	_view_mat.set_shader_parameter("field_land", _chs[CH_LAND]["vp"].get_texture())
	_view_mat.set_shader_parameter("field_shout", _chs[CH_SHOUT]["vp"].get_texture())
	_view_mat.set_shader_parameter("listener_px", Vector2(240, 238))
	_view_mat.set_shader_parameter("rf_hb",
		Vector2(CH_PARAMS[CH_HB]["reach"], CH_PARAMS[CH_HB]["falloff"]))
	_view_mat.set_shader_parameter("rf_land",
		Vector2(CH_PARAMS[CH_LAND]["reach"], CH_PARAMS[CH_LAND]["falloff"]))
	_view_mat.set_shader_parameter("rf_shout",
		Vector2(CH_PARAMS[CH_SHOUT]["reach"], CH_PARAMS[CH_SHOUT]["falloff"]))

	_view_tr = TextureRect.new()
	_view_tr.texture = _chs[CH_HB]["vp"].get_texture()
	_view_tr.material = _view_mat
	_view_tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_view_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view_tr.stretch_mode = TextureRect.STRETCH_SCALE
	_view_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_view_tr)
	_view_tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_apply_view_params()
	_setup_tile_materials()
	_debug_line = "子步 %d · stride %d · 波速 %.0f 单位/秒" % [SUBSTEPS, STRIDE, wave_speed()]
	_active = true
	_begin_reset()


func _process(delta: float) -> void:
	if not _active:
		return

	if _resetting:
		_reset_frames += 1
		for c in _chs:
			c["vp"].render_target_update_mode = SubViewport.UPDATE_ONCE
		if _reset_frames >= 2:
			_resetting = false
			for c in _chs:
				for m in c["mats"]:
					m.set_shader_parameter("reset", 0.0)
		return

	_step_acc += delta
	if _step_acc < TICK_DT:
		return
	_step_acc = minf(_step_acc - TICK_DT, TICK_DT)

	for c in _chs:
		# 注入只落在第 0 个子步上
		if c["steps"] > 0:
			c["steps"] -= 1
			c["mats"][0].set_shader_parameter("inject", c["amp"])
		else:
			c["mats"][0].set_shader_parameter("inject", 0.0)
		c["vp"].render_target_update_mode = SubViewport.UPDATE_ONCE


# ---------------------------------------------------------------- 发声接口

func emit_heartbeat(origin: Vector2, amp: float = 0.045) -> void:
	_emit(CH_HB, origin, amp, 2)


func emit_landing(origin: Vector2, amp: float) -> void:
	_emit(CH_LAND, origin, amp, 1)


## 喊叫：除了注入，还要把这一声道自己的衰减锚点挪到这里
func ping(origin: Vector2, amp: float = 0.5) -> void:
	_emit(CH_SHOUT, origin, amp, 2)
	_set_src(CH_SHOUT, origin)


func _emit(ch: int, origin: Vector2, amp: float, steps: int) -> void:
	var c: Dictionary = _chs[ch]
	c["emit_px"] = origin
	c["amp"] = amp
	c["steps"] = maxi(c["steps"], steps)
	for m in c["mats"]:
		(m as ShaderMaterial).set_shader_parameter("emit_px", origin)


## 听者位置：距离衰减场的中心，每帧跟随角色。
## 场里只有波真正到过的位置才有能量，所以移动遮罩不会造出信息。
func set_listener(pos: Vector2) -> void:
	if _view_mat:
		_view_mat.set_shader_parameter("listener_px", pos)
	for m in _tile_mats:
		(m as ShaderMaterial).set_shader_parameter("listener_px", pos)


func _set_src(ch: int, origin: Vector2) -> void:
	# 保留接口：如果以后要改成"衰减锚在发声点"，在这里更新即可
	pass


# ---------------------------------------------------------------- 状态

func set_active(v: bool) -> void:
	_active = v
	if _layer:
		_layer.visible = v
	if not v:
		for c in _chs:
			c["vp"].render_target_update_mode = SubViewport.UPDATE_DISABLED
	else:
		_begin_reset()


func _begin_reset() -> void:
	_resetting = true
	_reset_frames = 0
	_step_acc = 0.0
	for c in _chs:
		c["steps"] = 0
		c["amp"] = 0.0
		for m in c["mats"]:
			(m as ShaderMaterial).set_shader_parameter("reset", 1.0)
			(m as ShaderMaterial).set_shader_parameter("inject", 0.0)


func clear() -> void:
	_begin_reset()


func is_settled() -> bool:
	return not _resetting


func wave_speed() -> float:
	return STRIDE * sqrt(CFL) * STEPS_HZ


## 一行内部状态，交给 HUD 显示（HUD 不反向去读这里的常量）
func debug_line() -> String:
	return _debug_line


# ---------------------------------------------------------------- 图块光照

## 图块本身不发光：只有回响场照亮的地方才显形（暗处透明，露出身后的行波）
func _setup_tile_materials() -> void:
	if tilemap != null:
		tilemap.material = _make_tile_material(1.0)
	if tilemap_mid != null:
		tilemap_mid.material = _make_tile_material(0.80)
	if tilemap_bg != null:
		tilemap_bg.material = _make_tile_material(0.55)


func _make_tile_material(layer_gain: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/tile_light.gdshader")
	m.set_shader_parameter("field_hb", _chs[CH_HB]["vp"].get_texture())
	m.set_shader_parameter("field_land", _chs[CH_LAND]["vp"].get_texture())
	m.set_shader_parameter("field_shout", _chs[CH_SHOUT]["vp"].get_texture())
	m.set_shader_parameter("field_size", Vector2(FW, FH))
	m.set_shader_parameter("listener_px", Vector2(240, 238))
	for i in [CH_HB, CH_LAND, CH_SHOUT]:
		var key := "rf_" + str(CH_PARAMS[i]["key"])
		m.set_shader_parameter(key, Vector2(CH_PARAMS[i]["reach"], CH_PARAMS[i]["falloff"]))
	m.set_shader_parameter("gain", view_params["edge_gain"])
	m.set_shader_parameter("blur_px", view_params["bg_blur"])
	m.set_shader_parameter("layer_gain", layer_gain)
	_tile_mats.append(m)
	return m


# ---------------------------------------------------------------- 调试

## 分类图（R=实体 G=单向 B=装饰），F2 用它看烘出来的东西对不对
func debug_texture() -> Texture2D:
	return _classes_tex
