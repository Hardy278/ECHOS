class_name EchoWorld
extends Node2D

## 回声世界：所有发声物体共享的那一份"世界"。
##
## - `geometry`：每帧把前景/中景/后景现画成一张活几何纹理（WaveGeometry），
##   所有声源都从这张图上取"哪里有墙、哪里是水、表面带在哪"。没有烘焙。
## - `light`：所有声源各自把自己的场按音色加进这里，
##   合成出**总的照亮显示**——空气里的光和图片块的光都只认这一张。
##
## 于是"有几个声源"不再受着色器槽位限制：多一个发声物体，只是多画一层。

const WAVE_GEOMETRY := preload("res://scripts/wave/wave_geometry.gd")
const LIGHT_VIEW_SHADER := preload("res://shaders/light_view.gdshader")
const TILE_LIGHT_SHADER := preload("res://shaders/tile_light.gdshader")
## 三层图块对光的响应：后景压暗，才读得出前后
const LAYER_GAINS := [1.0, 0.80, 0.55]

## 三层图块（检查器里拖进来）。
@export var foreground: TileMapLayer
@export var midground: TileMapLayer
@export var background: TileMapLayer

var layers: Array = []
## 听者的位置（角色的坐标）：每个声源按"它在我这儿有多响"决定自己画多亮
var listener := Vector2(240, 238)
var geometry: Node            # WaveGeometry

var _light_vp: SubViewport
var _light_root: Control
var _display: CanvasLayer
var _sources: Array = []


func _enter_tree() -> void:
	add_to_group("echo_world")


func _process(_delta: float) -> void:
	for s in _sources:
		if is_instance_valid(s) and s.has_method("set_listener"):
			s.set_listener(listener)


func _ready() -> void:
	# 检查器里没指定就按名字兜底（场景里这三层叫 ForeGround / MidGround / Background）
	if foreground == null:
		foreground = _sibling_layer("ForeGround")
	if midground == null:
		midground = _sibling_layer("MidGround")
	if background == null:
		background = _sibling_layer("Background")
	if foreground == null:
		push_warning("EchoWorld: 没找到前景 TileMapLayer，图块不会被声场点亮")

	layers = [foreground, midground, background]

	geometry = WAVE_GEOMETRY.new()
	geometry.name = "Geometry"
	add_child(geometry)
	geometry.setup(layers)

	_build_light()
	_build_tile_materials()
	_build_display()


## 按名字在同级节点里找一个 TileMapLayer
func _sibling_layer(layer_name: String) -> TileMapLayer:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null(layer_name) as TileMapLayer


# ---------------------------------------------------------------- 对外

func geometry_texture() -> Texture2D:
	return geometry.texture() if geometry != null else null


func band_texture() -> Texture2D:
	return geometry.band_texture() if geometry != null else null


## 声源注册：把它那层视图挂到合成层上，之后每帧给它推听者位置。
func register(source: Node, view_mat: ShaderMaterial) -> void:
	if source == null or view_mat == null or _light_root == null:
		return
	if not _sources.has(source):
		_sources.append(source)

	var tr := TextureRect.new()
	tr.texture = geometry_texture()
	tr.material = view_mat
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_light_root.add_child(tr)
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


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

	var tr := TextureRect.new()
	tr.name = "AirLight"
	tr.texture = _light_vp.get_texture()
	tr.material = mat
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display.add_child(tr)
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
