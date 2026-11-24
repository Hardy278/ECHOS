class_name PickupAbility
extends Node

## 物品实体的"拾取能力"。
##
## 它只做一条链：
##   玩家背包收得下 → 收下 → 删除实体
## 收不下就什么都不改，实体留在原地。
##
## 它不认识 UI，也不认识"物品"这个数据本身之外的东西；
## 物品数据从父节点 ItemEntity 读。

func _entity() -> ItemEntity:
	return get_parent() as ItemEntity


func can_trigger(player: Node) -> bool:
	var e := _entity()
	if e == null or e.item_def == null or player == null:
		return false
	var inv := player.get_node_or_null("Inventory") as Inventory
	if inv == null:
		return false
	return inv.can_add(e.item_def, e.count)


func trigger(player: Node) -> bool:
	if not can_trigger(player):
		return false
	var e := _entity()
	var inv := player.get_node_or_null("Inventory") as Inventory
	if inv.add(e.item_def, e.count) != e.count:
		return false
	e.pick()
	e.queue_free()
	return true
