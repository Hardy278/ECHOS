extends SoundAbility

## 喊叫发声技能

## 对应 Input Map 中的动作.
@export var action := &"shout"


func _tick(_delta: float) -> float:
	return 1.0 if Input.is_action_just_pressed(action) else -1.0
