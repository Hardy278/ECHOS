class_name RoomStateStore
extends RefCounted

## 跨房间保留的快照：挂 `Persistent` 的东西（箱子 / 开关 / 门锁）在换房时存一份，
## 回来时按 `state_id` 放回去。
##
## 草和生物不挂 Persistent，所以随房间实例重建自然重置——这是设计，不是遗漏。

var _states: Dictionary = {}     # 坐标 → { state_id: 快照 }


func save(room: Room) -> void:
	if room == null:
		return
	var tree := room.get_tree()
	if tree == null:
		return
	var snap := {}
	for n in tree.get_nodes_in_group("persistent"):
		if not room.is_ancestor_of(n) or not n.has_method("save_state"):
			continue
		snap[n.get("state_id")] = n.call("save_state")
	_states[room.coord] = snap


func restore(room: Room) -> void:
	if room == null:
		return
	var snap: Dictionary = _states.get(room.coord, {})
	if snap.is_empty():
		return
	var tree := room.get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group("persistent"):
		if not room.is_ancestor_of(n) or not n.has_method("load_state"):
			continue
		var id = n.get("state_id")
		if snap.has(id):
			n.call("load_state", snap[id])
