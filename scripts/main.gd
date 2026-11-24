extends Node2D

## 主场景：相机与听觉基准。
## 调试 HUD 已移除；背包和交互提示在 Hud 下各自独立。

@onready var listener: EchoListener = $Player/EchoListener
@onready var camera: Camera2D = $Camera
@onready var world: EchoWorld = get_node_or_null("EchoWorld") as EchoWorld


func _ready() -> void:
	camera.make_current()
	# 当前画面用谁的听觉：现在只有 player；以后相机跟谁就换谁
	if world != null:
		world.active_listener = listener
