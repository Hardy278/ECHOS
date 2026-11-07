class_name NormalAtlasMap
extends Resource

## albedo 图集 → 法线图集 的映射表。
##
## 独立成一份资源，**不进层表**：法线是图集的美术数据，不是层的属性。
## 层表管的是画序 / 显示倍率 / 是否进声学，加进去就等于宣称每层都该有法线。

## 元素是 NormalAtlasEntry。用 Array[Resource] 而不是 Array[NormalAtlasEntry]：
## 自定义类型的泛型数组在 .tres 里序列化时更挑解析顺序，Resource 稳。
@export var entries: Array[Resource] = []


## 按 albedo 纹理查那条。查不到返回 null（= 这一层不该走带法线的着色器）。
func find(albedo: Texture2D) -> NormalAtlasEntry:
	if albedo == null:
		return null
	for e in entries:
		var entry := e as NormalAtlasEntry
		if entry != null and entry.is_valid() and entry.albedo == albedo:
			return entry
	return null
