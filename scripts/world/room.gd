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

## 固定顺序，不能改：EchoWorld 的层增益按这个下标取
const LAYER_NAMES := ["ForeGround", "MidGround", "Background"]


func _ready() -> void:
	add_to_group("rooms")
	_validate_layers()


## 三层图块，顺序固定为（前景, 中景, 后景）；没有的那层是 null
func layers() -> Array:
	var out: Array = []
	for n in LAYER_NAMES:
		out.append(get_node_or_null(n) as TileMapLayer)
	return out


func acoustics() -> Vector2:
	return Vector2(reverb, absorb)


## 三层必须共用同一份 TileSet：声学参数表和表面带都是按图集算的
func _validate_layers() -> void:
	var first: TileSet = null
	for l in layers():
		var layer := l as TileMapLayer
		if layer == null or layer.tile_set == null:
			continue
		if first == null:
			first = layer.tile_set
		elif layer.tile_set != first:
			push_warning("Room %s: 三层的 TileSet 不一致，声学几何会取错参数表" % name)
			return
