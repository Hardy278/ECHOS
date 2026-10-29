class_name EchoWorld
extends Node2D

## 回声世界：所有发声物体共享的那一份"世界"。
##
## - `geometry`：每帧把**当前房间**的前景/中景/后景现画成一张活几何纹理（WaveGeometry），
##   所有声源都从这张图上取"哪里有墙、哪里是水、表面带在哪"。没有烘焙。
## - `light`：所有声源各自把自己的场按音色加进这里，
##   合成出**总的照亮显示**——空气里的光和图片块的光都只认这一张。
##
## 世界不属于任何房间：切房时 `bind_room()` 把三层图块换成新房间的，材质和几何
## 跟着重挂，但光和声源都不用重建——它们的纹理对象一直是同一块，只是内容换了。

const WAVE_GEOMETRY := preload("res://scripts/wave/wave_geometry.gd")
const LIGHT_VIEW_SHADER := preload("res://shaders/light_view.gdshader")
const TILE_LIGHT_SHADER := preload("res://shaders/tile_light.gdshader")
## 三层图块对光的响应：后景压暗，才读得出前后
const LAYER_GAINS := [1.0, 0.80, 0.55]

## 当前房间的三层图块（顺序与 LAYER_GAINS 一致，没有的层是 null）
var layers: Array = []
## 听者的位置（角色的坐标）：每个声源按"它在我这儿有多响"决定自己画多亮
var listener := Vector2(240, 238)
var geometry: Node            # WaveGeometry

var _light_vp: SubViewport
var _light_root: Control
var _display: CanvasLayer
var _sources: Array = []
var _views: Dictionary = {}   # 声源 → 它在合成层里的那个四边形
var _entity_mat: ShaderMaterial


func _enter_tree() -> void:
	add_to_group("echo_world")


func _ready() -> void:
	geometry = WAVE_GEOMETRY.new()
	geometry.name = "Geometry"
	add_child(geometry)
	geometry.setup([])        # 视口先建好，图块等房间绑进来

	_build_light()
	_build_display()
	_build_entity_material()


func _process(_delta: float) -> void:
	for s in _sources:
		if is_instance_valid(s) and s.has_method("set_listener"):
			s.set_listener(listener)


# ---------------------------------------------------------------- 对外

## 绑到一个房间：它的三层图块成为当前世界
func bind_room(room: Room) -> void:
	if room == null:
		return
	layers = room.layers()
	_build_tile_materials()
	if geometry != null:
		geometry.rebind(layers)


func geometry_texture() -> Texture2D:
	return geometry.texture() if geometry != null else null


func band_texture() -> Texture2D:
	return geometry.band_texture() if geometry != null else null


## 实体（钟、机关、敌人）共用的一份材质：和 tile_light 是同一个着色器，
## 只是层增益不同。实体自己的 Sprite2D / AnimatedSprite2D 直接挂它，
## 于是"实体被照到才显形"和"听不见就看不见"全部沿用合成光那一套，
## 不需要给实体单独求光。
func entity_material() -> ShaderMaterial:
	return _entity_mat


## 声源注册：把它那层视图挂到合成层上，之后每帧给它推听者位置
func register(source: Node, view_mat: ShaderMaterial) -> void:
	if source == null or view_mat == null or _light_root == null:
		return
	if not _sources.has(source):
		_sources.append(source)
	if _views.has(source):
		return

	var quad := TextureRect.new()
	quad.texture = geometry_texture()
	quad.material = view_mat
	quad.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	quad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	quad.stretch_mode = TextureRect.STRETCH_SCALE
	quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_light_root.add_child(quad)
	quad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_views[source] = quad


## 声源随房间被释放时自己走了：把它那层也摘掉，否则合成层会一直画一份死视图
func unregister(source: Node) -> void:
	_sources.erase(source)
	var quad = _views.get(source)
	_views.erase(source)
	if is_instance_valid(quad):
		(quad as Node).queue_free()


## 一行内部状态，交给 HUD 显示
func debug_line() -> String:
	if geometry == null:
		return ""
	return "几何 %d×%d · 表面带 %d texel · 声源 %d" % [EchoField.FW, EchoField.FH,
			geometry.band_px, _sources.size()]


# ---------------------------------------------------------------- 合成层

## 声源视图的加法合成目标：这张纹理就是"总的照亮显示"
func _build_light() -> void:
	_light_vp = SubViewport.new()
	_light_vp.name = "LightView"
	_light_vp.size = EchoField.VIEW_SIZE
	_light_vp.disable_3d = true
	_light_vp.transparent_bg = true
	_light_vp.use_hdr_2d = true
	_light_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_light_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(_light_vp)

	_light_root = Control.new()
	_light_root.name = "Views"
	_light_root.size = EchoField.FIELD_SIZE
	_light_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_light_vp.add_child(_light_root)


## 三层的图块材质：被"总的照亮"照亮才显形，暗处透明
func _build_tile_materials() -> void:
	for i in layers.size():
		var layer := layers[i] as TileMapLayer
		if layer == null:
			continue
		var m := ShaderMaterial.new()
		m.shader = TILE_LIGHT_SHADER
		m.set_shader_parameter("light_tex", _light_vp.get_texture())
		m.set_shader_parameter("geo_tex", geometry_texture())
		m.set_shader_parameter("field_size", EchoField.FIELD_SIZE)
		m.set_shader_parameter("layer_gain", LAYER_GAINS[i])
		layer.material = m


func _build_display() -> void:
	_display = CanvasLayer.new()
	_display.layer = -1
	add_child(_display)

	var mat := ShaderMaterial.new()
	mat.shader = LIGHT_VIEW_SHADER
	mat.set_shader_parameter("light_tex", _light_vp.get_texture())

	var quad := TextureRect.new()
	quad.name = "AirLight"
	quad.texture = _light_vp.get_texture()
	quad.material = mat
	quad.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	quad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	quad.stretch_mode = TextureRect.STRETCH_SCALE
	quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display.add_child(quad)
	quad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## 实体共用材质：读同一张合成光、同一张几何纹理，只是层增益按前景算
func _build_entity_material() -> void:
	_entity_mat = ShaderMaterial.new()
	_entity_mat.shader = TILE_LIGHT_SHADER
	_entity_mat.set_shader_parameter("light_tex", _light_vp.get_texture())
	_entity_mat.set_shader_parameter("geo_tex", geometry_texture())
	_entity_mat.set_shader_parameter("field_size", EchoField.FIELD_SIZE)
	_entity_mat.set_shader_parameter("layer_gain", 1.0)
