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
const BLEED_SHADER := preload("res://shaders/light_bleed.gdshader")
## 光渗缓冲的分辨率：一个 texel = FIELD_SIZE / BLEED_SIZE = 8 个世界单位。
## 分辨率只是"渗光的形状有多细"，跟"能渗多深"无关——后者由 decay 决定。
const BLEED_SIZE := Vector2i(60, 34)
const TILE_LIGHT_SHADER := preload("res://shaders/tile_light.gdshader")

## 当前房间的图块层（顺序与 Room.LAYER_NAMES 一致，没有的层是 null）。
## 层不再带"压暗系数"——背景暗多少由它自己那几种砖的 show 决定（tileset custom data）。
var layers: Array = []
## 当前房间的层绑定：[{def: EchoLayer, node: TileMapLayer}]，z 升序
var _bindings: Array = []
## 听者的位置（角色的坐标）：每个声源按"它在我这儿有多响"决定自己画多亮
var listener := Vector2(240, 238)
var geometry: Node            # WaveGeometry

## 光渗的衰减（每步）。0.62 ≈ 渗 2~3 个 tile 就暗下去。
## 调大渗得更远（砖块内部更亮），调小只在表面附近亮。
@export var bleed_decay := 0.62

## 声速（世界单位/秒）：**全局唯一**，所有 EchoSource 都用它。
## 0 = 用项目设置 echos/wave_speed，再没有就用 EchoSource.BASE_SPEED（166.28）。
## 放在世界上而不是 Project Settings：手写的自定义段在编辑器面板里不一定显示，
## 这里的导出在 main.tscn 选中 EchoWorld 就能直接调。
## 运行中改它会立刻推给现有声源（走 refresh_room）。
@export var wave_speed := 0.0:
	set(v):
		wave_speed = v
		_push_speed()

var _light_vp: SubViewport
var _light_root: Control
## 光渗缓冲：低分辨率 ping-pong 两块。让"撞到表面的光"渗进实体内部。
## 不透声的格子里声场恒为 0，没有它的话砖块内部永远是黑的。
var _bleed_vps: Array = []
var _bleed_front := 0
var _bleed_reset_frames := 0
var _display: CanvasLayer
var _sources: Array = []
var _views: Dictionary = {}   # 声源 → 它在合成层里的那个四边形
var _entity_mat: ShaderMaterial
var _white_tex: Texture2D
var _black_tex: Texture2D


func _enter_tree() -> void:
	add_to_group("echo_world")


## 运行中改 wave_speed：让所有活着的声源重读一遍（顺带重读房间声学）。
## 场景加载时属性可能先于节点进树被设置，这里做空保护。
func _push_speed() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group("echo_sources"):
		if n.has_method("refresh_room"):
			n.call("refresh_room")


func _ready() -> void:
	geometry = WAVE_GEOMETRY.new()
	geometry.name = "Geometry"
	add_child(geometry)
	geometry.setup([])        # 视口先建好，图块等房间绑进来

	_build_light()
	_build_bleed()
	_build_display()
	_build_entity_material()


func _process(_delta: float) -> void:
	for s in _sources:
		if is_instance_valid(s) and s.has_method("set_listener"):
			s.set_listener(listener)
	_step_bleed()


# ---------------------------------------------------------------- 对外

## 绑到一个房间：它的三层图块成为当前世界
func bind_room(room: Room) -> void:
	if room == null:
		return
	layers = room.layers()
	_bindings = room.bindings()
	_clear_bleed()
	_build_tile_materials()
	if geometry != null:
		geometry.rebind(_bindings)


func geometry_texture() -> Texture2D:
	return geometry.texture() if geometry != null else null


func band_texture() -> Texture2D:
	return geometry.band_texture() if geometry != null else null


## 显示纹理（R = show，G = alpha）。波场每步读 G 当体积吸声系数。
func display_texture() -> Texture2D:
	return geometry.display_texture() if geometry != null else null


## 合成光（调试/探针用）
func light_texture() -> Texture2D:
	return _light_vp.get_texture() if _light_vp != null else null


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


## 光渗缓冲：低分辨率 ping-pong。
##
## 一步只扩散一个低分辨率 texel（= 8 个世界单位），每帧迭代一次。
## 这样"光往实体内部渗"是**随时间铺开**的，看起来像真的有光照进去，
## 而不是一瞬间整块亮起。成本：60×34 × 9 次采样/帧，可忽略。
func _build_bleed() -> void:
	# 先把两个视口都建出来（材质要互相引用对方的纹理，必须两边都在）
	for k in 2:
		var vp := SubViewport.new()
		vp.name = "Bleed%d" % k
		vp.size = BLEED_SIZE
		vp.disable_3d = true
		vp.transparent_bg = false
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		_bleed_vps.append(vp)

	var low := Vector2(BLEED_SIZE)
	var mats: Array = []
	for k in 2:
		var mat := ShaderMaterial.new()
		mat.shader = BLEED_SHADER
		# ping-pong：这一块读**另一块**的上一帧
		mat.set_shader_parameter("src_tex",
				(_bleed_vps[1 - k] as SubViewport).get_texture())
		mat.set_shader_parameter("light_tex", _light_vp.get_texture())
		mat.set_shader_parameter("low_size", low)
		mat.set_shader_parameter("decay", bleed_decay)
		mat.set_shader_parameter("reset", 0.0)
		mats.append(mat)

		var cr := ColorRect.new()
		cr.size = low
		cr.material = mat
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		(_bleed_vps[k] as SubViewport).add_child(cr)


