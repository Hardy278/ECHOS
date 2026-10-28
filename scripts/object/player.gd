class_name Player
extends CharacterBody2D

## 角色定义[br]
## 落地时发信号出去，落地也是一次发声（由 Echo/Landing 接收）。
## 角色自己的声音不在这里：`Player/Echo` 是一个 EchoSource，心跳 / 落地 / 喊叫
## 是它的子节点，直接对着它发声。

signal landed(strength: float)

@export var speed := 70.0           ## 水平走速（单位/秒）
@export var gravity := 900.0        ## 重力加速度（单位/秒²）
@export var jump_velocity := 254.5  ## 起跳初速

## 角色动态下落速度
var _fall_speed := 0.0

func _physics_process(delta: float) -> void:
	var ix := Input.get_axis("move_left", "move_right")
	velocity.x = ix * speed
	if not is_on_floor():
		velocity.y += gravity * delta
		_fall_speed = velocity.y
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = -jump_velocity
		_fall_speed = 0.0

	var was_floor := is_on_floor()
	move_and_slide()
	if not was_floor and is_on_floor():
		landed.emit(clampf(_fall_speed / 300.0, 0.0, 1.0))
		_fall_speed = 0.0

## 角色存在时间, 基于此算角色的呼吸感.
var _t := 0.0

func _process(delta: float) -> void:
	# 心跳微光
	_t += delta
	var pulse := 0.35 + 0.25 * (0.5 + 0.5 * sin(_t * TAU * 1.0))
	modulate = Color(1.0, 1.0, 1.0, pulse)
