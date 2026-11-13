class_name Player
extends CharacterBody2D

## 角色定义[br]
## 落地时发信号出去，落地也是一次发声（由 Echo/Landing 接收）。
## 角色自己的声音不在这里：`Player/Echo` 是一个 EchoSource，心跳 / 落地 / 喊叫
## 是它的子节点，直接对着它发声。
##
## 激波推进也在这里：坐下（`sit`）和发射（`launch`）由环境里的 Shooter 调用，
## 位移和发声都归角色自己。

signal landed(strength: float)
## 激波推进的开始 / 结束。音频（ThrustAbility）听这两个信号；
## 声场那边每帧的注入不受影响——那是激波的形状，一帧都不能少。
signal dash_started
signal dash_ended

const GameConst := preload("res://scripts/world/constants.gd")

@export var speed := 70.0           ## 水平走速（单位/秒）
## 重力加速度不在这里：全局只有 GameConst.GRAVITY 一份，直接引用。
## 以前这里有一个 `@export var gravity := GameConst.GRAVITY`，既能被 Inspector
## 覆盖、又和"全局唯一"矛盾；角色不该有第二个重力。
@export var jump_velocity := 254.5  ## 起跳初速
@export var coyote_time := 0.1      ## 土狼时间：走出平台边缘后还能起跳的宽限（秒）
@export var dash_amp := 0.8         ## 激波推进时的发声强度（再乘 实际速度/末速）
@export var climb_speed := 50.0     ## 爬梯速度（单位/秒）
@export var climb_side_speed := 60.0 ## 爬梯时左右移动速度
## 从梯子上跳开后，多久之内不再自动抓回去。
## 这段"放手时间"就是"按死 W + 点跳"能加速的原因：跳的冲量先把人送上去，
## 宽限结束再抓回梯子接着爬。
@export var ladder_jump_grace := 0.12

## 防止 v = 0 时功率除法爆掉
const DASH_V_FLOOR := 20.0
## 角色碰撞盒半高（10×16 的 16）。爬梯顶格判定用它
const HALF_HEIGHT := 8.0

## 环境物件（发射器之类）写进来的提示；HUD 每帧从角色身上拉
var hint := ""

## 角色动态下落速度
var _fall_speed := 0.0
## 土狼时间剩余
var _coyote := 0.0
## 朝向（最后一次水平输入的方向），发射方向用它
var _facing := 1.0
## 坐在发射器里：完全静止
var _seated := false

## 激波推进状态；_dash_dir == 0 就是没在推进
var _dash_dir := 0.0
var _dash_speed := 0.0
var _dash_max := 0.0
var _dash_power := 0.0
var _dash_left := 0.0

## 爬梯状态
var _climbing := false
## 爬到顶格后"驻足"：站在梯子顶，不吃重力，S 继续下爬、A/D 走开、跳跳走
var _perched := false
var _ladder: Ladder = null
var _perch_ladder: Ladder = null
var _ladder_grace := 0.0


func _enter_tree() -> void:
	add_to_group("player")     # RoomSystem 找它判边界


# ---------------------------------------------------------------- 对外

func is_dashing() -> bool:
	return _dash_dir != 0.0


func is_climbing() -> bool:
	return _climbing


func is_perched() -> bool:
	return _perched


## 坐下：完全静止，等发射
func sit() -> void:
	_seated = true
	_climbing = false
	_perched = false
	_ladder = null
	_perch_ladder = null
	velocity = Vector2.ZERO


## 起身（走出发射器 / 发射）
func stand() -> void:
	_seated = false


## 激波推进：恒定功率加速，无视重力、不能跳、不能改向。撞墙或时间到就结束。
func launch(dir: float, power: float, max_speed: float, duration: float) -> void:
	_seated = false
	_climbing = false
	_perched = false
	_ladder = null
	_perch_ladder = null
	_dash_dir = signf(dir) if not is_zero_approx(dir) else 1.0
	_dash_speed = absf(velocity.x)
	_dash_max = max_speed
	_dash_power = power
	_dash_left = duration
	dash_started.emit()


# ---------------------------------------------------------------- 帧

func _physics_process(delta: float) -> void:
	if is_dashing():
		_step_dash(delta)
		return

	if _ladder_grace > 0.0:
		_ladder_grace = maxf(0.0, _ladder_grace - delta)

	if _perched:
		_perch_step(delta)
		return

	if _climbing:
		_climb_step(delta)
		return

	var ix := Input.get_axis("move_left", "move_right")
	if not is_zero_approx(ix):
		_facing = signf(ix)

	velocity.x = 0.0 if _seated else ix * speed

	# 土狼时间：还在地上就续满，离地后一格一格扣
	_coyote = coyote_time if is_on_floor() else maxf(0.0, _coyote - delta)

	if not is_on_floor():
		velocity.y += GameConst.GRAVITY * delta
		_fall_speed = velocity.y

	var jump_pressed := Input.is_action_just_pressed("jump")
	if not _seated and _coyote > 0.0 and jump_pressed:
		velocity.y = -jump_velocity
		_fall_speed = 0.0
		_coyote = 0.0

	# 梯子：**跳的优先级更高**。jump 刚按下的这一帧不附着，
	# 所以"按死 W + 点跳"永远是先跳出去，宽限结束再被 W 抓回梯子。
	if not _seated and not jump_pressed and _ladder_grace <= 0.0 and _try_start_climb():
		_climb_step(delta)
		return

	var was_floor := is_on_floor()
	move_and_slide()
	if not was_floor and is_on_floor():
		landed.emit(clampf(_fall_speed / 300.0, 0.0, 1.0))
		_fall_speed = 0.0


# ---------------------------------------------------------------- 爬梯

