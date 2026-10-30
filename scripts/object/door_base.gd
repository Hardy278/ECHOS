class_name DoorBase
extends StaticBody2D

## 门的身体：一列三格。**上面一格**永远在、永远挡人挡声；**下面两格**是门板，开了就消失。
##
## 这里只管"身体"和"开"这个动作，不管**为什么**开：
##   Door      两条信道都响过 → 开
##   SoundDoor 玩家在门外 4 px 处的声音够响 → 开
##
## 门板挡声 ⇒ 门板内部场恒为 0 ⇒ 它自己发不出声，开门那一声要从门**两侧的空气**里发
## （门挡声，一侧的波过不去另一侧）。
##
## "开过没有"记在 Channels 里：门按房间重建多少次都不会丢。

## 这扇门的唯一名字（Channels 用它记"开过没有"）。重复会报错。
@export var id: StringName = &""
## 开门那一声
@export var ring_amp := 0.5
## 发声点离门中心多远（要落在门体外的空气里）
@export var ring_side := 12.0

## 四张顶格在门贴图里的横向像素位置（都是 8×8，y=16）
const TOP_X := [16, 32, 48, 64]
## 响完多久清场（要比 EchoSource 的 LIVE_SEC = 2.6 稍长，等它衰减干净）
const CLEAR_AFTER := 2.8

var _opened := false
var _ring_gen := 0

@onready var _top: Sprite2D = $Top
@onready var _panel: Sprite2D = $Panel
@onready var _panel_shape: CollisionShape2D = $PanelShape
@onready var _panel_body: AcousticBody = $PanelBody
@onready var _echo: EchoSource = $EchoSource


func _ready() -> void:
	var world := get_tree().get_first_node_in_group("echo_world")
	if world != null and world.has_method("entity_material"):
		_top.material = world.entity_material()
		_panel.material = world.entity_material()

	# 两块声学体各指各的贴图。不能靠 .tscn 里的 NodePath——
	# 那个字段读出来是 null，然后 AcousticBody 的兜底会把它俩都指到第一个 Sprite 上。
	($TopBody as AcousticBody).visual = _top
	($PanelBody as AcousticBody).visual = _panel

	Channels.register_door(id, self)


## 重进房间：这扇门开过，就还是开着的样子（不放那一声）
func restore_open_state() -> void:
	if Channels.is_opened(id):
		_apply_open(false)


func _apply_open(ring: bool) -> void:
	_opened = true
	Channels.mark_opened(id)

	_panel.visible = false
	_panel_shape.set_deferred("disabled", true)

	# 门板整块从几何里拿掉：不是 transmit = 1（那样 cover 还在，
	# 表面带还会给空气层留一圈高光），而是把声学体删掉。
	# 门是单向的，删了不用再建。
	if _panel_body != null:
		_panel_body.queue_free()
		_panel_body = null

	_top.region_rect = Rect2(TOP_X[3], 16, 8, 8)
	if ring:
		_ring()


## 两侧各发一次，隔两帧：一个场只记一个发射点，挨着发会互相覆盖。
## 响完之后等它自己衰减到黑，再清场——顺序不能反，先清会"啪"一下全黑。
func _ring() -> void:
	_ring_gen += 1
	var gen := _ring_gen
	_echo.emit_at(global_position + Vector2(-ring_side, 0), ring_amp, 3)
	await get_tree().process_frame
	await get_tree().process_frame
	_echo.emit_at(global_position + Vector2(ring_side, 0), ring_amp, 3)
	await get_tree().create_timer(CLEAR_AFTER).timeout
	if gen == _ring_gen:
		_echo.clear_field()
