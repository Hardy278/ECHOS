extends Node

## 音频导演（autoload：`Audio`）：全局声道池。
##
## 分工：能力说"我发什么、在哪儿"（AudioProfile + 世界坐标），
## 导演说"给不给你喇叭"。它只干四件事：建池、分配/回收、按 importance 抢占、
## 维持 sustain 循环。
##
## **不碰声场、不读回、不做随机。** 声场那边的 amp 只服务画面和门的阈值。
##
## 声道池挂在 root 而不是房间下：RoomSystem 切房会 queue_free 掉旧房间，
## 声音如果挂在房间里，一声关门会被砍在中间。挂在 root 上，尾巴自然响完。

## 池子大小。一屏一间房，十几条同时响已经很密了。
const POOL := 12
## 普通声音用不满整池：最后这几条留给 importance >= AudioProfile.CRITICAL。
const RESERVE := 2

## 总开关。**运行时**在远程检查器里关掉它，整条音频链路立刻变空操作，
## 用来现场判断"某个掉帧到底是不是音频的锅"。
@export var enabled := true

var _world: Node2D
var _idle: Array[AudioStreamPlayer2D] = []
## 正在响的一次性声道：[{p, profile, imp}]
var _live: Array = []
## sustain 循环：profile → {p, owner}
var _loops: Dictionary = {}
## profile → 变体游标（轮转）
var _rot: Dictionary = {}
## 去重键 → 上次触发的 msec
var _last: Dictionary = {}
## 听者位置：角色的耳朵，不是相机
var _listener := Vector2(240, 135)


func _ready() -> void:
	_build_buses()
	_world = Node2D.new()
	_world.name = "Voices"
	add_child(_world)
	for i in POOL:
		var p := _make_player()
		_world.add_child(p)
		_idle.append(p)


func _make_player() -> AudioStreamPlayer2D:
	var p := AudioStreamPlayer2D.new()
	p.bus = &"Dry"
	p.panning_strength = 1.0
	return p


## Dry / Wet 两条总线，Master 上挂限幅。
## 用代码建而不是 .tres：改起来看得见，也不会因为手写序列化格式出错。
func _build_buses() -> void:
	for bus_name in ["Dry", "Wet"]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")

	# 十几个声源 + 一声喊，不限幅就削顶。
	# 用 ClassDB 而不是直接 new：4.3 之后叫 AudioEffectHardLimiter，
	# 老名字在不同版本上不一定还在，缺了也不该整个 autoload 挂掉。
	var master := AudioServer.get_bus_index(&"Master")
	if master != -1 and AudioServer.get_bus_effect_count(master) == 0:
		for cls in ["AudioEffectHardLimiter", "AudioEffectLimiter"]:
			if not ClassDB.class_exists(cls):
				continue
			AudioServer.add_bus_effect(master, ClassDB.instantiate(cls))
			break


func _process(_delta: float) -> void:
	# finished 信号在换流 / stop() 时不一定发，统一每帧扫 playing 更省心。
	for i in range(_live.size() - 1, -1, -1):
		var e: Dictionary = _live[i]
		var p: AudioStreamPlayer2D = e.p
		if not is_instance_valid(p) or not p.playing:
			_live.remove_at(i)
			if is_instance_valid(p) and not _idle.has(p):
				_idle.append(p)

	# 持有者没了（切房会把整间房的能力一起释放）→ 循环跟着走。
	for prof in _loops.keys():
		var e: Dictionary = _loops[prof]
		if not is_instance_valid(e.owner):
			release(prof)

	var pl := get_tree().get_first_node_in_group("player") as Node2D
	if pl != null:
		_listener = pl.global_position


# ---------------------------------------------------------------- 对外

## 一次性声音。`key` 非空时按 profile.min_interval 去重（同一把门的两次触发）。
func play(profile: AudioProfile, at: Vector2, key := "") -> void:
	if not enabled:
		return
	if profile == null or profile.is_silent():
		return                    # 没做素材 = 静默，不借声道也不报警
	if not key.is_empty() and _too_soon(profile, key):
		return
	var stream := _next_stream(profile)
	if stream == null:
		return
	var p := _take_slot(profile.importance)
	if p == null:
		return                    # 池子满了且抢不动 = 这条声音丢掉
	p.stream = stream
	p.global_position = at
	p.max_distance = profile.max_distance
	p.attenuation = profile.attenuation
	p.bus = profile.bus
	p.volume_db = profile.volume_db
	p.play()
	_live.append({"p": p, "profile": profile, "imp": profile.importance})
	if not key.is_empty():
		_last[key] = Time.get_ticks_msec()


