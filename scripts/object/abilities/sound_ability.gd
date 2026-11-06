class_name SoundAbility
extends Node

## 发声能力的基类。
##
## 发到哪里由目标决定，沿父链找"自己就是声源"的祖先：
##   - 钟：Bell/EchoSource/Tick → 找到 EchoSource
##   - 角色：Player/Echo/Shout → 找到 EchoSource
##
## 一次 `fire()` = 往声场里注入 + 往耳朵里播。两件事同一个入口，
## 所以不会出现"看得见听不见"的半条声音。

@export var amp := 0.5      ## 声音的强弱
@export var steps := 1      ## 声音持续几个 step（物理模拟步数）
@export var cooldown := 0.0 ## 声音的冷却时间

@export_group("音频")
## 这条能力发什么声。留空 = 没做素材，整条链路静默（不报错、不占声道）。
@export var audio: AudioProfile
## 一次性声音的去重键。同一把门用同一个 key 才能吃到 profile.min_interval。
@export var audio_key := ""

var _cd := 0.0
var _target: Node


func _process(delta: float) -> void:
	if _cd > 0.0:
		_cd = maxf(0.0, _cd - delta)
	var strength := _tick(delta)
	if strength >= 0.0:
		fire(strength)


## 子类实现：返回 0..1 的强度表示这一帧要发；返回 -1 表示不发
func _tick(_delta: float) -> float:
	return -1.0


## 决定强度如何映射成振幅
func _amp_for(_strength: float) -> float:
	return amp


## 手动触发一次（截图 / 自检用）
func trigger() -> bool:
	return fire(1.0)


## 触发一次
func fire(strength: float) -> bool:
	if _cd > 0.0:
		return false
	var t := _get_target()
	if t == null or not t.has_method("emit_sound"):
		return false
	_cd = cooldown
	t.emit_sound(_origin(), _amp_for(strength), steps)
	play_audio()          # ← 同一个入口：声场和耳朵一起响
	return true


func cooldown_left() -> float:
	return _cd


# ---------------------------------------------------------------- 音频

func _origin() -> Vector2:
	# 能力是 Node，声源是 Node2D，所以沿父链找最近的 Node2D 当发声点
	var n: Node = get_parent()
	while n != null:
		if n is Node2D:
			return (n as Node2D).global_position
		n = n.get_parent()
	return Vector2.ZERO


## 按 profile 的模式播一声。ONE_SHOT 播一遍，SUSTAINED 续期一条循环。
func play_audio() -> void:
	if audio == null or audio.is_silent():
		return
	if audio.mode == AudioProfile.Mode.SUSTAINED:
		Audio.sustain(audio, _origin(), self)
	else:
		Audio.play(audio, _origin(), audio_key)


## 收掉这条能力持有的循环（激波推进结束之类）。
func stop_audio() -> void:
	if audio != null:
		Audio.release(audio)


func _get_target() -> Node:
	if _target != null and is_instance_valid(_target):
		return _target
	# 沿父链找"自己就是声源"的祖先（Player、钟的 EchoSource）
	var n: Node = get_parent()
	while n != null:
		if n.has_method("emit_sound"):
			_target = n
			return _target
		n = n.get_parent()
	_target = null
	return _target


## 沿父链找带某个信号的祖先（能力可能挂在普通 Node 容器下）
func _ancestor_with_signal(sig: StringName) -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.has_signal(sig):
			return n
		n = n.get_parent()
	return null
