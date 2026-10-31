@tool
class_name HangingGrass
extends Node2D

## 一**丛**从天花板垂下来的草：横向占一个 tile（16 世界单位），里面 strands 根。
##
## 之所以是 @tool：形状全在 Inspector 里调，不预览等于瞎调。
## 编辑器里用的是固定的亮色（没有合成光可读），并且改参数会立刻重建；
## 运行时才挂 EchoWorld 的实体材质、查玩家、跑物理。
##
## 为什么是一丛而不是一根：单根像绳子，三根并排才像"一群草"。
## 丛宽按 tile 算，所以它和关卡网格对齐——摆起来是一格一格的。
##
## **它自己不会动**。只有两个外力：
##   1. 声场 —— 声辐射压 F ∝ -∇(u²)，从响的地方被推向安静的地方
##   2. 撞击 —— 玩家 / 激波从身上穿过去，按速度把它撩开
## 一丛安静的草是死的；它动起来，就说明那边有很响的东西。
##
## **没有随机**：每根的形状由导出参数给定，同一丛摆十次是十丛一样的。
## 本节点的位置 = 天花板锚点（每根链的第 0 个点都钉在这里）。

@export_group("形状")
## 这一丛里几根
@export var strands := 3:
	set(v): strands = v; _on_shape_changed()
## 横向铺开的半宽（世界单位）。6 → 三根落在 -6 / 0 / +6，占 12，正好塞进 16 的 tile
@export var spread := 6.0:
	set(v): spread = v; _on_shape_changed()
## 段数（点数 = 段数 + 1）。多几节弯才顺，6 节画不出 ()()
@export var segments := 12:
	set(v): segments = v; _on_shape_changed()
## 每段长度
@export var seg_length := 4.5:
	set(v): seg_length = v; _on_shape_changed()
## 每根的长度倍率（不够 strands 个就循环取）
@export var length_scale: Array[float] = [0.86, 1.0, 0.9]:
	set(v): length_scale = v; _on_shape_changed()
## 每根相对重力方向的额外倾角（度）。默认全 0：**挂下来的静止姿态就是竖直向下**。
## 横向的差异来自锚点位置（spread），不来自角度——角度一给就会像扇子一样张开，
## 那不是"下垂"，那是"放射"。
@export var lean_deg: Array[float] = [0.0, 0.0, 0.0]:
	set(v): lean_deg = v; _on_shape_changed()
## 粗细：1 个 tile 像素 = 2 世界单位
@export var thickness := 2.0:
	set(v): thickness = v; _on_shape_changed()

@export_group("弯曲")
## 静止形状左右扭的幅度（世界单位）。1 个 tile 像素 = 2，所以 1~2 就够
@export var wave_amp := 1.5:
	set(v): wave_amp = v; _on_shape_changed()
## 几节走完一个完整正弦。越大波长越长；
## 一根上的波数 = segments / wave_segs（12 节 + 4 → 3 个波）
@export var wave_segs := 4.0:
	set(v): wave_segs = v; _on_shape_changed()
## 不规则度：0 = 一根完全规则的正弦（一排一模一样的括号，很假），
## 1 = 明显不齐。用的是**确定性哈希**，同一丛每次跑都长一样，没有 randf。
@export_range(0.0, 1.0) var jitter := 0.45:
	set(v): jitter = v; _on_shape_changed()

@export_group("被压平")
## 角色压上来时，S 形被拉平的程度：1 = 压到完全直，0 = 不压
@export_range(0.0, 1.0) var flatten := 1.0
## 压平的内半径（世界单位）：这个距离以内完全直
@export var flatten_inner := 10.0
## 压平的外半径：这个距离以外恢复原样，中间平滑过渡
@export var flatten_outer := 26.0

