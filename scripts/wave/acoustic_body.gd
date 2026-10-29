class_name AcousticBody
extends Node2D

## 挂在一个实体上：让它的**贴图轮廓**成为声场里的实体。
##
## 每帧把实体自己的 Sprite2D / AnimatedSprite2D 复制一份画进世界几何纹理：
## 贴图不透明的地方写 (吸声, 折射率, 透声, 覆盖)，透明的地方 discard。
##
## 外观不归它管：实体自己的 Sprite 挂 EchoWorld 的实体材质，读同一张合成光。
##
## 注意：实体要有自己的声源（比如钟），`transmit` 必须是 1，
## 否则注入的视线检查会被自己的轮廓挡住，实体永远发不出声音。

## 形状来源；留空就自动找第一个 Sprite2D / AnimatedSprite2D 子节点
@export var visual: CanvasItem
## 找不到贴图时退回的矩形尺寸（世界单位）；有贴图时忽略
@export var rect_size := Vector2(16, 16)
## 吸声性：越大越不留本体（显示端用它压暗）
@export_range(0.0, 1.0) var absorb := 0.0
## 折射率：1 = 空气，越大声速越慢
@export_range(1.0, 4.0) var ior := 1.0
## 透声性：0 = 完全挡住声音，1 = 只留形状（声音照穿，内部也会被照亮）
@export_range(0.0, 1.0) var transmit := 0.0


func _enter_tree() -> void:
	add_to_group("acoustic_bodies")


## 拿形状来源：显式指定的那个，或者实体（父节点）子树里第一个 Sprite / AnimatedSprite
func visual_node() -> CanvasItem:
	if visual != null:
		return visual
	# AcousticBody 一般是实体根节点的子节点，Sprite 是它的兄弟，所以在父节点上找
	var root := get_parent()
	if root == null:
		root = self
	for n in root.find_children("*", "Sprite2D", true, false):
		return n as CanvasItem
	for n in root.find_children("*", "AnimatedSprite2D", true, false):
		return n as CanvasItem
	return null
