extends Node

## 信道总线（autoload：Channels）。
##
## 按钮**发**信道，门**订阅**信道；两边谁也不认识谁。
## 一条信道可以被任意多个按钮驱动（OR），也可以被任意多扇门订阅（广播）。
##
## 房间是"进来建、出去拆"的，所以"哪条信道响过了""哪扇门开过了"
## 必须活在这里，不能挂在房间里的节点上。

signal fired(channel: StringName)

## 信道命名规范：小写字母开头，只允许 a-z 0-9 _ . -
## 建议写法：<房间>.<机关>，例如 r0_0.sw1 / r0_0.gate1
const NAME_PATTERN := "^[a-z][a-z0-9_.-]*$"

var _fired: Dictionary = {}
var _opened: Dictionary = {}
var _doors: Dictionary = {}      # 门 id → WeakRef（用来查重）


## 一条信道响了一次。锁存：同一条信道不会重复触发。
func fire(channel: StringName) -> void:
	if channel == &"":
		push_error("Channels: 空信道名，忽略")
		return
	if _fired.get(channel, false):
		return
	_fired[channel] = true
	fired.emit(channel)


func is_fired(channel: StringName) -> bool:
	return bool(_fired.get(channel, false))


## 这些信道是不是都响过了
func is_all_fired(list: Array) -> bool:
	if list.is_empty():
		return false
	for c in list:
		if not is_fired(c):
			return false
	return true


## 这些信道里响了几条
func fired_count(list: Array) -> int:
	var n := 0
	for c in list:
		if is_fired(c):
			n += 1
	return n


## 门登记自己的 id：同一个 id 只能有一扇门活着。
## 防止"复制一扇门、改了位置忘了改 id"这种撞车。
func register_door(id: StringName, door: Node) -> void:
	if id == &"":
		push_error("Channels: 门没有填 id（%s）" % door.name)
		return
	var ref: WeakRef = _doors.get(id)
	var other: Node = ref.get_ref() if ref != null else null
	if other != null and other != door:
		push_error("Channels: 门 id '%s' 撞车：%s 和 %s" % [id,
				String(other.get_path()), String(door.get_path())])
	_doors[id] = weakref(door)


func is_opened(id: StringName) -> bool:
	return bool(_opened.get(id, false))


func mark_opened(id: StringName) -> void:
	_opened[id] = true


## 信道名是否合规范
func is_valid_channel(channel: StringName) -> bool:
	if String(channel).is_empty():
		return false
	var re := RegEx.new()
	re.compile(NAME_PATTERN)
	return re.search(String(channel)) != null
