class_name ItemEntity
extends Node2D

## 世界里的"物品实体"——不是物品本身。
##
##   ItemDef / ItemStack / Inventory  = 物品数据
##   ItemEntity                      = 场景里那个可拾取的小东西
##   PickupAbility                   = 实体被触发时的行为
##
## 实体被删除只删掉场景里的这一份；Inventory 里的 ItemStack 继续存在。
## 世界视觉是 2×2 世界单位（= 1 个 tile 像素），靠自己的 Hum 发一点光。
## 16×16 的图标只属于 UI；这里不用它。

signal picked

@export var item_def: ItemDef
@export var count := 1
## 挂在垂草上时：第几根、第几个点（-1 = 末梢）
@export var strand := 0
@export var at_index := -1

var _picked := false

@onready var _visual: CanvasItem = $Visual
@onready var _ability: PickupAbility = $PickupAbility


func _ready() -> void:
	add_to_group("item_entities")

	var world := get_tree().get_first_node_in_group("echo_world")
	if world != null and world.has_method("entity_material"):
		var mat: Material = world.entity_material()
		if mat != null:
			_visual.material = mat


## 垂草每帧把链上的世界坐标交过来；量化到 2 单位，避免停在半像素上。
func mount_at(pos: Vector2) -> void:
	if _picked:
		return
	global_position = Vector2(roundf(pos.x / 2.0) * 2.0, roundf(pos.y / 2.0) * 2.0)


func is_picked() -> bool:
	return _picked


func pick() -> void:
	if _picked:
		return
	_picked = true
	picked.emit()


func can_pickup(player: Node) -> bool:
	return _ability != null and _ability.can_trigger(player)


func try_pickup(player: Node) -> bool:
	return _ability != null and _ability.trigger(player)
