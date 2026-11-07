class_name NormalAtlasEntry
extends Resource

## 映射表里的一条：一张 albedo 图集纹理配一张法线图集。
##
## 为什么粒度是"整张图集"而不是"单个 tile"：法线必须和 albedo 逐像素对齐，
## 所以布局天然一致 —— 第 (2,3) 格的法线就在第 (2,3) 格，坐标本身就是绑定，
## 不需要逐 tile 配置。某个 tile 不想有起伏，就把它那格填平法线 (128,128,255)。
##
## 必须是 `Texture2D` 而不是 png 路径：导出包里 .png 不打包。

## 被配的那张图集纹理（和 TileSetAtlasSource.texture 是同一个对象）
@export var albedo: Texture2D
## 和它同尺寸、同格栅的法线图集。切线空间：R = x, G = y, B = 朝外
@export var normal: Texture2D


func is_valid() -> bool:
	return albedo != null and normal != null