## 爬梯的一帧：W/S（或 ↑/↓）上下，A/D 左右（climb_side_speed）；
## 空格优先解除并起跳。**不把角色拉到梯子中心**：横向完全由玩家控制。
func _climb_step(_delta: float) -> void:
	if Input.is_action_just_pressed("jump"):
		_end_climb(true)
		return

	var ix := Input.get_axis("move_left", "move_right")
	var dir := Input.get_axis("move_up", "move_down")
	if not is_zero_approx(ix):
		_facing = signf(ix)
	velocity = Vector2(ix * climb_side_speed, dir * climb_speed)
	move_and_slide()
	_fall_speed = 0.0
	_coyote = 0.0

	# 爬到顶格：停在梯子顶"歇脚"，不再往上挤。
	# 之后 S 继续下爬、A/D 走下平台、空格跳走。
	if dir < 0.0 and _ladder != null and is_instance_valid(_ladder) \
			and global_position.y + HALF_HEIGHT <= _ladder.top_y() + 1.0:
		_perch(_ladder)
		return

	# 左右走出梯子的判定范围就松手，下一帧开始自由落体
	if _ladder == null or not is_instance_valid(_ladder) or not _ladder.overlaps_body(self):
		_climbing = false
		_ladder = null


## 身上碰到梯子并且按了上下：挂上去。
## 调用点已经保证 jump 没按、且不在"刚跳离"的宽限里。
func _try_start_climb() -> bool:
	if is_zero_approx(Input.get_axis("move_up", "move_down")):
		return false
	for n in get_tree().get_nodes_in_group("ladders"):
		var l := n as Ladder
		if l != null and l.overlaps_body(self):
			_start_climb(l)
			return true
	return false


func _start_climb(l: Ladder) -> void:
	_climbing = true
	_perched = false
	_ladder = l
	_perch_ladder = null
	velocity = Vector2.ZERO
	_fall_speed = 0.0
	_coyote = 0.0


## 站到梯子顶格上。位置取"脚刚好在顶格上边缘"，不吃重力。
func _perch(l: Ladder) -> void:
	_climbing = false
	_ladder = null
	_perched = true
	_perch_ladder = l
	velocity = Vector2.ZERO
	_fall_speed = 0.0
	_coyote = 0.0
	global_position.y = l.top_y() - HALF_HEIGHT


## 顶格驻足：S 下爬，A/D 走下平台，空格跳走。
func _perch_step(_delta: float) -> void:
	if _perch_ladder == null or not is_instance_valid(_perch_ladder):
		_perched = false
		_perch_ladder = null
		return

	if Input.is_action_just_pressed("jump"):
		_perched = false
		_perch_ladder = null
		velocity.y = -jump_velocity
		_ladder_grace = ladder_jump_grace
		_fall_speed = 0.0
		_coyote = 0.0
		return

	if Input.is_action_just_pressed("move_down"):
		_resume_climb()
		return

	# 左右走：离开顶格，下一帧按正常重力/移动处理（能直接走到旁边平台上）
	if not is_zero_approx(Input.get_axis("move_left", "move_right")):
		_perched = false
		_perch_ladder = null
		return

	velocity = Vector2.ZERO


## 从顶格回到梯子上：把身体往下挪进梯子的判定范围，再交给 _climb_step。
func _resume_climb() -> void:
	var l := _perch_ladder
	if l == null or not is_instance_valid(l):
		_perched = false
		_perch_ladder = null
		return
	_start_climb(l)
	global_position.y = l.top_y() + 4.0


func _end_climb(jump: bool) -> void:
	_climbing = false
	_ladder = null
	_perched = false
	_perch_ladder = null
	_fall_speed = 0.0
	_coyote = 0.0
	if jump:
		velocity.y = -jump_velocity
		_ladder_grace = ladder_jump_grace


## 恒定功率：v̇ = power / v。低速推力大、高速推力小，所以速度按 √t 长。
func _step_dash(delta: float) -> void:
	_dash_speed = minf(_dash_speed + _dash_power / maxf(_dash_speed, DASH_V_FLOOR) * delta,
			_dash_max)
	velocity = Vector2(_dash_dir * _dash_speed, 0.0)   # 无视重力
	move_and_slide()

	# 发声跟着**实际**速度走：撞墙那一帧 v 归零，激波立刻哑，
	# 不会变成顶着门蹭的蛆。
	_echo.emit_at(global_position,
			dash_amp * clampf(absf(velocity.x) / maxf(_dash_max, 0.001), 0.0, 1.0), 1)

	_dash_left -= delta
	if _dash_left <= 0.0 or is_on_wall() or absf(velocity.x) < _dash_max * 0.1:
		_dash_dir = 0.0
		_dash_speed = 0.0
		_dash_left = 0.0
		dash_ended.emit()


## 角色存在时间, 基于此算角色的呼吸感.
var _t := 0.0

@onready var _sprite: Sprite2D = $Sprite
@onready var _echo: EchoSource = $Echo
@onready var _listener: AudioListener2D = $AudioListener


func _ready() -> void:
	# 相机钉在房间中心不动，2D 声像的基准必须是角色自己，不是屏幕中心。
	# 不设这个，引擎会把"偏右"算成相对 (240,135) 的偏右，而不是相对你的耳朵。
	_listener.make_current()

func _process(delta: float) -> void:
	# 心跳微光。写在 Sprite 上而不是自己身上：自己的 modulate 留给溺水淡出，
	# 两个透明度相乘，互不覆盖。
	_t += delta
	var pulse := 0.35 + 0.25 * (0.5 + 0.5 * sin(_t * TAU * 1.0))
	_sprite.modulate = Color(1.0, 1.0, 1.0, pulse)
