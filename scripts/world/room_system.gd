class_name RoomSystem
extends Node2D

## 房间系统：一屏一间，走出边界就瞬间换到隔壁。
##
## 一次只有一个房间活着——它的图块是当前世界，它的实体是当前世界的实体。
## 切房时整块换掉：旧房间实例被释放、新房间实例进来、所有声源清场、
## EchoWorld 重新绑到新房间的三层图块上。
##
## 它自己只剩"边界判定 + 进房间的那一条序列"，其余都在外面：
##   · RoomRegistry    —— 有哪些房间、某个坐标上是哪个
##   · RoomStateStore  —— 挂 Persistent 的东西的跨房间快照
##   · EchoWorld       —— 房间图块怎么变成当前世界（bind_room）
##
## 本节点必须排在 Player **之后**（同一优先级按树序执行），这样 `_physics_process`
## 里读到的玩家坐标已经是这一帧移动完之后的值。

## 纯通知：房间换完了。想"跟着响应"的东西都订这个，不要去改 `_apply()` 的步骤。
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

## 最后一个踩过的检查点：{ coord: Vector2i, pos: Vector2 }。
## 出生点就是第 0 个，所以永远不会空。
var checkpoint: Dictionary = {}

var _registry := RoomRegistry.new()
var _state := RoomStateStore.new()
## 类型化而不是 `Node` + `has_method("bind_room")`：改名会变成编译错误，
## 而不是一条跑起来才出现的 warning。
var _world: EchoWorld
var _busy := false               # 切房窗口内不再检测边界


func _enter_tree() -> void:
	add_to_group("room_system")


func _ready() -> void:
	_world = get_tree().get_first_node_in_group("echo_world") as EchoWorld
	if _world == null:
		push_warning("RoomSystem: 场景里没有 EchoWorld，房间不会绑定到世界（画面会一直黑）")
	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	_registry.scan(rooms_dir)
	print("[房间表] %s" % _registry.describe())
	# 等所有 _ready（尤其 EchoWorld 的合成层）跑完再进第一个房间
	begin.call_deferred(start_coord)


# ---------------------------------------------------------------- 对外

func acoustics() -> Vector2:
	return current.acoustics() if current != null else Vector2.ZERO


## 哪几条边是开口（左, 右, 上, 下）：有相邻房间 = 开口 = 声学上的吸声边界。
## 世界的尽头（没有相邻房间）保持全反射。
func edges() -> Vector4:
	var l := 1.0 if _registry.has(current_coord + Vector2i.LEFT) else 0.0
	var r := 1.0 if _registry.has(current_coord + Vector2i.RIGHT) else 0.0
	var u := 1.0 if _registry.has(current_coord + Vector2i.UP) else 0.0
	var d := 1.0 if _registry.has(current_coord + Vector2i.DOWN) else 0.0
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
	var room := _apply(coord, Vector2.ZERO, false)
	if room == null:
		return
	# 出生点就是第 0 个检查点：一个都没踩过也有地方回
	if checkpoint.is_empty() and player != null:
		checkpoint = {"coord": coord, "pos": player.global_position}


## 检查点踩到：记下"最后一个"。跨房间也能回来，因为记的是房间坐标 + 房内位置。
func set_checkpoint(coord: Vector2i, pos: Vector2) -> void:
	checkpoint = {"coord": coord, "pos": pos}


## 回到最后一个踩过的检查点。同房间是纯传送，跨房间走 _enter。
func respawn() -> bool:
	if player == null or checkpoint.is_empty():
		push_warning("RoomSystem: 没有可用的检查点")
		return false
	var coord: Vector2i = checkpoint["coord"]
	var pos: Vector2 = checkpoint["pos"]
	if coord != current_coord:
		return _enter(coord, pos)
	player.global_position = pos
	player.velocity = Vector2.ZERO
	_clamp_inside()
	# 旧位置的余晖不该跟过来
	var src := _player_source()
	if src != null:
		src.clear_field()
	return true


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
	if _registry.at(target) == null:
		_push_back(dir)      # 这条边是世界的尽头
		return

	# 抄下正在穿出去的那一薄片：场还没清，这时读到的正好是"刚穿过门口"的时刻
	var src := _player_source()
	var slab: Texture2D = src.capture_slab(dir) if src != null else null

	# 位置连续：右出 → 新房间左侧同高度（越界了多少就带过去多少）
	_enter(target, player.global_position - Vector2(dir) * SIZE, dir, slab)


## 搬进另一个房间。切房和复活共用这一条路；失败时把 _busy 放回去。
func _enter(coord: Vector2i, player_pos: Vector2, dir := Vector2i.ZERO,
		slab: Texture2D = null) -> bool:
	_busy = true
	var room := _apply(coord, player_pos, true, dir, slab)
	_busy = false
	return room != null


## 进房间的**唯一**一条序列。begin 和 _enter 都走这里，所以不会出现
## "开局进的房间少了某一步、切房进的房间多了某一步"这种漂移。
##
## 顺序有依赖：先拔旧房间（碰撞和图块立刻离场，避免和新房间重叠一帧）
## → 搬人 → 清场（旧房的墙形反射不能跟过来）→ 绑世界 → 恢复状态 → 定场薄片。
##
## **这里只放有顺序依赖的步骤。** 只想"知道房间换了"的东西（水、相机、音乐、
## 以后的 HUD）订阅 `room_changed`，不要往这条序列里加行——信号的分发顺序等于
## 连接顺序，在调用点看不见，往这里加久了就又变回上帝函数。
func _apply(coord: Vector2i, at: Vector2, move_player: bool,
		dir := Vector2i.ZERO, slab: Texture2D = null) -> Room:
	var scene := _registry.at(coord)
	if scene == null:
		push_error("RoomSystem: 没有坐标 %s 的房间。把场景放进 %s，并在它根节点的 coord 里填这个坐标"
				% [coord, rooms_dir])
		return null

	var old := current
	if old != null:
		_state.save(old)
		current = null
		remove_child(old)
		old.queue_free()

	var room := _spawn(coord, scene)
	if room == null:
		return null

	if move_player:
		player.global_position = at
		_clamp_inside()

	_clear_fields()
	_bind(room)
	_state.restore(room)

	# 定场：把门口那一薄片写进新房间的入口侧，让刚才那一声跟着进来
	if slab != null and dir != Vector2i.ZERO:
		var src := _player_source()
		if src != null:
			src.seed_slab(slab, dir)

	current = room
	current_coord = coord
	_push_room_state()
	room_changed.emit(room)
	return room


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
	if _world != null:
		_world.bind_room(room)


## 点名"当前所有活着的声源"做一件事。用组而不是信号：
## 听者是个**动态集合**（换房就换一批），信号得逐个连/断，组查询天然就是"现在活着的"。
func _clear_fields() -> void:
	for n in get_tree().get_nodes_in_group("echo_sources"):
		var src := n as EchoSource
		if src != null:
			src.clear_field()


## 房间换了之后，让所有还活着的声源重读声学参数和开口。新房间里的声源会在
## 自己的 _setup 里读一次，这里主要是给跨房间存活的那些（玩家）用。
func _push_room_state() -> void:
	for n in get_tree().get_nodes_in_group("echo_sources"):
		var src := n as EchoSource
		if src != null:
			src.refresh_room()


## 玩家自己的声道：唯一跨房间存活的声源，边界搬运只对它做。
## 返回类型化引用，所以 `capture_slab` / `seed_slab` / `clear_field` 改名会是编译错误。
func _player_source() -> EchoSource:
	return player.get_node_or_null("Echo") as EchoSource if player != null else null
