class_name TileLayerPresenter
extends Node

## 一层图块的"呈现器"。**只给需要特殊表现的层挂**，默认层什么都不挂。
##
## 分工：
##   · EchoWorld 负责所有通用量（光、几何、显示、渗光、层倍率、镂空），照旧一份代码；
##   · 呈现器只回答两件事——这一层用哪个着色器、还要补哪些 uniform。
##
## 这样"特殊"不进层表，也不复制通用材质代码。

const NORMAL_SHADER := preload("res://shaders/tile_light_normal.gdshader")

## albedo 图集 → 法线图集
@export var normal_map: NormalAtlasMap
## 0 = 关，1 = 满对比
@export_range(0.0, 1.0) var normal_strength := 0.0
## 中央差分步长（texel）。见 tile_light_normal.gdshader 里的说明
@export var normal_step := 6.0

var _warned := false


## 返回 null = 用默认的 tile_light。
func layer_shader() -> Shader:
	return NORMAL_SHADER if _entry() != null else null


## 通用 uniform 已经由 EchoWorld 设好，这里只补自己的。
func decorate(m: ShaderMaterial) -> void:
	var entry := _entry()
	if entry == null:
		return
	m.set_shader_parameter("normal_tex", entry.normal)
	m.set_shader_parameter("normal_strength", normal_strength)
	m.set_shader_parameter("normal_step", normal_step)


# ---------------------------------------------------------------- 解析

## 这一层实际用到的那张 albedo 纹理。
## 一个 normal_tex uniform 只能服务一个图集源，所以只在这一层**只用了 1 个源**时才成立。
func _entry() -> NormalAtlasEntry:
	if normal_map == null:
		return null
	return normal_map.find(_albedo())


func _albedo() -> Texture2D:
	var layer := get_parent() as TileMapLayer
	if layer == null or layer.tile_set == null:
		return null
	var used := {}
	for c in layer.get_used_cells():
		var s := layer.get_cell_source_id(c)
		if s < 0:
			continue
		var atlas := layer.tile_set.get_source(s) as TileSetAtlasSource
		if atlas == null or atlas.texture == null:
			continue
		used[atlas.texture] = true
	if used.size() > 1:
		if not _warned:
			_warned = true
			push_warning("%s: 这层用了 %d 个图集源，法线只能服务一个 —— 已退回默认材质"
					% [layer.name, used.size()])
		return null
	if used.is_empty():
		return null
	return used.keys()[0]
