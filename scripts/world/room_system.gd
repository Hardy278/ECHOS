class_name RoomSystem
extends Node2D

## 房间系统：一屏一间，走出边界就瞬间换到隔壁。
##
## 一次只有一个房间活着——它的图块是当前世界，它的实体是当前世界的实体。
## 切房时整块换掉：旧房间实例被释放、新房间实例进来、所有声源清场、
## EchoWorld 重新绑到新房间的三层图块上。
##
## 房间从 `rooms_dir` 里扫出来（每个 .tscn 一个房间，坐标写在房间身上），
## 四邻由坐标 ±1 推导。
## 没有相邻房间的那条边就是世界的尽头：把玩家挡回边界内侧。
##
## 本节点必须排在 Player **之后**（同一优先级按树序执行），这样 `_physics_process`
## 里读到的玩家坐标已经是这一帧移动完之后的值。

signal room_changed(room: Room)

## 一屏的尺寸，也是场的尺寸
const SIZE := EchoField.FIELD_SIZE
## 挡回边界时留的缝，避免在边界上反复触发
const EDGE_MARGIN := 1.0

## 房间目录：这个文件夹里所有 .tscn 都算房间，坐标写在房间自己的 `coord` 上。
## 加房间 = 把场景丢进这个文件夹，没有表要维护、没有东西能填错。
@export_dir var rooms_dir := "res://scenes/rooms"
## 玩家（撞边界的是它）
@export var player: CharacterBody2D
## 开局进哪个房间
@export var start_coord := Vector2i.ZERO

var current: Room
var current_coord := Vector2i.ZERO

var _rooms: Dictionary = {}      # Vector2i → PackedScene
var _states: Dictionary = {}     # Vector2i → { state_id: 快照 }
var _world: Node                 # EchoWorld
var _busy := false               # 切房窗口内不再检测边界


func _enter_tree() -> void:
	add_to_group("room_system")


func _ready() -> void:
	_world = get_tree().get_first_node_in_group("echo_world")
	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	_scan_rooms()
	# 开局把房间表打到 Output：配置错了一眼就能看到
	print("[房间表] %s" % _describe_rooms())
	# 等所有 _ready（尤其 EchoWorld 的合成层）跑完再进第一个房间
	begin.call_deferred(start_coord)


# ---------------------------------------------------------------- 对外

func acoustics() -> Vector2:
	return current.acoustics() if current != null else Vector2.ZERO


## 哪几条边是开口（左, 右, 上, 下）：有相邻房间 = 开口 = 声学上的吸声边界。
## 世界的尽头（没有相邻房间）保持全反射，和以前一样。
func edges() -> Vector4:
	var l := 1.0 if _rooms.has(current_coord + Vector2i.LEFT) else 0.0
	var r := 1.0 if _rooms.has(current_coord + Vector2i.RIGHT) else 0.0
	var u := 1.0 if _rooms.has(current_coord + Vector2i.UP) else 0.0
	var d := 1.0 if _rooms.has(current_coord + Vector2i.DOWN) else 0.0
	return Vector4(l, r, u, d)


## 一行状态，交给 HUD
func describe() -> String:
	if current == null:
		return "房间 —"
	var where := "%d,%d" % [current_coord.x, current_coord.y]
	if current.title.is_empty():
		return "房间 (%s)" % where
	return "房间 (%s) %s" % [where, current.title]


func begin(coord: Vector2i) -> void:
	var scene := _scene_at(coord)
	if scene == null:
		push_error("RoomSystem: 没有坐标 %s 的房间。" % coord
				+ "把房间场景放进 %s，并在它根节点的 coord 里填这个坐标。" % rooms_dir)
		return
	current = _spawn(coord, scene)
	current_coord = coord
	_bind(current)
	_restore_state(current)
	_push_room_state()
	room_changed.emit(current)


# ---------------------------------------------------------------- 边界

func _physics_process(_delta: float) -> void:
	if _busy or current == null or player == null:
		return

	var p := player.global_position
	# 每个方向越出去多少；取最大的那个轴作为切换方向
	var out_x := maxf(p.x - SIZE.x, -p.x)
	var out_y := maxf(p.y - SIZE.y, -p.y)
	if out_x <= 0.0 and out_y <= 0.0:
		return

	var dir := Vector2i.ZERO
	if out_x >= out_y:
		dir = Vector2i(1, 0) if p.x > 0.0 else Vector2i(-1, 0)
	else:
		dir = Vector2i(0, 1) if p.y > 0.0 else Vector2i(0, -1)

	_cross(dir)


func _cross(dir: Vector2i) -> void:
	var target := current_coord + dir
	var scene := _scene_at(target)
	if scene == null:
		_push_back(dir)      # 这条边是世界的尽头
		return

	_busy = true
	_save_state(current)

	# 抄下正在穿出去的那一薄片：场还没清，这时读到的正好是"刚穿过门口"的时刻
	var src := _player_source()
	var slab: Texture2D = null
	if src != null and src.has_method("capture_slab"):
		slab = src.call("capture_slab", dir) as Texture2D

	# 先拔旧房间：它的碰撞和图块立刻离场，避免和新房间重叠一帧
	var old := current
	current = null
	if old != null:
		remove_child(old)
		old.queue_free()

	var room := _spawn(target, scene)

	# 位置连续：右出 → 新房间左侧同高度（越界了多少就带过去多少）
	player.global_position -= Vector2(dir) * SIZE
	_clamp_inside()

	# 清场：旧房间的墙形反射和残余不能跟过来
	_clear_fields()

	_bind(room)
	_restore_state(room)

	# 定场：把门口那一薄片写进新房间的入口侧，让刚才那一声跟着进来
	if slab != null and src != null and src.has_method("seed_slab"):
		src.call("seed_slab", slab, dir)

	current = room
	current_coord = target
	_busy = false
	_push_room_state()
	room_changed.emit(room)


func _push_back(dir: Vector2i) -> void:
	var p := player.global_position
	if dir.x > 0:
		p.x = SIZE.x - EDGE_MARGIN
	elif dir.x < 0:
		p.x = EDGE_MARGIN
	elif dir.y > 0:
		p.y = SIZE.y - EDGE_MARGIN
	elif dir.y < 0:
		p.y = EDGE_MARGIN
	player.global_position = p

	# 撞墙了就别继续往那个方向推，否则边界上会一直抖
	var v := player.velocity
	if dir.x != 0:
		v.x = 0.0
	if dir.y != 0:
		v.y = 0.0
	player.velocity = v


func _clamp_inside() -> void:
	var lo := Vector2(EDGE_MARGIN, EDGE_MARGIN)
	var hi := SIZE - lo
	player.global_position = player.global_position.clamp(lo, hi)


# ---------------------------------------------------------------- 装配

## 扫房间目录：每个 .tscn 一个房间，坐标从房间根节点的 `coord` 读（不实例化）
func _scan_rooms() -> void:
	_rooms.clear()
	var dir := DirAccess.open(rooms_dir)
	if dir == null:
		push_error("RoomSystem: 打不开房间目录 %s" % rooms_dir)
		return
	for f in dir.get_files():
		if not f.ends_with(".tscn"):
			continue
		var scene := load(rooms_dir.path_join(f)) as PackedScene
		if scene == null:
			push_warning("RoomSystem: %s 不是能用的场景" % f)
			continue
		var c := coord_of(scene)
		if _rooms.has(c):
			push_warning("RoomSystem: 坐标 %s 上有两个房间，%s 会盖掉 %s"
					% [c, f, (_rooms[c] as PackedScene).resource_path.get_file()])
		_rooms[c] = scene
	if _rooms.is_empty():
		push_error("RoomSystem: %s 里没有房间场景" % rooms_dir)


## 从场景文件里读根节点的 coord，不实例化（房间的 _ready 不该在启动时乱跑一遍）
static func coord_of(scene: PackedScene) -> Vector2i:
	if scene == null:
		return Vector2i.ZERO
	var state := scene.get_state()
	if state == null:
		return Vector2i.ZERO
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"coord":
			return state.get_node_property_value(0, i)
	return Vector2i.ZERO       # 没填 = (0,0)，也就是原点那个房间


func _describe_rooms() -> String:
	if _rooms.is_empty():
		return "（空——检查 %s）" % rooms_dir
	var parts: Array = []
	for c in _rooms:
		parts.append("(%d,%d)=%s" % [c.x, c.y, (_rooms[c] as PackedScene).resource_path.get_file()])
	parts.sort()
	return String(", ").join(parts)


func _scene_at(coord: Vector2i) -> PackedScene:
	return _rooms.get(coord) as PackedScene


func _spawn(coord: Vector2i, scene: PackedScene) -> Room:
	var room := scene.instantiate() as Room
	if room == null:
		push_error("RoomSystem: %s 的根节点不是 Room" % coord)
		return null
	if room.coord != coord:
		push_warning("RoomSystem: 房间 %s 里填的 coord 是 %s，以房间表为准" % [coord, room.coord])
	room.coord = coord
	add_child(room)          # 进树，_ready 立刻跑
	return room


func _bind(room: Room) -> void:
	if _world != null and _world.has_method("bind_room"):
		_world.call("bind_room", room)


func _clear_fields() -> void:
	for s in get_tree().get_nodes_in_group("echo_sources"):
		if s.has_method("clear_field"):
			s.call("clear_field")


## 房间换了之后，让所有还活着的声源重读声学参数和开口。新房间里的声源会在
## 自己的 _setup 里读一次，这里主要是给跨房间存活的那些（玩家）用。
func _push_room_state() -> void:
	for s in get_tree().get_nodes_in_group("echo_sources"):
		if s.has_method("refresh_room"):
			s.call("refresh_room")


## 玩家自己的声道：唯一跨房间存活的声源，边界搬运只对它做
func _player_source() -> Node:
	return player.get_node_or_null("Echo") if player != null else null


# ---------------------------------------------------------------- 状态快照

## 箱子 / 开关 / 门锁这类挂了 Persistent 的东西跨房间保留；草和生物不挂，自然重置
func _save_state(room: Room) -> void:
	if room == null:
		return
	var snap := {}
	for n in get_tree().get_nodes_in_group("persistent"):
		if not room.is_ancestor_of(n) or not n.has_method("save_state"):
			continue
		snap[n.get("state_id")] = n.call("save_state")
	_states[room.coord] = snap


func _restore_state(room: Room) -> void:
	if room == null:
		return
	var snap: Dictionary = _states.get(room.coord, {})
	if snap.is_empty():
		return
	for n in get_tree().get_nodes_in_group("persistent"):
		if not room.is_ancestor_of(n) or not n.has_method("load_state"):
			continue
		var id = n.get("state_id")
		if snap.has(id):
			n.call("load_state", snap[id])