## 当前"渗开的光"。tile_light 拿它和局部光取 max。
func bleed_texture() -> Texture2D:
	if _bleed_vps.is_empty():
		return null
	return (_bleed_vps[_bleed_front] as SubViewport).get_texture()


## 每帧往前推一步。换房间时清空，别把上一间的光带过来。
func _step_bleed() -> void:
	if _bleed_vps.size() < 2:
		return

	# 清场窗口：两块都写黑，不推进
	if _bleed_reset_frames > 0:
		_bleed_reset_frames -= 1
		var on := _bleed_reset_frames > 0
		for vp in _bleed_vps:
			_set_bleed_reset(vp, on)
			(vp as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
		return

	var back := 1 - _bleed_front
	# 采样器每步都要重绑：只设一次绑不上，采样器保持默认白，
	# 于是 max(decay, 1) = 1，整个缓冲会被填成 1。
	var mat := _bleed_material(back)
	if mat != null:
		mat.set_shader_parameter("src_tex",
				(_bleed_vps[_bleed_front] as SubViewport).get_texture())
		mat.set_shader_parameter("light_tex", _light_vp.get_texture())
		mat.set_shader_parameter("decay", bleed_decay)
	(_bleed_vps[back] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
	_bleed_front = back
	(_bleed_vps[1 - back] as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED


func _bleed_material(k: int) -> ShaderMaterial:
	if k < 0 or k >= _bleed_vps.size():
		return null
	var cr := (_bleed_vps[k] as SubViewport).get_child(0)
	return cr.material as ShaderMaterial if cr != null else null


func _set_bleed_reset(vp: Node, on: bool) -> void:
	var cr := (vp as SubViewport).get_child(0)
	if cr == null or cr.material == null:
		return
	var mat := cr.material as ShaderMaterial
	mat.set_shader_parameter("reset", 1.0 if on else 0.0)
	# 清场帧也要绑一次：reset 那一帧不读采样器，但下一帧要接上正确的那块
	mat.set_shader_parameter("light_tex", _light_vp.get_texture())


## 换房间时清场。用帧计数而不是 await：
## 一个节点的协程在节点被释放后很麻烦，而这里只要"两帧写黑"就够了。
func _clear_bleed() -> void:
	_bleed_reset_frames = 2
	_bleed_front = 0


## 所有读"合成光"的材质共用的那几项。
## 图块和实体只差在 display_tex 和层增益，其余完全相同——只写一份，改的时候不会漏掉一边。
func _apply_shared(m: ShaderMaterial, light_gain: float) -> void:
	m.set_shader_parameter("light_tex", _light_vp.get_texture())
	m.set_shader_parameter("geo_tex", geometry_texture())
	m.set_shader_parameter("field_size", EchoField.FIELD_SIZE)
	# 渗进实体内部的那一份光：没有它，砖块内部永远是黑的
	m.set_shader_parameter("bleed_tex",
			bleed_texture() if bleed_texture() != null else _black())
	m.set_shader_parameter("light_gain", light_gain)


## 每层的图块材质：被"总的照亮"照亮才显形，暗处透明
func _build_tile_materials() -> void:
	for b in _bindings:
		var layer := b.node as TileMapLayer
		var def := b.def as EchoLayer
		if layer == null or def == null:
			continue
		# 这一层要不要自己挑着色器：节点（或子节点）实现了 layer_shader() 就听它的。
		# 只有需要特殊表现的层才挂呈现器，默认层连这个方法都不存在。
		var presenter := _presenter_of(layer)
		var sh: Shader = TILE_LIGHT_SHADER
		if presenter != null:
			var custom: Shader = presenter.call("layer_shader")
			if custom != null:
				sh = custom
		var m := ShaderMaterial.new()
		m.shader = sh
		_apply_shared(m, def.light_gain)
		# 每块砖"显现纹理"的值；拿不到就绑 1×1 白（= 全显示）
		m.set_shader_parameter("display_tex",
				geometry.call("display_texture") if geometry != null else _white())
		# 不进几何的层（背景）是纯画面：它会透过前景瓦片露出来，
		# 而前景渗光本身很淡，底下压一块更亮的背景就被吃掉了。用覆盖把它镂空。
		m.set_shader_parameter("behind_only", 0.0 if def.acoustic else 1.0)
		# 呈现器只补它自己那几个 uniform；通用量一律不归它管
		if presenter != null and presenter.has_method("decorate"):
			presenter.call("decorate", m)
		layer.material = m


## 找这一层的呈现器：节点自己实现，或者它下面挂一个
func _presenter_of(layer: Node) -> Node:
	if layer.has_method("layer_shader"):
		return layer
	for c in layer.get_children():
		if c.has_method("layer_shader"):
			return c
	return null


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
	var edef := EchoLayers.entity_layer()
	_entity_mat = ShaderMaterial.new()
	_entity_mat.shader = TILE_LIGHT_SHADER
	# 实体层的显示倍率来自层表，不受图块层的 light_gain 影响
	_apply_shared(_entity_mat, edef.light_gain if edef != null else 1.0)
	# 实体没有"每砖种"的概念，统一完全显示；要单独调就给那个实体一份自己的材质
	_entity_mat.set_shader_parameter("display_tex", _white())


## 1×1 黑：光渗没准备好时的兜底。**不能给白**——那会让全世界都亮起来。
func _black() -> Texture2D:
	if _black_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 1))
		_black_tex = ImageTexture.create_from_image(img)
	return _black_tex


## 1×1 白：show = 1 的"全显示"贴图。着色器绑不上纹理时采样会得到 0，
## 那会让所有东西消失，所以任何缺省路径都必须给这张。
func _white() -> Texture2D:
	if _white_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex
