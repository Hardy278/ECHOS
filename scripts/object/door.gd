class_name Door
extends StaticBody2D

## 门：一列三格。**上面一格**是显示（亮几颗 = 这扇门的两条信道响了几条），
## 永远在、永远挡人挡声；**下面两格**是门板，两条信道都响过就消失。
##
## 门板挡声 ⇒ 门板内部场恒为 0 ⇒ 它自己发不出声。
## 所以开门那一声用 EchoSource.emit_from()，从门**左右两侧的空气**各发一次
## （门挡声，一侧的波过不去另一侧）。
##
## 状态存在 Channels 里：它按房间重建多少次都不会丢。

## 这扇门的唯一名字（Channels 用它记"开过没有"）。重复会报错。
@export var id: StringName = &""
## 订阅的两条信道，顺序 = 上点 / 下点
@export var channels: Array[StringName] = []
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
	for c in channels:
		if not Channels.is_valid_channel(c):
			push_error("Door '%s': 信道名 '%s' 不合规范（小写字母开头，只允许 a-z 0-9 _ . -）" % [id, c])
	if channels.size() != 2:
		push_warning("Door '%s': 订阅了 %d 条信道，但显示只有两颗点" % [id, channels.size()])

	Channels.fired.connect(_on_fired)
	# 先按信道算一次显示，再套"开过"的最终态——
	# 顺序不能反：_refresh_state() 只看 fired，"开过"是另一份状态，
	# 反着来会把已经全开的门顶格改回少几颗。
	_refresh_state()
	if Channels.is_opened(id):
		_apply_open(false)
		if not Channels.is_all_fired(channels):
			push_warning("Door '%s': 门是开过的，但 fired 记录只有 %d/%d —— 顶格已按'开过'画成全开" % [
					id, Channels.fired_count(channels), channels.size()])


func _on_fired(_channel: StringName) -> void:
	if _opened:
		return
	_refresh_state()
	if Channels.is_all_fired(channels):
		_apply_open(true)


## 顶格换成"响了几条"那一张。"开过"优先：开过的门永远是全开图案，
## 不受 fired 记录是否完整影响。
func _refresh_state() -> void:
	if Channels.is_opened(id):
		_top.region_rect = Rect2(TOP_X[3], 16, 8, 8)
		return
	if channels.is_empty():
		return
	var n := clampi(Channels.fired_count(channels), 0, 3)
	_top.region_rect = Rect2(TOP_X[n], 16, 8, 8)


func _apply_open(ring: bool) -> void:
	_opened = true
	Channels.mark_opened(id)

	_panel.visible = false
	_panel_shape.set_deferred("disabled", true)

	# 门板整块从几何里拿掉：不是 transmit = 1（那样 cover 还在，
	# 表面带还会给空气层留一圈高光），而是把声学体删掉，
	# _sweep_bodies() 会连镜像一起清掉。门是单向的，删了不用再建。
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