@export_group("动态")
## 抗弯刚度：每个点每帧往"纯竖直"拉多少。
## 它现在**不再负责保住弯曲**（弯曲是渲染阶段加的，重力碰不到），
## 所以就调小——草几乎不回弹，就是一根垂着的东西。
## 觉得像纸条，多半是这个值太大：纸条有回弹力，垂下来的草没有。
@export var stiffness := 0.012
## 速度保留率。越大荡得越久（0.985 ≈ 2.3 秒衰减一半），太小就一碰就停
@export var damping := 0.985
## 重力加速度（单位/秒²）。全局唯一一份，见 GameConst——
## 之前这里写的是 0.12 单位/帧²，折算下来只有玩家的一半。
@export var gravity := GameConst.GRAVITY
## 段长约束的迭代次数。**这个才是"不可伸长"的旋钮**：
## 每多迭代一次，剩下的残余拉伸就再被削掉一半以上。
@export var iterations := 10
## 根部刚度倍率：锚点处的回正力是尖端的这么多倍（1 = 均匀）。
## 真实的垂悬植物是"上面硬、下面软"——尖端最活，根部几乎不动。
@export var root_stiffness := 4.0

@export_group("外力")
## 质量。物理上质量不改变摆动周期，只改变"被推一下能飞多远"：
## 冲量和声场推力都除以它，所以调大就是更沉的草。
@export var mass := 3.0
## 声场推力。振幅是平方的，所以心跳推不动、喊叫和激波才推得动。
## 质量也除它，所以默认值按 mass=3 放大过——改 mass 记得一起调。
@export var sound_gain := 750.0
## 玩家把它撞开的半径
@export var push_radius := 6.0

## 一个 tile 像素 = 2 世界单位
const PIXEL := 2.0
const GameConst := preload("res://scripts/world/constants.gd")

## 本体亮度：画进 tile_light 的 COLOR 亮度。它 = "这块东西自身的图案亮度"。
## 图块的图案是暗的石头（lum≈0.3），所以 tile_light 里 art 只有 0.5 左右，
## 暖暖的合成光才有机会从底下透上来。画纯白会让 art 顶到 1，
## 草就变成这个着色器能画出的最亮冷银——那正是它之前看着"没被声音照亮"的原因。
@export var body_art := 0.30

var _pts: Array = []      ## 每根一根 PackedVector2Array
var _prev: Array = []
var _rest: Array = []
var _rest_len: Array = [] ## 每根每节的静止段长（正弦弯曲之后各节并不等长）
var _fruits: Array[Fruit] = []
var _player: Node2D


func _ready() -> void:
	# 锚点也在格上，否则整丛会系统性地偏半个像素
	global_position = _snap(global_position)
	_rebuild()

	# 编辑器里到此为止：没有合成光、没有玩家、不跑物理
	if Engine.is_editor_hint():
		queue_redraw()
		return

	_player = get_tree().get_first_node_in_group("player") as Node2D
	for c in get_children():
		if c is Fruit:
			_fruits.append(c as Fruit)

	var world := get_tree().get_first_node_in_group("echo_world")
	if world != null and world.has_method("entity_material"):
		# 和 tile、实体走完全同一条路：同一份材质、同一张合成光。
		material = world.entity_material()


## 编辑器里改一个形状参数就重建一次——**不逐帧跑**，只在参数真的变了的时候。
## 运行时这个回调直接返回。
func _on_shape_changed() -> void:
	if not Engine.is_editor_hint():
		return
	_rebuild()
	queue_redraw()


