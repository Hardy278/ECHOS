class_name AcousticShape
extends Node2D

## 声场里的一块形状：把自己写进"世界几何"纹理的
##   R = 吸声   G = 折射率   B = 透声   A = 覆盖
##
## 形状从哪来由子类决定，这里只管**属性和生命周期**：
##   AcousticBody   —— 照抄一个实体的贴图轮廓（钟、门、开关、声条）
##   AcousticStroke —— 自己给一条折线（会动的草、绳子）
##
## 外观不归它管：实体自己的 Sprite / 草的 _draw 挂 tile_light 材质，
## 读的是同一张合成光；表面带、照亮、听者闸门全都自动一致。

## 吸声性：越大越不留本体（显示端用 1-absorb 压暗）
@export_range(0.0, 1.0) var absorb := 0.0
## 折射率：1 = 空气，越大声速越慢
@export_range(1.0, 4.0) var ior := 1.0
## 透声性：0 = 完全挡住声音，1 = 只留形状（声音照穿，内部也会被照亮）
@export_range(0.0, 1.0) var transmit := 0.0


func _enter_tree() -> void:
	# 几何那边只认这一个组，不再区分是贴图还是折线
	add_to_group("acoustic_shapes")


## 造一个要画进几何视口的画布元素。返回 null = 这一帧没有形状。
## 材质由 WaveGeometry 挂（geo_body 着色器 + 下面三个参数）。
func build_mirror() -> CanvasItem:
	return null


## 每帧把它摆成自己现在的形状。
func pose_mirror(_mirror: CanvasItem) -> void:
	pass