## 持续声音：**同一个 profile 只占一条循环**（7 个果实 = 1 条）。
## 位置只接受离听者更近的那个贡献者——7 个来源每帧轮流写位置会抖。
##
## 循环是**素材自己的属性**（WAV 的 loop_mode / OGG 的 loop），播放器没有 loop 开关：
## 所以 SUSTAINED 的 profile 里必须放已经开了循环的 stream，否则它播一遍就停。
func sustain(profile: AudioProfile, at: Vector2, owner: Node) -> void:
	if not enabled:
		return
	if profile == null or profile.is_silent() or owner == null:
		return
	var e = _loops.get(profile)
	if e != null:
		var cur: AudioStreamPlayer2D = e.p
		if is_instance_valid(cur) and cur.playing:
			e.owner = owner                     # 续期：还有人在响
			if at.distance_squared_to(_listener) < cur.global_position.distance_squared_to(_listener):
				cur.global_position = at
			return
	var stream := _next_stream(profile)
	if stream == null:
		return
	var p := _take_slot(AudioProfile.CRITICAL)   # 循环不被抢
	if p == null:
		return
	p.stream = stream
	p.global_position = at
	p.max_distance = profile.max_distance
	p.attenuation = profile.attenuation
	p.bus = profile.bus
	p.volume_db = profile.volume_db
	p.play()
	_loops[profile] = {"p": p, "owner": owner}


## 收掉一条循环（激波推进结束、持有者要走）。
func release(profile: AudioProfile) -> void:
	if profile == null:
		return
	var e = _loops.get(profile)
	if e == null:
		return
	_loops.erase(profile)
	var p: AudioStreamPlayer2D = e.p
	if not is_instance_valid(p):
		return
	p.stop()
	if not _idle.has(p):
		_idle.append(p)


## 切房 / 重开时清干净（现在没人调，留给以后"整房静音"用）。
func stop_all() -> void:
	for i in range(_live.size() - 1, -1, -1):
		var p: AudioStreamPlayer2D = _live[i].p
		if is_instance_valid(p):
			p.stop()
			if not _idle.has(p):
				_idle.append(p)
	_live.clear()
	for prof in _loops.keys().duplicate():
		release(prof)


func stats() -> String:
	return "声道 %d/%d · 循环 %d" % [_live.size(), POOL, _loops.size()]


func listener_position() -> Vector2:
	return _listener


## 池子里还有几条一次性声音在响（探针 / HUD 用）
func live_count() -> int:
	return _live.size()


func idle_count() -> int:
	return _idle.size()


func loop_count() -> int:
	return _loops.size()


# ---------------------------------------------------------------- 内部

## 拿一条声道。池子空了就抢 importance 最低的那条；关键音和循环都不会被抢。
func _take_slot(imp: int) -> AudioStreamPlayer2D:
	var reserved := 0 if imp >= AudioProfile.CRITICAL else RESERVE
	if _idle.size() <= reserved:
		var v := _weakest(imp)
		if v < 0:
			return null
		var p: AudioStreamPlayer2D = _live[v].p
		_live.remove_at(v)
		p.stop()
		return p
	return _idle.pop_back()


## 池里比 imp 更不重要的那条的下标；没有就 -1。
func _weakest(imp: int) -> int:
	var worst := -1
	var low := imp
	for i in _live.size():
		var e: Dictionary = _live[i]
		if e.imp >= AudioProfile.CRITICAL:
			continue                      # 关键音永远不被抢
		if e.imp < low:
			low = e.imp
			worst = i
	return worst


func _too_soon(profile: AudioProfile, key: String) -> bool:
	if profile.min_interval <= 0.0 or not _last.has(key):
		return false
	var elapsed := Time.get_ticks_msec() - int(_last[key])
	return elapsed < int(profile.min_interval * 1000.0)


## 变体轮转：不是随机，所以每条变体都一定会被用到，也一定可复现。
func _next_stream(profile: AudioProfile) -> AudioStream:
	var n := profile.streams.size()
	if n <= 0:
		return null
	var i := int(_rot.get(profile, 0)) % n
	_rot[profile] = (i + 1) % n
	return profile.streams[i]
