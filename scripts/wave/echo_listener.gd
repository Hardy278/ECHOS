class_name EchoListener
extends Node2D

## 一个"会听的生物"的听觉**数据接口**。
##
## 它只回答数据问题：我现在听得见谁、多清楚、多远、在哪、多久之前。
## 不创建 SubViewport / Texture2DRD / ShaderMaterial，不写 light_tex；
## 渲染和 AI 都是它的消费者。
##
## 三层：
##   · 声波衰减 —— EchoSource 的场，一个参考系；已经含在 sample_at() 里
##   · 距离衰减 —— z = x * exp(-d / L)，L = distance_scale
##   · 统一亮度曲线 —— y = z + a z(1-z)(c-z)，弱光提亮/强光压暗是同一曲线的两端
##
## 低于 min_audible 时输出 0；有效距离 L * ln(x / min_audible)。

signal heard(source: EchoSource, strength: float)
signal lost(source: EchoSource)

@export var enabled := true
## AI 不需要每帧：每 poll_interval 秒更新一次缓存并发边沿信号
@export var poll_interval := 0.1
## 只听这些组（挂在声源所属生物上）；空 = 全部
@export var hearing_filter: Array[StringName] = []
## 忽略自己身上的声源（自己的心跳 / 脚步 / 喊叫）
@export var ignore_self := true
## 丢失后还保留"最后听到"多久（给 AI 去查看）
@export var memory_sec := 3.0

@export_group("Hearing")
## 距离衰减尺度 L：z = x * exp(-d / L)
@export var distance_scale := 100.0
## 最低可听亮度 τ：z <= τ 时为 0
@export var min_audible := 0.001
## 统一亮度曲线 g(z) = z + a z (1-z) (c-z)
@export var curve_a := 1.0
@export var curve_c := 0.1

## 一条"当前听得见"的数据
class Hearing:
	var source: EchoSource
	var strength := 0.0
	var distance := 0.0
	var position := Vector2.ZERO
	var direction := Vector2.ZERO
	var first_heard := 0.0
	var last_heard := 0.0

var _current: Dictionary = {}      # EchoSource -> Hearing
var _last_known: Dictionary = {}   # EchoSource -> Hearing（丢失后保留 memory_sec）
var _acc := 0.0


# ---------------------------------------------------------------- 生命周期

func _enter_tree() -> void:
	add_to_group("echo_listeners")


func _ready() -> void:
	# 场景里的 EchoWorld 可能还没 ready；推迟一帧再注册
	_setup.call_deferred()


func _exit_tree() -> void:
	if not is_inside_tree():
		return
	var w := _world()
	if w != null and w.has_method("unregister_listener"):
		w.unregister_listener(self)


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_acc += delta
	if _acc < poll_interval:
		return
	_acc = 0.0
	_poll()


func _setup() -> void:
	var w := _world()
	if w != null and w.has_method("register_listener"):
		w.register_listener(self)


func _world() -> Node:
	return get_tree().get_first_node_in_group("echo_world") if is_inside_tree() else null


# ---------------------------------------------------------------- 给 AI / 渲染查

## 纯公式：不读 GPU、不建纹理。渲染消费者也可以每帧调它。
func perceive(source: EchoSource) -> float:
	if source == null or not is_instance_valid(source):
		return 0.0

	var d := global_position.distance_to(source.global_position)
	var x := source.sample_at(global_position) * source.gain
	var z := x * exp(-d / maxf(distance_scale, 0.001))
	if z <= min_audible:
		return 0.0
	var y := z + curve_a * z * (1.0 - z) * (curve_c - z)
	return clampf(y, 0.0, 1.0)


## 当前听得见的，按 strength 降序。
func audible_sources() -> Array[Hearing]:
	var out: Array[Hearing] = []
	for h in _current.values():
		out.append(h)
	out.sort_custom(func(a, b): return a.strength > b.strength)
	return out


## 最清楚的那一个；没有就 null。
func loudest() -> Hearing:
	var all := audible_sources()
	return all[0] if not all.is_empty() else null


func strength_of(source: EchoSource) -> float:
	var h: Hearing = _current.get(source)
	return h.strength if h != null else 0.0


func can_hear(source: EchoSource) -> bool:
	return strength_of(source) > 0.0


## 当前或最近（memory_sec 内）听到的；从没听到就是 null。
func last_heard(source: EchoSource) -> Hearing:
	var h: Hearing = _current.get(source)
	if h != null:
		return h
	h = _last_known.get(source)
	return h


func time_since_heard(source: EchoSource) -> float:
	var h := last_heard(source)
	if h == null:
		return INF
	return Time.get_ticks_msec() / 1000.0 - h.last_heard


# ---------------------------------------------------------------- 内部

func _poll() -> void:
	var now := Time.get_ticks_msec() / 1000.0

	# 声源随房间释放时不会通知 listener：这里先清掉死对象
	for s in _current.keys():
		if not is_instance_valid(s):
			_current.erase(s)
	for s in _last_known.keys():
		if not is_instance_valid(s):
			_last_known.erase(s)

	var seen := {}

	for n in get_tree().get_nodes_in_group("echo_sources"):
		var s := n as EchoSource
		if s == null or not is_instance_valid(s) or not _accepts(s):
			continue
		var v := perceive(s)
		if v <= 0.0:
			continue

		var h: Hearing = _current.get(s)
		if h == null:
			# 短暂丢失后又听见：复用旧记录，保住 first_heard
			h = _last_known.get(s)
			if h != null:
				_last_known.erase(s)
			else:
				h = Hearing.new()
				h.source = s
				h.first_heard = now
			heard.emit(s, v)

		h.strength = v
		h.distance = global_position.distance_to(s.global_position)
		h.position = s.global_position
		h.direction = (s.global_position - global_position).normalized()
		h.last_heard = now
		seen[s] = h

	for s in _current.keys():
		if not seen.has(s):
			var old: Hearing = _current[s]
			_last_known[s] = old
			lost.emit(s)
	_current = seen

	# 过期的最远记忆清掉
	for s in _last_known.keys():
		var h: Hearing = _last_known[s]
		if now - h.last_heard > memory_sec:
			_last_known.erase(s)


func _accepts(s: EchoSource) -> bool:
	if ignore_self and _same_body(s):
		return false
	if hearing_filter.is_empty():
		return true
	var body := s.get_parent()
	for g in hearing_filter:
		if body != null and body.is_in_group(g):
			return true
	return false


## 声源是不是长在这个听者自己的身上（自己的心跳、脚步、喊叫）。
func _same_body(s: EchoSource) -> bool:
	var body := get_parent()
	if body == null:
		return false
	return s.get_parent() == body or body.is_ancestor_of(s)
