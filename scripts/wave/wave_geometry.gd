extends Node

## 世界几何：**每帧**把前景 / 中景 / 后景的图块现画成一张活纹理。
##
## 纹理通道（尺寸见 EchoField，1 texel = 1 世界单位）：
##   R = 吸声性（这块图块自己画不画）
##   G = 绝对折射率（1 = 空气，越大声速越慢）
##   B = 透声性（声音能不能穿过去）
##   A = 覆盖（这一格有图块；前景压中景、中景压后景）
##
## 为什么不直接共享主视口的画布：Godot 的 World2D 同时装着物理空间**和画布**，
## 共享 world_2d 等于共享整张画布，主视口画的东西会反馈回自己。
## 所以这里把每个 TileMapLayer 复制成"镜像层"放进几何视口单独画；
## 镜像层关掉碰撞，只负责出图。
##
## 因为每帧重画，TileSet 自带的动画（水波）和草被踩换帧都会立刻反映到几何上，
## 不会像烘死的那张一样永远停在 0 帧。
## 表面带（内侧 1 个 tile 像素）由 band.gdshader 从 A 通道现算。

const GEO_SHADER := preload("res://shaders/geo_tile.gdshader")
const BAND_SHADER := preload("res://shaders/band.gdshader")
const DEFAULT_ONE_WAY_ABSORB := 0.20
const MAX_BAND_PX := 4

## 1 个 tile 像素 = 几个场 texel。由图层缩放推出（2 倍缩放 → 2），不写死。
var band_px := 1

var _layers: Array = []
var _vp: SubViewport
var _canvas: Node2D
var _band_vp: SubViewport
var _band_mat: ShaderMaterial
var _mirrors: Dictionary = {}      # {图层下标: {source_id: TileMapLayer}}
var _atlas_cache: Dictionary = {}  # source_id → 参数图
var _mat_cache: Dictionary = {}    # source_id → 材质
var _dirty := false


func _enter_tree() -> void:
	# 图块被改过（草被踩）之后，改的人只要 call_group("wave_geometry", "request_sync")
	add_to_group("wave_geometry")


func setup(layers: Array) -> void:
	_layers = layers
	band_px = _derive_band_px()
	_build_geometry_view()
	_build_band_view()
	rebuild()


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		rebuild()


# ---------------------------------------------------------------- 对外

func texture() -> Texture2D:
	return _vp.get_texture() if _vp != null else null


func band_texture() -> Texture2D:
	return _band_vp.get_texture() if _band_vp != null else null


## 图块有改动，下一帧重画镜像层
func request_sync() -> void:
	_dirty = true


# ---------------------------------------------------------------- 装配

func _build_geometry_view() -> void:
	_vp = SubViewport.new()
	_vp.name = "GeometryView"
	_vp.size = EchoField.VIEW_SIZE
	_vp.disable_3d = true
	_vp.transparent_bg = true            # 空气 = (0,0,0,0)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(_vp)

	var cam := Camera2D.new()
	cam.name = "Camera"
	cam.position = EchoField.FIELD_SIZE * 0.5
	_vp.add_child(cam)
	cam.make_current()

	_canvas = Node2D.new()
	_canvas.name = "Mirrors"
	_vp.add_child(_canvas)


func _build_band_view() -> void:
	_band_vp = SubViewport.new()
	_band_vp.name = "BandView"
	_band_vp.size = EchoField.VIEW_SIZE
	_band_vp.disable_3d = true
	_band_vp.transparent_bg = false
	_band_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_band_vp)

	_band_mat = ShaderMaterial.new()
	_band_mat.shader = BAND_SHADER
	_band_mat.set_shader_parameter("geo_tex", _vp.get_texture())
	_band_mat.set_shader_parameter("field_size", EchoField.FIELD_SIZE)
	_band_mat.set_shader_parameter("band_px", band_px)

	var cr := ColorRect.new()
	cr.size = EchoField.FIELD_SIZE
	cr.material = _band_mat
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band_vp.add_child(cr)


## 图层缩放 → "1 个 tile 像素"在场里占几个 texel
func _derive_band_px() -> int:
	var s := 1.0
	for l in _layers:
		var layer := l as TileMapLayer
		if layer == null:
			continue
		s = maxf(s, (absf(layer.global_scale.x) + absf(layer.global_scale.y)) * 0.5)
	return clampi(roundi(s), 1, MAX_BAND_PX)


# ---------------------------------------------------------------- 镜像层

