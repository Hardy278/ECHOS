class_name Fruit
extends Node2D

## 垂草上的果实：一盏一直在响的灯。
##
## **它自己不动。** 它动，是因为草在动——草每帧把锚点交给它（mount_at）。
## 没有动画、没有抖动序列、没有自己的物理：它唯一会做的事就是发声。
##
## 所以"采下来当道具"就是 pick() + reparent：草失去挂载物自己荡两下停住，
## 果实搬到哪儿就在哪儿继续响、继续亮。一行都不用改。

## 挂在这一丛的第几根上
@export var strand := 0
## 挂在链的第几个点上；-1 = 末梢
@export var at_index := -1

## 一个 tile 像素 = 2 世界单位（tileset 是 8×8、scale 2）
const PIXEL := 2.0

var _picked := false


func _ready() -> void:
	var world := get_tree().get_first_node_in_group("echo_world")
	if world == null or not world.has_method("entity_material"):
		return
	var mat: Material = world.entity_material()
	for c in get_children():
		if c is CanvasItem:
			(c as CanvasItem).material = mat


## 草每帧调用：把这个果实挂到这个世界坐标上。
## 量化到 tile 像素，否则摆动的果实会停在半像素上，糊成两格。
func mount_at(pos: Vector2) -> void:
	if _picked:
		return
	global_position = Vector2(roundf(pos.x / PIXEL) * PIXEL,
			roundf(pos.y / PIXEL) * PIXEL)


## 采下来：不再被草驱动。之后谁把它捡走，它就在谁身上震、在谁身上响。
func pick() -> void:
	_picked = true


func is_picked() -> bool:
	return _picked
