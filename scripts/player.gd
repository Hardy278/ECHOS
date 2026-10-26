extends CharacterBody2D

## 角色：10x16，走速 70，跳跃顶点 36。
## 落地时发信号给主场景——落地也是一次发声，这是声音解谜的基本直觉。

signal landed(strength: float)

const SPEED := 70.0
const GRAVITY := 900.0
const JUMP_V := 254.5          # sqrt(2*900*36) ≈ 254.5 → 顶点 36 px
const SIZE := Vector2(10, 16)

var _t := 0.0
var _fall_speed := 0.0

@onready var _collider: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	# SIZE 是唯一尺寸来源：碰撞盒和画出来的方框都从它推，避免场景里再手写一遍 10x16
	var box := _collider.shape as RectangleShape2D
	if box != null:
		box = box.duplicate() as RectangleShape2D   # 子资源在实例间共享，改前先复制
		box.size = SIZE
		_collider.shape = box


func _physics_process(delta: float) -> void:
	var ix := Input.get_axis("move_left", "move_right")
	velocity.x = ix * SPEED
	if not is_on_floor():
		velocity.y += GRAVITY * delta
		_fall_speed = velocity.y
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = -JUMP_V
		_fall_speed = 0.0

	var was_floor := is_on_floor()
	move_and_slide()
	if not was_floor and is_on_floor():
		landed.emit(clampf(_fall_speed / 300.0, 0.0, 1.0))
		_fall_speed = 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	# 只有极弱的心跳轮廓——别人的光要靠发声去买
	var pulse := 0.35 + 0.25 * (0.5 + 0.5 * sin(_t * TAU * 1.0))
	draw_rect(Rect2(-SIZE.x * 0.5, -SIZE.y * 0.5, SIZE.x, SIZE.y),
		Color(1.0, 0.75, 0.45, pulse), true)
	draw_rect(Rect2(-SIZE.x * 0.5, -SIZE.y * 0.5, SIZE.x, SIZE.y),
		Color(1.0, 0.9, 0.7, 0.35), false, 0.5)
