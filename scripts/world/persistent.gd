class_name Persistent
extends Node

## 挂在"切走再回来要保持原样"的东西上：箱子、开关、门锁。
## 不挂这个的一切（生物、草）都随房间实例重建而重置，这是默认行为。
##
## 生命周期：离开房间时 RoomSystem 对房间里所有 Persistent 调 save_state()；
## 进入房间时用存下的字典调 load_state()。只存在内存里，不落盘。

## 同一房间里要唯一；跨房间可以重名（快照是按房间分开存的）
@export var state_id: StringName = &""


func _ready() -> void:
	add_to_group("persistent")


## 返回要跨房间保存的东西；没有就是空字典
func save_state() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	pass
