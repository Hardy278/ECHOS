class_name ItemDef
extends Resource

## 纯粹的"物品概念"：只描述一种物品是什么，不包含任何世界实体、掉落物场景、
## 拾取逻辑或 UI。
##
## 它回答：
##   · 这是什么（id / 名字 / 描述）
##   · 长什么样（icon）
##   · 一格最多叠几个（max_stack）
##
## 它**不回答**：
##   · 地上那个可拾取物是什么节点（那是 ItemEntity + PickupAbility）
##   · 怎么捡、怎么丢、怎么显示（Inventory / UI / 其他系统）
##
## 世界实体引用它；它不反向引用世界实体。

@export var id: StringName = &""
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
@export_range(1, 999) var max_stack := 1


func is_valid() -> bool:
	return not String(id).is_empty() and max_stack >= 1
