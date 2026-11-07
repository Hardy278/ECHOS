class_name RoomRegistry
extends RefCounted

## 房间表：一个目录 → {坐标: PackedScene}。
##
## 只回答"有哪些房间 / 某个坐标上是哪个"，不碰节点树、不碰玩家。
## 切房、边界判定、声学开口都问它，而不是各自去翻字典。

var _rooms: Dictionary = {}      # Vector2i → PackedScene
var _dir := ""


## 扫目录：每个 .tscn 一个房间，坐标从房间根节点的 `coord` 读（不实例化）。
func scan(dir_path: String) -> void:
	_dir = dir_path
	_rooms.clear()
	var d := DirAccess.open(dir_path)
	if d == null:
		push_error("RoomRegistry: 打不开房间目录 %s" % dir_path)
		return

	for f in d.get_files():
		# 打包时 .tscn 会转成 .scn，目录里只剩 "xxx.tscn.remap"；
		# 编辑器里则是 xxx.tscn 本身。两种都要认——load() 会自己走 remap。
		var file := f.trim_suffix(".remap")
		if not file.ends_with(".tscn"):
			continue
		var scene := load(dir_path.path_join(file)) as PackedScene
		if scene == null:
			push_warning("RoomRegistry: %s 不是能用的场景" % file)
			continue
		var c := coord_of(scene)
		if _rooms.has(c):
			push_warning("RoomRegistry: 坐标 %s 上有两个房间，%s 会盖掉 %s"
					% [c, file, (_rooms[c] as PackedScene).resource_path.get_file()])
		_rooms[c] = scene

	if _rooms.is_empty():
		push_error("RoomRegistry: %s 里没有房间场景" % dir_path)


func has(coord: Vector2i) -> bool:
	return _rooms.has(coord)


func at(coord: Vector2i) -> PackedScene:
	return _rooms.get(coord) as PackedScene


func is_empty() -> bool:
	return _rooms.is_empty()


## 一行房间表，启动时打到 Output：配置错了一眼能看到
func describe() -> String:
	if _rooms.is_empty():
		return "（空——检查 %s）" % _dir
	var parts: Array = []
	for c in _rooms:
		parts.append("(%d,%d)=%s" % [c.x, c.y, (_rooms[c] as PackedScene).resource_path.get_file()])
	parts.sort()
	return String(", ").join(parts)


## 从场景文件里读根节点的 coord，不实例化（房间的 _ready 不该在启动时乱跑一遍）。
## 没填 = (0,0)，也就是原点那个房间。
static func coord_of(scene: PackedScene) -> Vector2i:
	if scene == null:
		return Vector2i.ZERO
	var state := scene.get_state()
	if state == null:
		return Vector2i.ZERO
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"coord":
			return state.get_node_property_value(0, i)
	return Vector2i.ZERO