func _rebuild() -> void:
	var n := segments + 1
	var count := maxi(strands, 1)
	_pts.clear()
	_prev.clear()
	_rest.clear()
	_rest_len.clear()
	for s in count:
		var t := float(s) / float(maxi(count - 1, 1))
		var offset := lerpf(-spread, spread, t) if count > 1 else 0.0
		var lean := float(lean_deg[s % lean_deg.size()]) if not lean_deg.is_empty() else 0.0
		var scale := float(length_scale[s % length_scale.size()]) if not length_scale.is_empty() else 1.0
		# 角度取负：DOWN.rotated(+θ) 的 x 分量是 -sinθ，正角度是往左的。
		var dir := Vector2.DOWN.rotated(deg_to_rad(-lean))
		var seg := seg_length * scale
		var pts := PackedVector2Array()
		var prev := PackedVector2Array()
		var rest := PackedVector2Array()
		pts.resize(n)
		prev.resize(n)
		rest.resize(n)
		for i in n:
			# 静止形状 = 纯竖直（重力方向）。**弯曲不在这里**——
			# 它是渲染/几何阶段沿法线加的静态偏移，重力碰不到（见 _shaped）。
			var p := Vector2(offset, 0.0) + dir * seg * float(i)
			pts[i] = p
			prev[i] = p
			rest[i] = p

		# 约束按静止时的实际段长来。现在是直的，所以各节等长；
		# 保留这个数组是因为以后形状真变长了也不用改约束那边。
		var lens := PackedFloat32Array()
		lens.resize(n - 1)
		for i in n - 1:
			lens[i] = rest[i + 1].distance_to(rest[i])
		_rest_len.append(lens)

		_pts.append(pts)
		_prev.append(prev)
		_rest.append(rest)


# ---------------------------------------------------------------- 帧

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	for s in _pts.size():
		_integrate(s, delta)
		for k in iterations:
			_solve(s)
	_hit_player(delta)
	_drive_fruits()
	queue_redraw()


func _integrate(s: int, dt: float) -> void:
	var pts: PackedVector2Array = _pts[s]
	var prev: PackedVector2Array = _prev[s]
	var rest: PackedVector2Array = _rest[s]
	var anchor: Vector2 = rest[0]
	var n := pts.size()
	if n < 2:
		return

	# 重力是加速度（单位/秒²），换成每帧位移要乘 dt²
	var g := Vector2.DOWN * gravity * dt * dt

	for i in range(1, n):
		var v := (pts[i] - prev[i]) * damping
		prev[i] = pts[i]
		pts[i] += v + g
		# 抗弯：往静止形状拉。这是位置弹簧，不是硬约束——
		# 它够弱，所以扰动会顺着链往下传、整根会甩；够强，波浪形状才不被重力压直。
		#
		# 刚度沿长度递减：根部（u=0）是 root_stiffness 倍，尖端（u=1）是 1 倍。
		# 所以整根是"从天花板上硬接下来、末梢最活"，而不是一根均匀的软绳。
		var u := float(i) / float(n - 1)
		var k := clampf(stiffness * lerpf(root_stiffness, 1.0, u), 0.0, 1.0)
		pts[i] = pts[i].lerp(rest[i], k)

	# 锚点钉死（每根自己的 x 偏移）
	pts[0] = anchor

	# 声场只推末梢：中段交给约束解算，整根自己会摆起来
	if sound_gain != 0.0:
		var force: Vector2 = SoundSampler.radiation(to_global(pts[n - 1]))
		pts[n - 1] += force * sound_gain / maxf(mass, 0.001)

	_pts[s] = pts
	_prev[s] = prev


## 段长约束（PBD）。锚点不动，其余两边各让一半。
## 每节的目标长度取自静止形状——波浪弯了之后各节并不等长。
func _solve(s: int) -> void:
	var pts: PackedVector2Array = _pts[s]
	var lens: PackedFloat32Array = _rest_len[s]
	var n := pts.size()
	for i in n - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		var dist := d.length()
		if dist < 0.0001:
			continue
		var corr := d * ((dist - lens[i]) / dist)
		if i == 0:
			pts[i + 1] = b - corr
		else:
			pts[i] = a + corr * 0.5
			pts[i + 1] = b - corr * 0.5
	_pts[s] = pts


