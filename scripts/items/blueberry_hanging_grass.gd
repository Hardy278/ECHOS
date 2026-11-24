@tool
extends HangingGrass

## 一丛专门挂蓝浆果的垂草。
##
## 蓝浆果被捡走后删除实体；这个场景记下它原来挂在哪根、哪个点、什么位置，
## 过 respawn_sec 秒再实例化一颗新的挂回去。
##
## 只处理"重生"这件事；挂载本身仍由 HangingGrass 的 mount_at 驱动。

const BERRY_SCENE := preload("res://scenes/items/blueberry_entity.tscn")

@export var respawn_sec := 8.0


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	for c in get_children():
		_wire(c)


func _wire(n: Node) -> void:
	if n is ItemEntity:
		n.picked.connect(_on_picked.bind(n))


func _on_picked(e: ItemEntity) -> void:
	var spot := {
		"strand": e.strand,
		"at_index": e.at_index,
		"pos": e.global_position,
	}
	_respawn(spot)


func _respawn(spot: Dictionary) -> void:
	await get_tree().create_timer(maxf(respawn_sec, 0.1)).timeout
	if not is_inside_tree():
		return
	var e := BERRY_SCENE.instantiate() as ItemEntity
	e.strand = int(spot["strand"])
	e.at_index = int(spot["at_index"])
	e.global_position = spot["pos"] as Vector2
	add_child(e)
	add_hanging(e)
	_wire(e)
