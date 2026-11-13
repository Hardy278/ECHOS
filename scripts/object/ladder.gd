@tool
class_name Ladder
extends Area2D

## 梯子：一整根，用 `tiles` 控制这个 8×8 的 Sprite 重复几格。
##
## 结构照花草的写法：
##   Area2D        —— 只负责"玩家在不在这根梯子上"（不挡人、不挡声）
##   Sprite2D      —— ladder.png，region 拉长 + texture_repeat 纵向平铺
##   Collision     —— 12 宽，高度 = 16×tiles + grab_margin（顶部多给一点抓取余量）
##   AcousticBody  —— 形状就是自己的贴图轮廓，Z = 1（只留形状、不挡声）
##
## **锚点在底部中心**：把根节点放在地面/平台表面，梯子就往上长。
## 这样摆梯子不用自己算"中心在哪"。
##
## `tiles` 和 `grab_margin` 是 @tool 的，Inspector 里改完立刻能在编辑器看到形状。
## 运行时才挂实体材质、注册到 "ladders" 组、把 AcousticBody 的 visual 指过来。

const TILE_PX := 16.0       ## 一格的世界尺寸：8px 图 × 房间缩放 2
const SPRITE_PX := 8.0      ## 贴图本身一格多少像素
const WIDTH := 12.0         ## 判定宽度：比一格窄一点，贴边站着也能抓

## 这根梯子有几格。改它，Sprite 的 region 和碰撞盒一起变。
@export_range(1, 32) var tiles := 4:
	set(v):
		tiles = maxi(1, v)
		_refresh()


func _ready() -> void:
	_refresh()
	if Engine.is_editor_hint():
		return

	add_to_group("ladders")
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite != null:
		var world := get_tree().get_first_node_in_group("echo_world")
		if world != null and world.has_method("entity_material"):
			sprite.material = world.entity_material()
	var body := get_node_or_null("Body") as AcousticBody
	if body != null and sprite != null:
		# NodePath 在 .tscn 里读出来是 null，只能在代码里给（见 shooter.gd）
		body.visual = sprite


## 把 tiles 落到 Sprite 的 region 和 Collision 的矩形上。
## 编辑器里也会跑：改一个数字就能看到梯子变长。
##
## 碰撞盒**严格等于**梯子图块的范围（宽 12 是判定宽度，不是高度）：
## 顶上不额外伸出一截。顶格歇脚是玩家状态（perched），不是靠加高碰撞盒实现的。
func _refresh() -> void:
	var sprite := get_node_or_null("Sprite") as Sprite2D
	var col := get_node_or_null("Collision") as CollisionShape2D
	if sprite == null or col == null:
		return

	var h := TILE_PX * tiles
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, SPRITE_PX, SPRITE_PX * tiles)
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sprite.scale = Vector2(2, 2)
	sprite.position = Vector2(0, -h * 0.5)

	# 碰撞形状必须**每个实例一份**：RectangleShape2D 是 Resource，场景里默认共享，
	# 直接改 size 会让所有梯子一起变。场景里已经 resource_local_to_scene，
	# 这里再兜底：拿到共享的就把自己这份复制出来再改。
	var rect := col.shape as RectangleShape2D
	if rect == null:
		rect = RectangleShape2D.new()
	elif not rect.resource_local_to_scene:
		rect = rect.duplicate() as RectangleShape2D
		rect.resource_local_to_scene = true
	col.shape = rect
	rect.size = Vector2(WIDTH, h)
	col.position = Vector2(0, -h * 0.5)


## 梯子顶格的上边缘（世界 y）。根节点在底部中心，所以往上减。
func top_y() -> float:
	return global_position.y - TILE_PX * tiles