## 玩家穿过时把草顶开。
##
## 用**角色的碰撞盒**而不是一个圆：落在盒子里的点沿**水平**方向推到身体两侧，
## 于是玩家走过去时草是被劈开的（留出一条缝），而不是被身子从中间穿过去。
## 只推 x、不推 y——草是被"撩开"，不是被"顶起"或"压下"。
##
## 速度必须乘 delta：velocity 是**每秒**，Verlet 的位移是**每帧**。
## 不乘的话，走路 90 单位/秒会被当成 90 单位/帧——放大 60 倍，一碰就飞。
##
## 分速度按质量：完全非弹性碰撞里草拿到的份额是 m_player / (m_player + m_grass)。
## 玩家 1、草 3 → 0.25。所以 mass 调大就是更沉的草，不用另设系数。
func _hit_player(delta: float) -> void:
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p == null:
		return
	var c := p.global_position
	var vel := Vector2.ZERO
	var half := Vector2(5.0, 8.0)          # 角色碰撞盒的一半（10×16）
	if p is CharacterBody2D:
		vel = (p as CharacterBody2D).velocity
		var cs := (p as CharacterBody2D).get_node_or_null("CollisionShape2D") as CollisionShape2D
		if cs != null and cs.shape is RectangleShape2D:
			half = (cs.shape as RectangleShape2D).size * 0.5

	var m_p := GameConst.PLAYER_MASS
	var share := m_p / (m_p + maxf(mass, 0.001))
	var transfer := vel * delta * share

	# 盒子在 x 方向多留一圈余量，草才会被让到身体两侧而不是贴着身子
	var reach := half + Vector2(push_radius, 0.0)
	var top := c.y - half.y
	var bottom := c.y + half.y

	for s in _pts.size():
		var pts: PackedVector2Array = _pts[s]
		var prev: PackedVector2Array = _prev[s]
		for i in range(1, pts.size()):
			var w := to_global(pts[i])
			if w.y < top or w.y > bottom:
				continue
			var dx := w.x - c.x
			if absf(dx) >= reach.x:
				continue
			var side := 1.0 if dx >= 0.0 else -1.0
			var target := c.x + side * reach.x
			pts[i].x += target - w.x      # 只改 x
			prev[i].x = pts[i].x - transfer.x
		_pts[s] = pts
		_prev[s] = prev


func _drive_fruits() -> void:
	for f in _fruits:
		if not is_instance_valid(f) or f.is_picked():
			continue
		var s := clampi(f.strand, 0, _pts.size() - 1)
		var pts: PackedVector2Array = _pts[s]
		var idx: int = f.at_index if f.at_index >= 0 else pts.size() - 1
		f.mount_at(to_global(pts[clampi(idx, 0, pts.size() - 1)]))


# ---------------------------------------------------------------- 几何

## 给 AcousticStroke 用：第 s 根的世界坐标折线（和画面上完全同一条曲线）。
## 草是 _draw 出来的，拿不出贴图，所以它进世界几何的方式就是这条线——
## 有了它，表面带会自动长在草身上，声音撞上来时它会像地形一样亮。
func acoustic_points(s: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if s < 0 or s >= _pts.size():
		return out
	var smooth := smooth_points(s)
	out.resize(smooth.size())
	for i in smooth.size():
		out[i] = to_global(smooth[i])
	return out


## 把物理链变成"草的样子"：沿每一点的法线，加一段**静态的**正弦偏移。
##
## 这一步发生在物理之后，所以**弯曲与重力无关**：
## 重力只决定这根草整体垂成什么弧线，弯曲是长在它身上的一层图案。
## 之前把弯曲写进静止形状，于是重力会和弹簧一起把它压扁——那看起来就像弹簧。
func _shaped(s: int) -> PackedVector2Array:
	var pts: PackedVector2Array = _pts[s]
	var n := pts.size()
	var out := PackedVector2Array()
	out.resize(n)

	# 每根自己的相位和幅度——否则三根是一模一样的三个括号
	var ph := _hash01(s * 17 + 5) * TAU
	var am := 1.0 + (_hash01(s * 31 + 11) - 0.5) * 2.0 * jitter

	for i in n:
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n - 1)]
		var tan := b - a
		var nrm := Vector2.RIGHT
		if tan.length_squared() > 0.000001:
			nrm = Vector2(-tan.y, tan.x).normalized()

		var u := float(i) / maxf(wave_segs, 0.01)
		# 主波
		var w := sin(u * TAU + ph) * am
		# 一个更短、更弱的次波：打破"每段都一样"的重复感
		w += sin(u * TAU * 2.37 + ph * 1.7) * 0.30 * am
		# 每个点再抖一点（确定性），让曲线不是数学曲线
		w += (_hash01(s * 977 + i * 131 + 7) - 0.5) * 2.0 * jitter * 0.55

		# 被角色压住的地方拉平：离角色越近，弯曲越小，走开就自己长回来
		if flatten > 0.0 and _player != null:
			var d := to_global(pts[i]).distance_to(_player.global_position)
			var k := clampf((d - flatten_inner) / maxf(flatten_outer - flatten_inner, 0.001), 0.0, 1.0)
			w *= 1.0 - flatten * (1.0 - k)

		out[i] = pts[i] + nrm * (w * wave_amp)
	return out


