class_name Room
extends Node2D

## 一个房间：480×270 的一屏空间，在网格里的位置由 `coord` 决定。
##
## 房间场景里就是三层 TileMapLayer（世界图块）+ 这个房间自己的实体。
## 切进来时它的三层被 EchoWorld 绑成"当前世界"，切出去时整个实例被释放——
## 所以房间里的一切（草被踩成什么样、钟在响没在响）都随实例重建而重置。
## 要跨房间保留的东西挂 Persistent。

## 这个房间在网格里的位置。RoomSystem 靠它把房间摆到网格上，所以必须唯一；
## 也是"从哪条边走出去会到哪"的唯一依据（四邻 = ±1）。
@export var coord := Vector2i.ZERO
## HUD 上显示的名字
@export var title := ""

## 声学：叠在物体自己的音色上，不覆盖物体性格
@export_range(0.0, 1.0) var reverb := 0.0   ## 越大余晖衰减越慢，回声拖得越长
@export_range(0.0, 1.0) var absorb := 0.0   ## 越大能量掉得越快，波走得越短

func _ready() -> void:
	add_to_group("rooms")
	_validate_layers()


## 这一房间的图块层，顺序 = 层表里 TILE 层的 z 升序（底层在前）。
## 没有的那层是 null——调用方（EchoWorld / Water）都按 null 跳过。
##
## 层名不再硬编码在这里：唯一真相来源是 res://world/layer_set.tres（EchoLayers）。
func layers() -> Array:
	var out: Array = []
	for b in bindings():
		out.append(b.node)
	return out


## 层定义 + 房间节点配成对，顺序 = z 升序。
## 每项是 {def: EchoLayer, node: TileMapLayer}。
## WaveGeometry / EchoWorld 要的是"这层的定义"和"这层的节点"两样，
## 所以别再传裸节点了——否则又得靠下标去猜哪层是哪层。
func bindings() -> Array:
	var out: Array = []
	for def in EchoLayers.tile_layers():
		var n := String(def.path)
		var layer := get_node_or_null(n) as TileMapLayer
		if layer == null:
			push_warning("Room %s: 层表要求节点 '%s'，房间里没有" % [name, n])
			continue
		out.append({"def": def, "node": layer})
	return out


func acoustics() -> Vector2:
	return Vector2(reverb, absorb)


## 每层的 TileSet 现在**可以不同**（背景 / 前景各一份），所以不再要求"三层共用"。
## 真正会让参数静默错位的是**缺少 custom data 层**：参数图是按名字找层的
## （ior / absorb / Z / water / show / alpha），少一个就退回默认值——
## 画面和声音都不会报错，只会"莫名其妙不对"。这里把它变成一条警告。
const REQUIRED_DATA := ["ior", "absorb", "Z", "water", "show", "alpha"]

func _validate_layers() -> void:
	var checked := {}
	for l in layers():
		var layer := l as TileMapLayer
		if layer == null or layer.tile_set == null:
			continue
		var ts := layer.tile_set
		if checked.has(ts):
			continue
		checked[ts] = true
		for data_name in REQUIRED_DATA:
			if ts.get_custom_data_layer_by_name(data_name) < 0:
				push_warning("Room %s: TileSet「%s」缺 custom data 层「%s」，这层的砖会退回默认值"
						% [name, ts.resource_path.get_file(), data_name])
