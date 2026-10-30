class_name Switch
extends Area2D

## 开关：踩上去发一条信道，然后一直是"按下"的样子，不会复位。
##
## 它**挡声**（挂了 AcousticBody），所以它自己的发声点必须在体外：
## 用 EchoSource.emit_at() 从 plate 上方那格空气里发。
##
## 状态存在 Channels 里，所以出门再回来仍然是按下态。

## 这个开关发哪条信道
@export var channel: StringName = &""
## 按下那一声
@export var press_amp := 0.25
## 发声点离自己多远（往上，要落在体外的空气里）
@export var emit_lift := 12.0

## 门贴图里两张皿的位置：(2,6) 未按、(4,6) 已按，都是 8×8，y=48
const UP_X := 16
const DOWN_X := 32
## 响完多久清场（要比 EchoSource 的 LIVE_SEC = 2.6 稍长，等它衰减干净）
const CLEAR_AFTER := 2.8

var _pressed := false
var _ring_gen := 0

@onready var _sprite: Sprite2D = $Sprite
@onready var _echo: EchoSource = $EchoSource


func _ready() -> void:
	var world := get_tree().get_first_node_in_group("echo_world")
	if world != null and world.has_method("entity_material"):
		_sprite.material = world.entity_material()

	if not Channels.is_valid_channel(channel):
		push_error("Switch '%s': 信道名 '%s' 不合规范（小写字母开头，只允许 a-z 0-9 _ . -）"
				% [name, channel])

	# 声学体指着自己这块贴图（不靠 .tscn 的 NodePath，那个字段读出来是 null）
	($Body as AcousticBody).visual = _sprite

	body_entered.connect(_on_body_entered)

	# 重进房间：这条信道已经响过，直接是按下态
	if Channels.is_fired(channel):
		_show_pressed()


func _on_body_entered(body: Node2D) -> void:
	if _pressed or not body.is_in_group("player"):
		return
	if Channels.is_fired(channel):
		return
	_pressed = true
	_show_pressed()
	Channels.fire(channel)
	_ring()


## 从体外的空气里发一声；等它自己衰减到黑（EchoSource.damp = 0.97），再清场。
## 顺序不能反：先清会"啪"一下全黑。
func _ring() -> void:
	_ring_gen += 1
	var gen := _ring_gen
	_echo.emit_at(global_position + Vector2(0, -emit_lift), press_amp, 2)
	await get_tree().create_timer(CLEAR_AFTER).timeout
	if gen == _ring_gen:
		_echo.clear_field()


func _show_pressed() -> void:
	_sprite.region_rect = Rect2(DOWN_X, 48, 8, 8)
