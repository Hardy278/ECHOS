extends Node

## 世界几何：**每帧**把前景 / 中景 / 后景的图块现画成一张活纹理。
##
## 纹理通道（尺寸见 EchoField，1 texel = 1 世界单位）：
##   R = surface（显现边缘：**由声阻抗 Z 推出**，见 surface_from_z）
##   G = 绝对折射率 c（1 = 空气，越大声速越慢）
##   B = 透声性 transmit（**由声阻抗 Z 推出**，见 transmit_from_z）
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
const DISPLAY_SHADER := preload("res://shaders/geo_display.gdshader")
const BAND_SHADER := preload("res://shaders/band.gdshader")
const BODY_SHADER := preload("res://shaders/geo_body.gdshader")
const BODY_ALPHA_SHADER := preload("res://shaders/geo_body_alpha.gdshader")
## 单面平台默认的"显现纹理"值：0.8。
## 它以前是靠 absorb=0.2（把 v 乘 0.8）压暗的，现在换成显式的不透明度上限。
const DEFAULT_ONE_WAY_SHOW := 0.8
## 折射介质默认的"显现纹理"值：0.6。它以前是 tile_light 里一句
## `g.g > 1.01 ? 0.6 : 1.0` 的硬编码（水看起来要"暗一点、像看进去"）。
const DEFAULT_REFRACTIVE_SHOW := 0.6
## 层表里没有实体层时的兜底 z：压在所有图块层之上
const ENTITY_Z_FALLBACK := 3
const MAX_BAND_PX := 4

## Z / c / α 怎么变成纹理通道，全在 AcousticMedium 里（图块和实体共用同一套）。


## 1 个 tile 像素 = 几个场 texel。由图层缩放推出（2 倍缩放 → 2），不写死。
var band_px := 1

var _layers: Array = []
var _vp: SubViewport
var _canvas: Node2D
var _display_vp: SubViewport
var _display_canvas: Node2D
var _band_vp: SubViewport
var _band_mat: ShaderMaterial
var _mirrors: Dictionary = {}      # {图层下标: {source_id: TileMapLayer}}
var _display_mirrors: Dictionary = {}   # 同上，但画进显示视口
var _shapes: Dictionary = {}       # AcousticShape → CanvasItem（画在几何视口里的声学形状）
var _shape_display: Dictionary = {}  # 同上，但画进显示视口（只写 α）
var _atlas_cache: Dictionary = {}  # source_id → 几何参数图
var _display_atlas_cache: Dictionary = {}  # source_id → 显示参数图
var _mat_cache: Dictionary = {}    # source_id → 几何材质
var _display_mat_cache: Dictionary = {}  # source_id → 显示材质
var _dirty := false


func _enter_tree() -> void:
	# 图块被改过（草被踩）之后，改的人只要 call_group("wave_geometry", "request_sync")
	add_to_group("wave_geometry")


func setup(layers: Array) -> void:
	_layers = layers
	band_px = _derive_band_px()
	_build_geometry_view()
	_build_display_view()
	_build_band_view()
	rebuild()


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		rebuild()
	_sync_shapes()


# ---------------------------------------------------------------- 对外

func texture() -> Texture2D:
	return _vp.get_texture() if _vp != null else null


func band_texture() -> Texture2D:
	return _band_vp.get_texture() if _band_vp != null else null


## 每块砖"显现纹理"的值（R 通道）+ 覆盖（A 通道）。
## tile_light 用世界 UV 采样它；没覆盖的地方（比如实体）要当成 show = 1。
func display_texture() -> Texture2D:
	return _display_vp.get_texture() if _display_vp != null else null


## 图块有改动，下一帧重画镜像层
func request_sync() -> void:
	_dirty = true


## 换房间：镜像层整批作废，换成新房间的三层图块。
## 视口和表面带那张纹理不重建——对象一直是同一个，只是内容换了。
func rebind(layers: Array) -> void:
	_drop_mirrors()
	_atlas_cache.clear()      # 万一换了 TileSet，参数图必须重做
	_mat_cache.clear()
	_display_mat_cache.clear()
	_layers = layers
	band_px = _derive_band_px()
	if _band_mat != null:
		_band_mat.set_shader_parameter("band_px", band_px)
	rebuild()


