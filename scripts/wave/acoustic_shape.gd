class_name AcousticShape
extends Node2D

## 声场里的一块形状：把自己写进"世界几何"纹理的
##   R = surface   G = 折射率   B = 透声   A = 覆盖
## 以及"显示"纹理的 G = 吸声 α。
##
## 形状从哪来由子类决定，这里只管**属性和生命周期**：
##   AcousticBody   —— 照抄一个实体的贴图轮廓（钟、门、开关、声条）
##   AcousticStroke —— 自己给一条折线（会动的草、绳子）
##
## 填法和瓦片是同一套：只填 Z / c / α，transmit 和 surface 由 AcousticMedium 推出来。
## 换算只有一处，所以"一堵墙"和"一块砖"不会是两套物理。
##
## 外观不归它管：实体自己的 Sprite / 草的 _draw 挂 tile_light 材质，
## 读的是同一张合成光；表面带、照亮、听者闸门全都自动一致。

## 声阻抗 Z：1 = 与空气匹配（声音照穿，钟、草这种只留形状的都填 1），
## 越大越挡声，≥ Z_HARD 当实心。0 = 没填 = 实心（和瓦片一致，别留空气洞）。
@export var Z := 0.0
## 折射率 c：1 = 空气，越大声速越慢
@export_range(1.0, 4.0) var ior := 1.0
## 吸声 α：介质内部的体衰减（0 = 不吸声）。和"挡不挡声"是两回事。
@export_range(0.0, 1.0) var alpha := 0.0
## 显现边缘：1 = 正常出轮廓（默认）。
##   · -1 = 由 Z 推（反射系数）——只给"想让物理决定它亮不亮"的实体用。
##   · 0  = 有形状但没有轮廓。
## 实体不像地形那样成批铺，轮廓是手画的，所以默认不跟着 Z 走：
## 草、钟这类 Z=1（不挡声）的东西按推导只有 0.55，会显得比改之前暗。
@export_range(-1.0, 1.0) var surface := 1.0


func _enter_tree() -> void:
	# 几何那边只认这一个组，不再区分是贴图还是折线
	add_to_group("acoustic_shapes")


## 写进几何纹理 B 通道的值
func transmit_value() -> float:
	return AcousticMedium.transmit_from_z(Z)


## 写进几何纹理 R 通道的值
func surface_value() -> float:
	return surface if surface >= 0.0 else AcousticMedium.surface_from_z(Z)


## 写进显示纹理 G 通道的值
func alpha_value() -> float:
	return clampf(alpha, 0.0, 1.0)


## 造一个要画进几何视口的画布元素。返回 null = 这一帧没有形状。
## 材质由 WaveGeometry 挂（geo_body 着色器 + 上面那几个参数）。
func build_mirror() -> CanvasItem:
	return null


## 每帧把它摆成自己现在的形状。
func pose_mirror(_mirror: CanvasItem) -> void:
	pass
