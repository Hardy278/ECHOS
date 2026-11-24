class_name ItemInteractor
extends Node

## 玩家脚下的"最近可交互物"选择器。
##
## 不新增按键：X 仍然绑定 sit。
##   · 找到范围内最近的、背包收得下的 ItemEntity；
##   · 不画任何高亮——只把 target_changed 发给屏幕下方的提示 UI；
##   · 这时按 X，事件交给这个实体（拾取），并告诉 Player 这一帧的 X 已被消费；
##   · 没有目标时什么都不做，X 照旧落回 sit（发射器坐下/发射）。

signal target_changed(has_target: bool)

@export var radius := 30.0

var _player: Player
var _focus: ItemEntity


func _ready() -> void:
	_player = get_parent() as Player


func _physics_process(_delta: float) -> void:
	if _player == null:
		return

	if _player.is_seated() or _player.is_dashing():
		_set_focus(null)
		return

	var best: ItemEntity = null
	var best_d := radius * radius
	for n in get_tree().get_nodes_in_group("item_entities"):
		var e := n as ItemEntity
		if e == null or not is_instance_valid(e):
			continue
		if not e.can_pickup(_player):
			continue
		var d := _player.global_position.distance_squared_to(e.global_position)
		if d <= best_d:
			best_d = d
			best = e

	_set_focus(best)

	if _focus != null and Input.is_action_just_pressed("sit"):
		if _focus.try_pickup(_player):
			_player.mark_interaction_consumed()
			_set_focus(null)


func has_focus() -> bool:
	return _focus != null and is_instance_valid(_focus)


func _set_focus(e: ItemEntity) -> void:
	if _focus == e:
		return
	_focus = e
	if _player != null:
		_player.set_interaction_focus(_focus != null)
		# 靠近只出下方提示，不写角色 hint，也不高亮实体
		_player.hint = ""
	target_changed.emit(_focus != null)
