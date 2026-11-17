@tool
class_name Checkpoint
extends Area2D

## 检查点：踩过就记住，溺水后回到这里。
##
## 它自己就是一个 Area2D：碰没碰到由物理判定，不靠脚本算距离。
## 形状在场景里摆（默认一格），没有贴图——编辑时看得见的只有那个框。
## 复活点就是本节点的位置：摆在哪就在哪重开。
##
## **shape 不是共享资源**：脚本按 width/height/offset_y 为每个实例创建
## 自己的 RectangleShape2D。拖 scenes/checkpoint.tscn 进场景、或复制实例，
## 都会自动得到一份新的 shape，不需要手动 Make Unique。
##
## 只登记"最后一个踩过的"：踩到就把「房间坐标 + 位置」写进 RoomSystem，
## 全局只留一份。房间换掉后这个实例被释放了，登记还在，
## 所以可以在 A 房间淹死、回到 B 房间的检查点。

@export var width := 16.0:
	set(v):
		width = maxf(v, 1.0)
		_refresh()

@export var height := 64.0:
	set(v):
		height = maxf(v, 1.0)
		_refresh()

@export var offset_y := -32.0:
	set(v):
		offset_y = v
		_refresh()


func _ready() -> void:
	_refresh()
	# 额外挂的 Shape2 之类也逐实例拆开，避免复制后共享。
	_make_shapes_local()

	if Engine.is_editor_hint():
		return
	collision_layer = 0      # 不是实体，谁也不该撞它
	collision_mask = 1       # 只在乎玩家那一层
	body_entered.connect(_on_body_entered)


## 主 Shape 由 width/height/offset_y 生成；每次刷新都新建一份，永不共享。
func _refresh() -> void:
	var col := get_node_or_null("Shape") as CollisionShape2D
	if col == null:
		return
	var rect := RectangleShape2D.new()
	rect.resource_local_to_scene = true
	rect.size = Vector2(width, height)
	col.shape = rect
	col.position = Vector2(0, offset_y)


func _make_shapes_local() -> void:
	for c in get_children():
		var col := c as CollisionShape2D
		if col == null or col.shape == null:
			continue
		if col.shape.resource_local_to_scene:
			continue
		var shape := col.shape.duplicate() as Shape2D
		shape.resource_local_to_scene = true
		col.shape = shape


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	var rooms := get_tree().get_first_node_in_group("room_system") as RoomSystem
	if rooms == null:
		return
	rooms.set_checkpoint(_room_coord(), global_position)


## 这个检查点属于哪个房间（房间的 coord，不是自己的位置）
func _room_coord() -> Vector2i:
	var n := get_parent()
	while n != null:
		if n is Room:
			return (n as Room).coord
		n = n.get_parent()
	return Vector2i.ZERO
