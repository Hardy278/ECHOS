class_name SoundDoor
extends DoorBase

## 声控门：不订阅信道，只听**玩家**的声音。
##
## 门外 4 px 有四个感知点（左右两面 × 上下两格），读玩家声场的包络（B 通道）取最大值。
## 这就是"它感知到的强度"：只表达响度，不表达"哪条信道响过"。
##
## 为什么读 B 不读 R：R 是振荡的，同一点每秒过零几十次，拿它比阈值会抖；
## B 本来就是 max(|u|, 上一刻 B × env_decay)（半衰约 0.34 s），是现成的峰值保持器。
##
## 为什么不读合成光：那一层已经被听者闸门、gain、表面带高光乘过了，
## 是"玩家看得见多少"，不是"门这儿有多响"。
##
## 为什么感知点在体外 4 px：门是 transmit = 0.9 的半透体，内部每步都会把场乘一次 0.9，
## 贴着面外取，拿到的才是没被门自己衰减过的原始数据。
##
## 强度显示在门板左右两边那 1 像素上：门板砍掉左右各 1 像素，那两列就是两条
## 垂直音条，从下往上填。**满格就开门。** 音条本身没有颜色，交给光照显形。

## 感知到的强度超过它就开门，同时音条正好填满。
## 实测（空场、无遮挡、玩家喊 amp = 0.3，取传播后的峰值）：20 px 处 ≈ 0.30，
## 29 px 处 ≈ 0.18。所以 0.15 大约等于"站到 33 px 以内喊一嗓"。
## 注意声音要**传过来**：注入的高斯只有 14 px 粗，29 px 外的峰值是在约 0.4 s 后到的。
@export var threshold := 0.15
## 多少物理帧采一次：B 的半衰 0.34 s，10 Hz 足够，也躲开频繁读回的开销
@export var sample_every := 6

var _tick := 0
var _bars: Array[Sprite2D] = []
var _bar_bodies: Array[AcousticBody] = []
var _bar_w := 2.0
var _bar_h_full := 32.0
var _bar_bottom := 24.0
var _bar_now := 0.0
var _bar_target := 0.0


func _ready() -> void:
	super._ready()
	_build_bars()
	restore_open_state()


func _physics_process(delta: float) -> void:
	if _opened:
		return

	# 音条限速逼近目标：涨得快但看得见（约 0.25 s 扫满），落得慢一点，像电平表。
	# 采样只有 10 Hz，不限速的话条会一格一格地跳。
	var rate := _bar_h_full * (4.0 if _bar_target >= _bar_now else 1.2)
	_bar_now = move_toward(_bar_now, _bar_target, rate * delta)
	_set_bar(_bar_now)

	# 满格就开门：等条真的扫到顶再开，玩家看得见那一下满格
	if _bar_now >= _bar_h_full:
		_apply_open(true)
		return

	_tick += 1
	if _tick % maxi(sample_every, 1) != 0:
		return

	var v := _sensed()
	# 线性：条长直接跟感知到的强度成正比，满格 = threshold。
	_bar_target = _bar_h_full * clampf(v / maxf(threshold, 0.0001), 0.0, 1.0)


func _apply_open(ring: bool) -> void:
	for b in _bars:
		b.visible = false
	for b in _bar_bodies:
		b.queue_free()          # 门开了就没人再听，柱子的声学形状也一起撤掉
	_bar_bodies.clear()
	super._apply_open(ring)


## 两条音条：门板砍掉左右各 1 像素之后空出来的那两列，纯色，靠光照显形。
func _build_bars() -> void:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)

	var mat: Material = null
	var world := get_tree().get_first_node_in_group("echo_world")
	if world != null and world.has_method("entity_material"):
		mat = world.entity_material()

	# 全部从门板自己的尺寸推出来，不写坐标表
	var half := _panel.region_rect.size * _panel.scale * 0.5
	_bar_w = _panel.scale.x
	_bar_h_full = half.y * 2.0
	_bar_bottom = _panel.position.y + half.y

	for x in [_panel.position.x - half.x - _bar_w, _panel.position.x + half.x]:
		var sp := Sprite2D.new()
		sp.name = "Bar"
		sp.texture = tex
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp.centered = false                    # 从节点位置往下画
		sp.position = Vector2(x, _bar_bottom)
		sp.scale = Vector2(_bar_w, 0.0)
		sp.material = mat
		sp.visible = false
		add_child(sp)
		_bars.append(sp)

		# 音条本身也是几何体，写进世界几何的是 (吸声 0, 折射 1, 透声 0.9, 覆盖)
		#   · 吸声 0：tile_light 才肯画它。墙格的吸声若是 1，条会被整块乘没，
		#     这正是"条在涨但画面上什么都没有"的原因。
		#   · 覆盖 1：表面带会在条边上出高光，声音撞上来时它能亮出一条边。
		#   · 高度跟条一起长，所以它也是一根能被声波反射的柱子。
		var body := AcousticBody.new()
		body.name = "BarBody"
		body.visual = sp
		body.transmit = 0.9
		add_child(body)
		_bar_bodies.append(body)


## h 是世界像素高度，从门板底边往上长
func _set_bar(h: float) -> void:
	for b in _bars:
		b.visible = h > 0.01
		b.scale = Vector2(_bar_w, h)
		b.position.y = _bar_bottom - h


## 门外 4 px 的四个点：左右两面 × 上下两格。
## ring_side 本来就是"门心到面外空气"的距离，和开门那两声用的是同一个数。
func _sense_points() -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for sp in [_top, _panel]:
		var y: float = (sp as Node2D).position.y
		pts.append(to_global(Vector2(-ring_side, y)))
		pts.append(to_global(Vector2(ring_side, y)))
	return pts


## 场里 B 通道在这些点上的最大值（取 3×3 邻域，免得正好落在驻波节点上读到 0）。
## 读回由 SoundSampler 统一做，这里只查缓存——门和草共用同一份采样。
func _sensed() -> float:
	var best := 0.0
	for p in _sense_points():
		best = maxf(best, SoundSampler.envelope_max(p))
	return best
