class_name Inventory
extends Node

## 背包：4 格，每格一个 ItemStack。
##
## 规则（对应设计）：
##   · 每种物品只占一格；同种物品只往这一格里叠。
##   · 一格上限由 ItemDef.max_stack 决定（蓝浆果 = 5）。
##   · 4 格 = 最多 4 种物品；蓝浆果最多 5 个，不会靠第二格再叠 5 个。
##   · 这里只管"收不收得下 / 加减数量"；不碰场景、不碰 UI、不碰拾取实体。
##
## 世界实体（ItemEntity）被拾取时调用 can_add() + add()；收得下才删除实体。

signal changed

const SLOT_COUNT := 4

var slots: Array[ItemStack] = []
## 当前选中的栏位（鼠标滚轮切换）。UI 用它画粗亮边框。
var active_slot := 0


func _init() -> void:
	slots.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		slots[i] = ItemStack.new()


func set_active_slot(index: int) -> void:
	var next := wrapi(index, 0, SLOT_COUNT)
	if next == active_slot:
		return
	active_slot = next
	changed.emit()


## dir = +1 下一格，-1 上一格。滚轮下滚通常传 +1。
func cycle_active(dir: int) -> void:
	set_active_slot(active_slot + dir)


func active_stack() -> ItemStack:
	return get_slot(active_slot)


func get_slot(index: int) -> ItemStack:
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


func count(def: ItemDef) -> int:
	if def == null:
		return 0
	for s in slots:
		if not s.is_empty() and s.def == def:
			return s.count
	return 0


func slot_of(def: ItemDef) -> int:
	if def == null:
		return -1
	for i in slots.size():
		if not slots[i].is_empty() and slots[i].def == def:
			return i
	return -1


func empty_slot() -> int:
	for i in slots.size():
		if slots[i].is_empty():
			return i
	return -1


## 这 n 个能不能**全部**收下。拾取实体先问这个，true 才删实体。
func can_add(def: ItemDef, amount: int = 1) -> bool:
	if def == null or amount <= 0:
		return false
	var idx := slot_of(def)
	if idx >= 0:
		return slots[idx].can_add(amount)
	return empty_slot() >= 0 and amount <= def.max_stack


## 返回实际收下的数量。can_add() 为 true 时它一定等于 amount。
func add(def: ItemDef, amount: int = 1) -> int:
	if not can_add(def, amount):
		return 0
	var idx := slot_of(def)
	if idx < 0:
		idx = empty_slot()
		slots[idx].def = def
	var added := slots[idx].add(amount)
	if added > 0:
		# 当前选中格是空的，就把选中移到这里，捡起来就能看到
		if slots[active_slot].is_empty():
			active_slot = idx
		changed.emit()
	return added


## 从这一格拿走。返回实际拿走数量。
func remove_at(index: int, amount: int = 1) -> int:
	var s := get_slot(index)
	if s == null:
		return 0
	var removed := s.remove(amount)
	if removed > 0:
		changed.emit()
	return removed


func remove(def: ItemDef, amount: int = 1) -> int:
	if def == null:
		return 0
	var idx := slot_of(def)
	return remove_at(idx, amount) if idx >= 0 else 0


func is_empty() -> bool:
	for s in slots:
		if not s.is_empty():
			return false
	return true
