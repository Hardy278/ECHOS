class_name Door
extends DoorBase

## 信道门：订阅两条信道，两条都响过就开。
##
## 顶格画"响了几条"（两颗点 → 一颗 → 一颗 → 没有），永远在、永远挡。
## 下面两格是门板，开了就消失。身体和"开"这个动作都在 DoorBase 里。

## 订阅的两条信道，顺序 = 上点 / 下点
@export var channels: Array[StringName] = []


func _ready() -> void:
	super._ready()

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
	restore_open_state()
	if _opened and not Channels.is_all_fired(channels):
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