## 把三层的格子全部复制到镜像层。图块变了就整份重来（一次几百个 set_cell，够快）。
func rebuild() -> void:
	if _canvas == null:
		return
	for per_src in _mirrors.values():
		for m in per_src.values():
			(m as TileMapLayer).clear()

	for li in _layers.size():
		var layer := _layers[li] as TileMapLayer
		if layer == null or layer.tile_set == null:
			continue
		for cell in layer.get_used_cells():
			var src := layer.get_cell_source_id(cell)
			if src < 0:
				continue
			var mirror := _mirror_for(li, layer, src)
			mirror.set_cell(cell, src, layer.get_cell_atlas_coords(cell),
				layer.get_cell_alternative_tile(cell))


func _mirror_for(li: int, layer: TileMapLayer, src: int) -> TileMapLayer:
	var per_src: Dictionary = _mirrors.get(li, {})
	_mirrors[li] = per_src
	if per_src.has(src):
		return per_src[src]

	var m := TileMapLayer.new()
	m.name = "src%d" % src
	m.tile_set = layer.tile_set
	m.collision_enabled = false      # 只出图，不参与物理
	m.occlusion_enabled = false
	m.texture_filter = layer.texture_filter
	m.z_index = 2 - li                # 后景先画、前景后画 → 前景覆盖
	m.material = _geo_material(src)
	_canvas.add_child(m)
	m.global_transform = layer.global_transform
	per_src[src] = m
	return m


func _geo_material(src: int) -> ShaderMaterial:
	if _mat_cache.has(src):
		return _mat_cache[src]
	var m := ShaderMaterial.new()
	m.shader = GEO_SHADER
	m.set_shader_parameter("params_atlas", _params_atlas(src))
	_mat_cache[src] = m
	return m


# ---------------------------------------------------------------- 逐图块参数

## 和某个图集纹理等大的参数图：每个 tile 的矩形里填它自己的 (吸声, 折射率, 透声)。
## 着色器按图集 UV 采样，所以不用算 tile 下标，缩放/翻转都不影响。
func _params_atlas(src: int) -> Texture2D:
	if _atlas_cache.has(src):
		return _atlas_cache[src]

	var tset := _find_tileset()
	var atlas: TileSetAtlasSource = null
	if tset != null:
		atlas = tset.get_source(src) as TileSetAtlasSource
	var tex: Texture2D = atlas.texture if atlas != null else null
	if tex == null:
		_atlas_cache[src] = _blank_texture()
		return _atlas_cache[src]

	var img := Image.create(tex.get_width(), tex.get_height(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var abs_id := tset.get_custom_data_layer_by_name("absorb")
	var tr_id := tset.get_custom_data_layer_by_name("transmit")
	var ior_id := tset.get_custom_data_layer_by_name("ior")
	var has_phys := tset.get_physics_layers_count() > 0

	for i in atlas.get_tiles_count():
		var coords := atlas.get_tile_id(i)
		var td := atlas.get_tile_data(coords, 0)

		var one_way := false
		if td != null and has_phys:
			for pi in td.get_collision_polygons_count(0):
				if td.is_collision_polygon_one_way(0, pi):
					one_way = true
					break

		var absorb := 0.0
		if abs_id >= 0 and td != null:
			absorb = clampf(float(td.get_custom_data_by_layer_id(abs_id)), 0.0, 1.0)
		elif one_way:
			absorb = DEFAULT_ONE_WAY_ABSORB

		var transmit := 0.0
		if tr_id >= 0 and td != null:
			transmit = clampf(float(td.get_custom_data_by_layer_id(tr_id)), 0.0, 1.0)

		# 折射率：没填 = 空气（1.0）。水 1.33、玻璃 1.5 …… 越大声音越慢。
		# 上限 4 只是防呆：基础 cfl 贴着稳定上限，n < 1 会让场爆掉，所以下限锁在 1。
		var ior := 1.0
		if ior_id >= 0 and td != null:
			ior = clampf(float(td.get_custom_data_by_layer_id(ior_id)), 1.0, 4.0)

		# 动画图块的每一帧都是图集里的一块矩形，全都要填
		var col := Color(absorb, ior, transmit, 1.0)
		var frames := maxi(1, atlas.get_tile_animation_frames_count(coords))
		for f in frames:
			img.fill_rect(atlas.get_tile_texture_region(coords, f), col)

	var out := ImageTexture.create_from_image(img)
	_atlas_cache[src] = out
	return out


func _find_tileset() -> TileSet:
	for l in _layers:
		var layer := l as TileMapLayer
		if layer != null and layer.tile_set != null:
			return layer.tile_set
	return null


func _blank_texture() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