## 镜像层是画在视口里的副本，换房间时整批扔掉
func _drop_mirrors() -> void:
	for pair in [[_mirrors, _canvas], [_display_mirrors, _display_canvas]]:
		var store: Dictionary = pair[0]
		var canvas = pair[1]
		for per_src in store.values():
			for m in per_src.values():
				var node := m as Node
				if is_instance_valid(node):
					if canvas != null:
						(canvas as Node).remove_child(node)
					node.queue_free()
		store.clear()


# ---------------------------------------------------------------- 声学形状

## 实体不是图块，所以它们的"声学形状"每帧现摆：由形状自己造一个画布元素
## （贴图镜像是 Sprite2D，折线是 Line2D），画进几何视口，位置直接跟实体走。
## 所以会动的实体（包括会摆的草）也有声音形状。
##
## 这里不认识具体的形状类型——只认 AcousticShape 那两个方法。加一种新形状
## （比如一个多边形），只要写一个子类，这边一行都不用改。
func _sync_shapes() -> void:
	if _canvas == null:
		return

	var def := _entity_layer()
	if def != null and not def.acoustic:
		# 实体层被设成纯装饰：不建声学形状（已经建好的由 _sweep_shapes 收掉）
		_sweep_shapes()
		return
	var z := def.z if def != null else ENTITY_Z_FALLBACK

	for n in get_tree().get_nodes_in_group("acoustic_shapes"):
		var shape := n as AcousticShape
		if shape == null:
			continue
		_sync_one_shape(shape, z, false)
		_sync_one_shape(shape, z, true)
	_sweep_shapes()


## 一块声学形状在几何视口、显示视口里各有一面镜子（同一个节点不能同时在两个视口里，
## 和瓦片镜像是一个道理）。几何那面写 surface/ior/transmit，显示那面只写吸声 α。
## 显示那面是**按需**的：α = 0 的实体根本不需要，省掉一次摆形状，
## 也免得它在显示图里多写一片覆盖（那片覆盖会盖掉背景砖自己的 show）。
func _sync_one_shape(shape: AcousticShape, z: int, display: bool) -> void:
	var table: Dictionary = _shape_display if display else _shapes
	var canvas := _display_canvas if display else _canvas
	if canvas == null:
		return
	if display and shape.alpha_value() <= 0.0:
		_drop_shape_mirror(shape, _shape_display, canvas)
		return
	var mirror := table.get(shape) as CanvasItem
	if mirror == null or not is_instance_valid(mirror):
		mirror = shape.build_mirror()
		if mirror == null:
			return
		mirror.material = _alpha_material() if display else _body_material()
		canvas.add_child(mirror)
		table[shape] = mirror
	# 实体的合成 z 由层表决定（默认 3：压在所有图块层之上）
	mirror.z_index = z
	shape.pose_mirror(mirror)
	_apply_shape_params(shape, mirror, display)


func _drop_shape_mirror(shape: AcousticShape, table: Dictionary, canvas: Node) -> void:
	var old := table.get(shape) as Node
	if old == null:
		return
	if is_instance_valid(old):
		if canvas != null:
			canvas.remove_child(old)
		old.queue_free()
	table.erase(shape)


## 实体层定义。拿不到就返回 null，调用方退回默认值。
func _entity_layer() -> EchoLayer:
	for l in EchoLayers.layers():
		if l.kind == EchoLayer.Kind.ENTITY:
			return l
	return null


func _body_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BODY_SHADER
	return m


func _alpha_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BODY_ALPHA_SHADER
	return m


## 形状 → 着色器参数。transmit / surface 都是 AcousticMedium 从 Z 推出来的，
## 所以实体和图块填的是同一套物理量。
func _apply_shape_params(shape: AcousticShape, mirror: CanvasItem, display: bool) -> void:
	var m := mirror.material as ShaderMaterial
	if m == null:
		return
	if display:
		m.set_shader_parameter("alpha", shape.alpha_value())
		return
	m.set_shader_parameter("surface", shape.surface_value())
	m.set_shader_parameter("ior_ch", AcousticMedium.ior_to_channel(shape.ior))
	m.set_shader_parameter("transmit", shape.transmit_value())


## 实体被销毁（房间换了）就把它的镜子摘掉
func _sweep_shapes() -> void:
	for pair in [[_shapes, _canvas], [_shape_display, _display_canvas]]:
		var table: Dictionary = pair[0]
		var canvas = pair[1]
		for b in table.keys():
			var mirror := table[b] as Node
			if is_instance_valid(b) and is_instance_valid(mirror):
				continue
			if is_instance_valid(mirror):
				if canvas != null:
					(canvas as Node).remove_child(mirror)
				mirror.queue_free()
			table.erase(b)


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


