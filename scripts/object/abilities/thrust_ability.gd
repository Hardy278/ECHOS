extends SoundAbility

## 激波推进的轰鸣。**不进声场**——推进时的波动一直是 `player.gd` 每帧注入的
## （那是激波的形状，一帧都不能少），音频只吃"开始 / 结束"两个事件。
##
## 这两件事本来就该分开：声场的注入是 60 次/秒的物理，音频是一次事件。
## 把注入搬进能力会改掉激波的形状；把音频挂到注入上就是每秒 60 发的机枪声。
##
## 从 SoundAbility 派生只是为了白拿 `audio` / `_origin()` / `play_audio()`：
## 它的 `_tick()` 用基类的 -1，所以永远不会往场里注入任何东西。

var _player: Node


func _ready() -> void:
	_player = _find_player()
	if _player == null:
		push_warning("Thrust: 没找到角色，激波不会出声")
		return
	for sig in [&"dash_started", &"dash_ended"]:
		if not _player.has_signal(sig):
			push_warning("Thrust: 角色没有 %s 信号" % sig)
			return
	_player.connect(&"dash_started", _on_started)
	_player.connect(&"dash_ended", _on_ended)


func _on_started() -> void:
	play_audio()


func _on_ended() -> void:
	stop_audio()


func _find_player() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.is_in_group("player"):
			return n
		n = n.get_parent()
	return null
