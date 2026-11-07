class_name GroundGrass
extends Area2D

## 地面草：踩上去会摆，同时是声场里的一块形状。
##
## 它自己是场景，三件事各归各的：
##   Area2D            —— 检测"被踩到"
##   AnimatedSprite2D  —— 播 res://sprites/grass_sprite_frames.tres 里的 swing
##   AcousticBody      —— 让它进声场（Z = 1：只留形状、不挡声）
##
## 分开的理由：草如果只是图集里的几帧，它的状态就活在 TileMapLayer 里——
## 没法有自己的声学形状，也没法单独调亮度。
##
## 帧、速度、循环都是帧资源那边的事，这里只管"什么时候播"。
## 显形用的是实体那一份材质（tile_light），所以照亮、听者闸门、表面带全都和
## 图块一致；`dim` 靠 modulate.a 乘到最终 alpha 上（tile_light 里那一句
## `COLOR.a * v * ...` 读的就是顶点色）。

## 一格的宽度（世界单位）：图块 8 px × 房间缩放 2。
@export var tile_px := 16.0
## 显现强度（0~1）。1 = 和钟一样亮；0.55 = 当年那块背景砖。
@export_range(0.0, 1.0) var dim := 0.55

## 帧资源里的动画名
const ANIM := &"swing"

## 摆一遍就停（默认）。
## 帧资源里的 `loop` 是开着的——那是编辑器新建动画的默认值，而它也印在
## `grass_sprite_frames.tres` 里；这里**不去改你那份资源**，而是给每株草复制一份
## SpriteFrames 再把 loop 关掉。所以踩一下 = 弯下去、晃两下、回到立着的姿态。
## 想要"踩过之后一直轻轻摆"，把这个勾关掉就行。
@export var once := true

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _collision: CollisionShape2D = $Collision


func _ready() -> void:
	_sprite.scale = Vector2.ONE * (tile_px / 8.0)
	if once:
		_sprite.sprite_frames = _sprite.sprite_frames.duplicate()
		_sprite.sprite_frames.set_animation_loop(ANIM, false)
	_sprite.animation = ANIM
	_sprite.frame = 0
	_sprite.pause()                    # 平时停在第一帧（立着）
	_sprite.modulate = Color(1.0, 1.0, 1.0, dim)

	var rect := RectangleShape2D.new()
	rect.size = Vector2(tile_px, tile_px)
	_collision.shape = rect

	var world := get_tree().get_first_node_in_group("echo_world")
	if world != null and world.has_method("entity_material"):
		_sprite.material = world.entity_material()

	body_entered.connect(_on_body_entered)
	# 出生时就站在草上（比如从上一间房走过来），也补一次
	for b in get_overlapping_bodies():
		if b.is_in_group("player"):
			_swing()
			break


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_swing()


## 重踩从头播。跑完停在最后一帧（那正好是"立着"的那张）。
func _swing() -> void:
	_sprite.play(ANIM)
