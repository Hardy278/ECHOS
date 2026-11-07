class_name FieldSlab
extends RefCounted

## 切房时跨边界搬运的那一薄片声场的**几何**。
##
## 纯 Rect2i 运算：不碰节点、不碰 GPU，所以能直接测。
## "从哪儿抄"和"贴到哪儿"是同一条公式取反方向——共用这一个函数，两边不会错开。

## 开口边的吸声层宽度（texel）。材质创建时写进着色器的 sponge_w，
## 这里是唯一来源（着色器里的默认值只是占位，不参与计算）。
const SPONGE_W := 28.0
## 搬运的薄片宽度（texel）：至少要盖住一个 stencil
const SEED_W := 12

## dir 是穿越方向（单位向量）：竖片看 x，横片看 y。
## 返回那块矩形；调用方负责检查越界。
static func rect(dir: Vector2i, w: int, h: int) -> Rect2i:
	var inset := int(SPONGE_W)
	if dir.x > 0:
		return Rect2i(w - inset - SEED_W, 0, SEED_W, h)
	if dir.x < 0:
		return Rect2i(inset, 0, SEED_W, h)
	if dir.y > 0:
		return Rect2i(0, h - inset - SEED_W, w, SEED_W)
	return Rect2i(0, inset, w, SEED_W)