## 显示视口：同样的镜像层再画一遍，但用的是"只写 show"的着色器。
##
## 为什么要第二遍：show 是逐图块的显示参数，而一层的图块可能来自**多个图集源**
## （前景层就同时用了 0/1/2 三个源），一份材质绑一张小图覆盖不了。
## 所以只能像几何那样，用同一套镜像再渲染一张 480×270。
func _build_display_view() -> void:
	_display_vp = SubViewport.new()
	_display_vp.name = "DisplayView"
	_display_vp.size = EchoField.VIEW_SIZE
	_display_vp.disable_3d = true
	_display_vp.transparent_bg = true
	_display_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_display_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(_display_vp)

	var cam := Camera2D.new()
	cam.name = "Camera"
	cam.position = EchoField.FIELD_SIZE * 0.5
	_display_vp.add_child(cam)
	cam.make_current()

	_display_canvas = Node2D.new()
	_display_canvas.name = "Mirrors"
	_display_vp.add_child(_display_canvas)


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
## （只看参与声学的层：纯装饰层不画进几何，缩放不该影响 band 厚度）
func _derive_band_px() -> int:
	var s := 1.0
	for b in _layers:
		var layer := b.node as TileMapLayer
		var def := b.def as EchoLayer
		if layer == null or (def != null and not def.acoustic):
			continue
		s = maxf(s, (absf(layer.global_scale.x) + absf(layer.global_scale.y)) * 0.5)
	return clampi(roundi(s), 1, MAX_BAND_PX)


# ---------------------------------------------------------------- 镜像层

## 把三层的格子全部复制到镜像层。图块变了就整份重来（一次几百个 set_cell，够快）。
## 几何和显示各要一套镜像——同一个节点不能同时存在于两个视口，只能各造一份。
func rebuild() -> void:
	if _canvas == null:
		return
	for m in _all_mirrors():
		m.clear()

	for li in _layers.size():
		var b: Dictionary = _layers[li]
		var layer := b.node as TileMapLayer
		var def := b.def as EchoLayer
		if layer == null or layer.tile_set == null:
			continue
		# 纯装饰层不进几何：不挡声、不长表面带，也省掉一整套镜像
		if def != null and not def.acoustic:
			continue
		var z := def.z if def != null else li
		for cell in layer.get_used_cells():
			var src := layer.get_cell_source_id(cell)
			if src < 0:
				continue
			var coords := layer.get_cell_atlas_coords(cell)
			var alt := layer.get_cell_alternative_tile(cell)
			_mirror_for(li, layer, src, false, z).set_cell(cell, src, coords, alt)
			_mirror_for(li, layer, src, true, z).set_cell(cell, src, coords, alt)


func _all_mirrors() -> Array:
	var out := []
	for per_src in _mirrors.values():
		for m in per_src.values():
			out.append(m)
	for per_src in _display_mirrors.values():
		for m in per_src.values():
			out.append(m)
	return out


func _mirror_for(li: int, layer: TileMapLayer, src: int, display: bool,
		z_index: int) -> TileMapLayer:
	var store := _display_mirrors if display else _mirrors
	var canvas := _display_canvas if display else _canvas
	var per_src: Dictionary = store.get(li, {})
	store[li] = per_src
	if per_src.has(src):
		return per_src[src]

	var m := TileMapLayer.new()
	m.name = ("disp%d" if display else "src%d") % src
	m.tile_set = layer.tile_set
	m.collision_enabled = false      # 只出图，不参与物理
	m.occlusion_enabled = false
	m.texture_filter = layer.texture_filter
	# z 来自层表（小 = 底层）。实体镜像固定 z=3，永远在最上面。
	m.z_index = z_index
	m.material = (_display_material if display else _geo_material).call(src)
	canvas.add_child(m)
	m.global_transform = layer.global_transform
	per_src[src] = m
	return m


func _display_material(src: int) -> ShaderMaterial:
	if _display_mat_cache.has(src):
		return _display_mat_cache[src]
	var m := ShaderMaterial.new()
	m.shader = DISPLAY_SHADER
	m.set_shader_parameter("params_atlas", _params_atlas(src, true))
	_display_mat_cache[src] = m
	return m


