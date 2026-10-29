extends Node2D

## 钟：不动的矩形，**没有碰撞箱**，而且**只在被照到的时候显形**。
##
## 外观是 Sprite2D + EchoWorld 的实体材质（和 tile_light 同一个着色器）：
## 亮度取"总的照亮"，所以它响的时候会照亮自己，你冲它喊一声也会把它照出来；
## 听者听不见的时候，对应那层光本来就被闸门压成 0，钟也就不会露出来。
##
## 声学形状由子节点 AcousticBody 提供（照抄 Sprite 的轮廓，transmit = 1：
## 只留形状，声音照穿——不然它自己的声源会被自己的轮廓挡住）。
## 发声由子节点 EchoSource 负责，定时由 EchoSource/Tick（SoundAbility）负责。

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	var world := get_tree().get_first_node_in_group("echo_world")
	if world != null and world.has_method("entity_material"):
		_sprite.material = world.entity_material()
