extends Node2D

## 主场景：流程。HUD 的内容**全部从这里往物件上拉**，没有谁往里推。

@onready var player: Player = $Player
@onready var listener: EchoListener = $Player/EchoListener
@onready var shout_ability = $Player/Echo/Shout   # 只为了拿冷却显示，发声由能力自己负责
@onready var camera: Camera2D = $Camera
@onready var hud: Label = $Hud/Label
@onready var world: EchoWorld = get_node_or_null("EchoWorld") as EchoWorld
@onready var rooms: RoomSystem = get_node_or_null("Rooms") as RoomSystem


func _ready() -> void:
	camera.make_current()
	# 当前画面用谁的听觉：现在只有 player；以后相机跟谁就换谁
	if world != null:
		world.active_listener = listener


func _process(_delta: float) -> void:
	_update_hud()


func _update_hud() -> void:
	var where: String = rooms.describe() if rooms != null else "房间 —"
	var cd: float = shout_ability.cooldown_left()
	var cd_txt: String = "可发声" if cd <= 0.0 else "冷却 %.1fs" % cd
	var info: String = world.debug_line() if world != null else ""
	var tail: String = "" if player.hint.is_empty() else "\n" + player.hint
	hud.text = "A/D 移动  W/S 爬梯  空格 跳  左键/Q 发声  ·  %d FPS\n%s\n%s\n%s%s" % [
			Engine.get_frames_per_second(), where, cd_txt, info, tail]
