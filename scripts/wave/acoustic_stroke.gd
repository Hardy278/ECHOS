class_name AcousticStroke
extends AcousticShape

## 让一条**折线**成为声场里的形状：会动的悬垂草、绳子这类拿不出贴图的东西。
##
## 点由父节点提供：父节点实现 `acoustic_points() -> PackedVector2Array`（世界坐标）。
## 于是"草自己怎么算物理、怎么画"和"它怎么进几何"彻底分开——
## 几何那边不需要知道草是一根链，只看到一条线。
##
## `transmit = 1`（默认）只留形状不挡声：草不会挡住声音，但会出现在表面带里，
## 于是它像地形一样被"撞上去的波"照亮。调低它就变成一根真能挡声的柱子。

## 线宽（世界单位）。草要填 tile 像素宽就是 2。
@export var width := 2.0
## 一丛里我要画第几根（0 起）。父节点按这个下标给出折线。
@export var strand := 0


func build_mirror() -> CanvasItem:
	var line := Line2D.new()
	line.name = "stroke"
	line.z_index = 3
	# 几何纹理只关心覆盖，抗锯齿反而会造出半透明边
	line.antialiased = false
	line.joint_mode = Line2D.LINE_JOINT_SHARP
	line.begin_cap_mode = Line2D.LINE_CAP_BOX
	line.end_cap_mode = Line2D.LINE_CAP_BOX
	line.texture_mode = Line2D.LINE_TEXTURE_NONE
	line.default_color = Color.WHITE
	line.width = width
	return line


func pose_mirror(mirror: CanvasItem) -> void:
	var line := mirror as Line2D
	if line == null:
		return
	line.width = width
	line.points = _points()


## 世界坐标的折线，问父节点要；拿不到就是空的（这一帧没有形状）
func _points() -> PackedVector2Array:
	var p := get_parent()
	if p != null and p.has_method("acoustic_points"):
		return p.call("acoustic_points", strand) as PackedVector2Array
	return PackedVector2Array()