func _geo_material(src: int) -> ShaderMaterial:
	if _mat_cache.has(src):
		return _mat_cache[src]
	var m := ShaderMaterial.new()
	m.shader = GEO_SHADER
	m.set_shader_parameter("params_atlas", _params_atlas(src, false))
	_mat_cache[src] = m
	return m


# ---------------------------------------------------------------- 逐图块参数

## 和某个图集纹理等大的参数图。图集里每个 tile 的矩形都填上它自己的一整组参数。
## 两种图，通道含义不同，各自喂给一张视口：
##   · display = false（几何视口）: R = surface, G = ior, B = transmit, A = 1（覆盖）
##   · display = true （显示视口）: R = show,    G = alpha, B = 0,      A = 1（覆盖）
## surface / transmit 是美术填的 Z 推出来的（AcousticMedium.surface_from_z / transmit_from_z），
## Z 这个名字只活在这个函数里，着色器一点都不知道有它。
## 两张全屏纹理各自从一个视口来，所以不需要把一个通道劈成两半用。
func _params_atlas(src: int, display: bool) -> Texture2D:
	var cache: Dictionary = _display_atlas_cache if display else _atlas_cache
	if cache.has(src):
		return cache[src]

	var tset := _find_tileset()
	var atlas: TileSetAtlasSource = null
	if tset != null:
		atlas = tset.get_source(src) as TileSetAtlasSource
	var tex: Texture2D = atlas.texture if atlas != null else null
	if tex == null:
		cache[src] = _blank_texture()
		return cache[src]

	var img := Image.create(tex.get_width(), tex.get_height(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var z_id := tset.get_custom_data_layer_by_name("Z")
	var ior_id := tset.get_custom_data_layer_by_name("ior")
	var show_id := tset.get_custom_data_layer_by_name("show")
	var alpha_id := tset.get_custom_data_layer_by_name("alpha")
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

		# 折射率：没填 = 空气（1.0）。水 1.33、玻璃 1.5 …… 越大声音越慢。
		# 上限 4 只是防呆：基础 cfl 贴着稳定上限，n < 1 会让场爆掉，所以下限锁在 1。
		var ior := 1.0
		if ior_id >= 0 and td != null:
			ior = clampf(float(td.get_custom_data_by_layer_id(ior_id)), 1.0, AcousticMedium.IOR_MAX)

		# 声阻抗 Z 是美术填的那个量；透声系数由它推出来。
		var z := 0.0
		if z_id >= 0 and td != null:
			z = float(td.get_custom_data_by_layer_id(z_id))
		var transmit := AcousticMedium.transmit_from_z(z)

		# surface：显不显现边缘。由 Z 推出来（反射系数），不再单独填。
		var surface := AcousticMedium.surface_from_z(z)

		# show：显不显现纹理。没填时按"材质种类"给默认值：
		#   · 单面平台 0.8（原来是 absorb=0.2 压暗的）
		#   · 折射介质 0.6（原来是 shader 里的 body hack）
		var show := 1.0
		if show_id >= 0 and td != null:
			show = clampf(float(td.get_custom_data_by_layer_id(show_id)), 0.0, 1.0)
		elif one_way:
			show = DEFAULT_ONE_WAY_SHOW
		elif ior > 1.01:
			show = DEFAULT_REFRACTIVE_SHOW

		# 吸声 α：介质**内部**的体衰减，和界面上的 transmit 是两回事。
		# 只写进显示图的 G 通道，由 wave_step_fb 每步读。
		var alpha := 0.0
		if alpha_id >= 0 and td != null:
			alpha = clampf(float(td.get_custom_data_by_layer_id(alpha_id)), 0.0, 1.0)

		# 动画图块的每一帧都是图集里的一块矩形，全都要填。
		# G 是 RGBA8 通道（0~1），所以 c 要归一化：1 → 0，IOR_MAX → 1。
		var col := Color(show, alpha, 0.0, 1.0) if display \
				else Color(surface, AcousticMedium.ior_to_channel(ior), transmit, 1.0)
		var frames := maxi(1, atlas.get_tile_animation_frames_count(coords))
		for f in frames:
			img.fill_rect(atlas.get_tile_texture_region(coords, f), col)

	var out := ImageTexture.create_from_image(img)
	cache[src] = out
	return out


func _find_tileset() -> TileSet:
	for b in _layers:
		var layer := b.node as TileMapLayer
		if layer != null and layer.tile_set != null:
			return layer.tile_set
	return null


func _blank_texture() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
