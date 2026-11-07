extends SoundAbility

## 溺水：整个头没进水面 → 变淡 → 立刻搬到最后一个检查点 → 在那儿响一声 →
## 闪几下恢复。
##
## 它是 SoundAbility，因为"溺死"这件事本身就要出声：声源沿父链找到
## Player/Echo，发声点取最近的 Node2D 祖先（= 玩家位置）。所以只要先搬完再
## fire()，这一声自然响在重生点，不用自己传坐标。
##
## 状态用**转移表**：`_next()` 一处写清"哪个状态接受哪个事件"，表里没有的组合
## 就是不接受。这个判断以前散在几个分支里（`if _state != IDLE: return` 之类），
## 加第四个状态时漏掉一处，表现会是"溺水之后再也不会死"。
##
## 流程放在 _physics_process：玩家在自己的 _physics_process 里走完 move_and_slide
## 才轮到子节点，所以读到的永远是这一帧的最终位置；而 Rooms 排在树尾，所以冻结
## 总比越界切房早一步生效。
##
## 淡出写在 player 的 modulate 上；心跳脉动在 Sprite 上，两者相乘，互不覆盖。

## 变淡 / 每一闪 / 闪几次 / 复活后的免死时间（秒）
const FADE := 0.12
const FLASH := 0.09
const FLASHES := 3
const GRACE := 0.5

enum State { IDLE, FADING, FLASHING }

var _player: CharacterBody2D
var _size := Vector2(10.0, 16.0)     # 玩家碰撞箱（从形状读）
var _state := State.IDLE
var _grace := 0.0


func _ready() -> void:
	_player = _find_player()
	if _player == null:
		push_warning("Drown: 没找到角色，溺水不会生效")
		return
	var cs := _player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		_size = (cs.shape as RectangleShape2D).size


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	if _grace > 0.0:
		_grace = maxf(0.0, _grace - delta)
		return
	if not _accepts(&"submerged"):
		return                       # 正在淡出 / 正在闪：不重复触发
	var water := get_tree().get_first_node_in_group("water") as Water
	if water == null:
		return
	var box := Rect2(_player.global_position - _size * 0.5, _size)
	if water.submerged(box):
		_go(&"submerged")


# ---------------------------------------------------------------- 状态转移

## 哪个状态接受哪个事件、去哪个状态。表里没有 = 不接受。
func _next(s: State, event: StringName) -> State:
	match [s, event]:
		[State.IDLE, &"submerged"]:
			return State.FADING
		[State.FADING, &"respawned"]:
			return State.FLASHING
		[State.FLASHING, &"recovered"]:
			return State.IDLE
	return s


func _accepts(event: StringName) -> bool:
	return _next(_state, event) != _state


## 转移 + 进入动作。非法事件静默忽略——表已经说明了它不该发生。
func _go(event: StringName) -> void:
	var next := _next(_state, event)
	if next == _state:
		return
	_state = next
	match _state:
		State.FADING:
			_enter_fading()
		State.FLASHING:
			_enter_flashing()
		State.IDLE:
			_enter_idle()


func _enter_fading() -> void:
	_freeze(true)
	var tw := create_tween()
	tw.tween_property(_player, "modulate:a", 0.0, FADE)
	tw.tween_callback(_go.bind(&"respawned"))


func _enter_flashing() -> void:
	var rooms := get_tree().get_first_node_in_group("room_system")
	if rooms != null:
		rooms.call("respawn")
		fire(1.0)          # 人已经站在检查点上了，这一声就响在那儿
	var tw := create_tween()
	for i in FLASHES:
		tw.tween_property(_player, "modulate:a", 1.0, FLASH)
		if i < FLASHES - 1:
			tw.tween_property(_player, "modulate:a", 0.0, FLASH)
	tw.tween_callback(_go.bind(&"recovered"))


func _enter_idle() -> void:
	_player.modulate = Color.WHITE
	_freeze(false)
	_grace = GRACE


## 冻住：不吃输入、不下落，等补间把人搬完
func _freeze(on: bool) -> void:
	_player.velocity = Vector2.ZERO
	_player.set_physics_process(not on)


func _find_player() -> CharacterBody2D:
	var n: Node = get_parent()
	while n != null:
		if n is CharacterBody2D and n.is_in_group("player"):
			return n as CharacterBody2D
		n = n.get_parent()
	return null