## 整数哈希 → [0, 1)。确定性：同样的输入永远同样的输出。
func _hash01(k: int) -> float:
	var h := (k * 374761393 + 668265263) & 0x7FFFFFFF
	h = (h ^ (h >> 13)) * 1274126177
	h = h & 0x7FFFFFFF
	return float(h) / 2147483647.0


## 把折线（12 节）采样成一条密曲线，采样间距半个 tile 像素。
##
## 物理只需要 12 个点（够稳、够便宜），但**画出来和进几何的必须更密**：
## 否则一根弯的草是 4.5 单位一段的折线，看起来是一节一节的。
## 用 Catmull-Rom 穿过去，形状不变、只是变顺。
func smooth_points(s: int) -> PackedVector2Array:
	var pts := _shaped(s)
	var n := pts.size()
	if n < 3:
		return pts

	var out := PackedVector2Array()
	var step := PIXEL * 0.5
	for i in n - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, n - 1)]
		var cnt := maxi(1, int(ceil(p1.distance_to(p2) / step)))
		for k in cnt:
			out.append(_catmull(p0, p1, p2, p3, float(k) / float(cnt)))
	out.append(pts[n - 1])
	return out


func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
			+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


# ---------------------------------------------------------------- 像素渲染

## 物理跑浮点，画之前量化到整数 tile 像素。
## 不用 Line2D：它会产生亚像素宽度的四边形和斜接，一定糊。
func _draw() -> void:
	# 保险：编辑器里 _ready 有时还没跑（比如脚本刚从非 tool 改成 tool），
	# 这里补一次，保证第一帧就有东西可画。
	if _pts.is_empty():
		_rebuild()
	# 编辑器里额外画一个锚点标记：看得见它，说明 tool 脚本是活的
	if Engine.is_editor_hint():
		draw_rect(Rect2(Vector2(-3, -3), Vector2(6, 3)), Color(1.0, 0.35, 0.35))
	for s in _pts.size():
		var last := Vector2(1e9, 1e9)
		for p in smooth_points(s):
			# 采样比像素格更密，量化后会重复落在同一格：跳过重复的，省一半方块
			var q := _snap(p)
			if q == last:
				continue
			last = q
			_dot(q)


func _dot(p: Vector2) -> void:
	# 编辑器里没有合成光，用固定的亮色，否则预览是一片黑
	var c := Color(0.75, 1.0, 0.80) if Engine.is_editor_hint() \
			else Color(body_art, body_art, body_art)
	draw_rect(Rect2(p, Vector2(thickness, thickness)), c)


func _snap(p: Vector2) -> Vector2:
	return Vector2(roundf(p.x / PIXEL) * PIXEL, roundf(p.y / PIXEL) * PIXEL)
