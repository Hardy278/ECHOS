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

const GameConst := preload("res://scripts/world/constants.gd")

@export var speed := 70.0           ## 水平走速（单位/秒）
@export var gravity := GameConst.GRAVITY  ## 重力加速度（单位/秒²）；全局唯一一份，见 GameConst
@export var mass := GameConst.PLAYER_MASS ## 质量。只用来和别的物体分撞击速度，不影响下落
@export var jump_velocity := 254.5  ## 起跳初速
@export var coyote_time := 0.1      ## 土狼时间：走出平台边缘后还能起跳的宽限（秒）
@export var dash_amp := 0.8         ## 激波推进时的发声强度（再乘 实际速度/末速）

## 防止 v = 0 时功率除法爆掉
const DASH_V_FLOOR := 20.0

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


func _enter_tree() -> void:
	add_to_group("player")     # RoomSystem 找它判边界


# ---------------------------------------------------------------- 对外

func is_dashing() -> bool:
	return _dash_dir != 0.0


## 坐下：完全静止，等发射
func sit() -> void:
	_seated = true
	velocity = Vector2.ZERO


## 起身（走出发射器 / 发射）
func stand() -> void:
	_seated = false


## 发射：恒定功率加速，无视重力、不能跳、不能改向。撞墙或时间到就结束。
func launch(dir: float, power: float, max_speed: float, duration: float) -> void:
	_seated = false
	_dash_dir = signf(dir) if not is_zero_approx(dir) else 1.0
	_dash_speed = absf(velocity.x)
	_dash_max = max_speed
	_dash_power = power
	_dash_left = duration


# ---------------------------------------------------------------- 帧

func _physics_process(delta: float) -> void:
	if is_dashing():
		_step_dash(delta)
		return

	var ix := Input.get_axis("move_left", "move_right")
	if not is_zero_approx(ix):
		_facing = signf(ix)

	velocity.x = 0.0 if _seated else ix * speed

	# 土狼时间：还在地上就续满，离地后一格一格扣
	_coyote = coyote_time if is_on_floor() else maxf(0.0, _coyote - delta)

	if not is_on_floor():
		velocity.y += gravity * delta
		_fall_speed = velocity.y
	if not _seated and _coyote > 0.0 and Input.is_action_just_pressed("jump"):
		velocity.y = -jump_velocity
		_fall_speed = 0.0
		_coyote = 0.0

	var was_floor := is_on_floor()
	move_and_slide()
	if not was_floor and is_on_floor():
		landed.emit(clampf(_fall_speed / 300.0, 0.0, 1.0))
		_fall_speed = 0.0


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


## 角色存在时间, 基于此算角色的呼吸感.
var _t := 0.0

@onready var _sprite: Sprite2D = $Sprite
@onready var _echo: EchoSource = $Echo

func _process(delta: float) -> void:
	# 心跳微光。写在 Sprite 上而不是自己身上：自己的 modulate 留给溺水淡出，
	# 两个透明度相乘，互不覆盖。
	_t += delta
	var pulse := 0.35 + 0.25 * (0.5 + 0.5 * sin(_t * TAU * 1.0))
	_sprite.modulate = Color(1.0, 1.0, 1.0, pulse)
