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
	# 先按信道算一次显示，再处理"开过"或"两条都响过但门当时不在场"。
	# 顺序不能反：_refresh_state() 只看 fired，"开过"是另一份状态。
	_refresh_state()
	if not Channels.is_opened(id) and Channels.is_all_fired(channels):
		# 两条信道是在别的房间按的，门当时没加载，没收到 fired 信号；
		# 这里补开，不能只靠 is_opened（那要门在场开过一次才会记）。
		_apply_open(false)
	else:
		restore_open_state()
	if _opened and not Channels.is_all_fired(channels):
		push_warning("Door '%s': 门是开过的，但 fired 记录只有 %d/%d —— 顶格已按'开过'画成全开" % [
				id, Channels.fired_count(channels), channels.size()])


func _on_fired(channel: StringName) -> void:
	if _opened:
		return
	# 不是这扇门订阅的信道，不响应；否则别的按钮会让所有门一起闪。
	if not channels.has(channel):
		return

	_refresh_state()
	# 每按下一个按钮，门先响一声/闪一下，给"这条信道收到了"的反馈。
	# 最后一条响完再开门，开门本身不再重复响（_apply_open(false)）。
	_ring()

	if Channels.is_all_fired(channels):
		_apply_open(false)


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
