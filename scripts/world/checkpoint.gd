class_name Checkpoint
extends Area2D

## 检查点：踩过就记住，溺水后回到这里。
##
## 它自己就是一个 Area2D：碰没碰到由物理判定，不靠脚本算距离。
## 形状在场景里摆（默认一格），没有贴图——编辑时看得见的只有那个框。
## 复活点就是本节点的位置：摆在哪就在哪重开。
##
## 只登记"最后一个踩过的"：踩到就把「房间坐标 + 位置」写进 RoomSystem，
## 全局只留一份。房间换掉后这个实例被释放了，登记还在，
## 所以可以在 A 房间淹死、回到 B 房间的检查点。


func _ready() -> void:
	collision_layer = 0      # 不是实体，谁也不该撞它
	collision_mask = 1       # 只在乎玩家那一层
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	var rooms := get_tree().get_first_node_in_group("room_system")
	if rooms == null:
		return
	rooms.call("set_checkpoint", _room_coord(), global_position)


## 这个检查点属于哪个房间（房间的 coord，不是自己的位置）
func _room_coord() -> Vector2i:
	var n := get_parent()
	while n != null:
		if n is Room:
			return (n as Room).coord
		n = n.get_parent()
	return Vector2i.ZERO
