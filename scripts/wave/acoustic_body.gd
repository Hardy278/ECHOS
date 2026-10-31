class_name AcousticBody
extends AcousticShape

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


func build_mirror() -> CanvasItem:
	var s := Sprite2D.new()
	s.name = "body"
	s.z_index = 3               # 画在图块层之上：实体压过地形
	return s


## 形状 = 实体贴图（含动画当前帧）；没贴图就退回矩形
func pose_mirror(mirror: CanvasItem) -> void:
	var m := mirror as Sprite2D
	if m == null:
		return
	var vis := visual_node()
	if vis is AnimatedSprite2D:
		var a := vis as AnimatedSprite2D
		var frames := a.sprite_frames
		m.texture = frames.get_frame_texture(a.animation, a.frame) if frames != null else null
		m.hframes = 1
		m.vframes = 1
		m.region_enabled = false
		m.centered = a.centered
		m.offset = a.offset
		m.flip_h = a.flip_h
		m.flip_v = a.flip_v
		m.global_transform = a.global_transform
	elif vis is Sprite2D:
		var s := vis as Sprite2D
		m.texture = s.texture
		m.hframes = s.hframes
		m.vframes = s.vframes
		m.frame = s.frame
		m.region_enabled = s.region_enabled
		m.region_rect = s.region_rect
		m.centered = s.centered
		m.offset = s.offset
		m.flip_h = s.flip_h
		m.flip_v = s.flip_v
		m.global_transform = s.global_transform
	else:
		m.texture = _white_tex()
		m.hframes = 1
		m.vframes = 1
		m.region_enabled = false
		m.centered = true
		m.offset = Vector2.ZERO
		m.flip_h = false
		m.flip_v = false
		m.global_transform = global_transform \
				* Transform2D(0.0, rect_size, 0.0, Vector2.ZERO)


## 兜底用的白点（1×1），画成矩形
func _white_tex() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)
