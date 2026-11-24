class_name ItemStack
extends RefCounted

## 一组同种物品：ItemDef + 数量。
##
## 它只是**数据**，不是场景节点。Inventory 的每一格装一个 ItemStack。
## 地上那个可拾取实体不是 ItemStack；实体被删除后，这里的栈继续存在。

var def: ItemDef
var count := 0


func is_empty() -> bool:
	return def == null or count <= 0


func space() -> int:
	if def == null:
		return 0
	return maxi(0, def.max_stack - count)


func can_add(amount: int) -> bool:
	return def != null and amount > 0 and count + amount <= def.max_stack


## 返回实际加进去的数量（最多到 max_stack）。
func add(amount: int) -> int:
	if def == null or amount <= 0:
		return 0
	var take := mini(amount, def.max_stack - count)
	count += take
	return take


## 返回实际拿走数量；拿空后把 def 清掉，这一格回到空。
func remove(amount: int) -> int:
	if amount <= 0 or def == null:
		return 0
	var take := mini(amount, count)
	count -= take
	if count <= 0:
		clear()
	return take


func clear() -> void:
	def = null
	count = 0
