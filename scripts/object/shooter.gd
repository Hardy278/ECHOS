class_name Shooter
extends Node2D

## 发射器：一格大小、透声、没有碰撞箱。
##
## 玩家站进来 → 按 X 坐下（人物完全静止）→ A/D 只改朝向、不移动
## → 再按 X 发射。被发射的是玩家自己，位移和发声都在 Player 里。
##
## 恒定功率加速：v̇ = power / max(v, V_FLOOR)。低速时推力大，速度越高越小，
## 所以速度按 √t 长。末速压在 max_speed（声速 ≈ 166，0.9c ≈ 150）——
## 波比人快，激波会在角色到达之前就把前面的门点亮。

## 恒定功率（速度²/秒）。45000 ≈ 0.25 秒到 150，加速段约走 25 px。
@export var power := 45000.0
## 末速上限
@export var max_speed := 150.0
## 没撞墙时最多跑多久
@export var dash_time := 0.6

var _player: Player
var _seated := false
var _dir := 1.0

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	var world := get_tree().get_first_node_in_group("echo_world")
	if world != null and world.has_method("entity_material"):
		_sprite.material = world.entity_material()

	# 声学体指着自己这块贴图（不能靠 .tscn 里的 NodePath，那个字段读出来是 null）
	($Body as AcousticBody).visual = _sprite

	($Area as Area2D).body_entered.connect(_on_entered)
	($Area as Area2D).body_exited.connect(_on_exited)


func _on_entered(body: Node2D) -> void:
	if body is Player:
		_player = body


func _on_exited(body: Node2D) -> void:
	if body != _player:
		return
	_stand()
	_player = null


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _player.is_dashing():
		return

	if not _seated:
		# 只有站在地上才能坐
		if _player.is_on_floor():
			_player.hint = "按 X 坐下"
			if Input.is_action_just_pressed("sit"):
				_seated = true
				_player.sit()
		else:
			_player.hint = ""
		return

	# 坐着：A/D 只改朝向
	_player.hint = "按 A/D 调整方向  按 X 发射"
	var ix := Input.get_axis("move_left", "move_right")
	if not is_zero_approx(ix):
		_dir = signf(ix)
	if Input.is_action_just_pressed("sit"):
		_seated = false
		_player.hint = ""
		_player.launch(_dir, power, max_speed, dash_time)


func _stand() -> void:
	if _player != null:
		if _seated:
			_player.stand()
		_player.hint = ""
	_seated = false
