extends SoundAbility

## 落地发声技能.

@export var amp_min := 0.05
@export var signal_name := &"landed"

var _pending := -1.0
var _connected := false


func _ready() -> void:
	# 能力挂在普通 Node 容器下时，父节点不是角色本身，要往上找带 landed 信号的祖先
	var src := _ancestor_with_signal(signal_name)
	if src != null:
		src.connect(signal_name, _on_signed)
		_connected = true


func _on_signed(strength: float) -> void:
	_pending = clampf(strength, 0.0, 1.0)


func _tick(_delta: float) -> float:
	if _pending < 0.0:
		return -1.0
	var s := _pending
	_pending = -1.0
	return s


func _amp_for(strength: float) -> float:
	return amp_min + (amp - amp_min) * strength


func is_wired() -> bool:
	return _connected
