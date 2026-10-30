extends Node2D

## 主场景：流程。

@onready var player: CharacterBody2D = $Player
@onready var shout_ability = $Player/Echo/Shout   # 只为了拿冷却显示，发声由能力自己负责
@onready var camera: Camera2D = $Camera
@onready var hud: Label = $Hud/Label
@onready var world: EchoWorld = get_node_or_null("EchoWorld") as EchoWorld
@onready var rooms: RoomSystem = get_node_or_null("Rooms") as RoomSystem

## 环境物件（发射器之类）挂到这里，HUD 会多显示一行
var hint := ""


func _ready() -> void:
	camera.make_current()
	add_to_group("main")       # Shooter 之类通过这个找 HUD


func _process(_delta: float) -> void:
	# 听者位置：每个声源按"它在我这儿有多响"决定自己画多亮
	if world != null:
		world.listener = player.position

	_update_hud()


func _update_hud() -> void:
	var where: String = rooms.describe() if rooms != null else "房间 —"
	var cd: float = shout_ability.cooldown_left()
	var cd_txt: String = "可发声" if cd <= 0.0 else "冷却 %.1fs" % cd
	var info: String = world.debug_line() if world != null else ""
	var tail: String = "" if hint.is_empty() else "\n" + hint
	hud.text = "A/D 移动  空格 跳  左键/Q 发声\n%s\n%s\n%s%s" % [where, cd_txt, info, tail]
