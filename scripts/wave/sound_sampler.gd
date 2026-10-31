extends Node

## 共享的声场采样服务（autoload：SoundSampler）。
##
## 把"从 GPU 读回声场"这件事**集中成每 N 个物理帧一次**。
##
## 为什么需要它：读场要走 get_image()（GPU→CPU 拷贝），很贵。以前只有声控门
## 在听，每扇门各自每 6 帧读一次还能接受；一旦有 N 株会动的草、N 个听者，
## 就变成 N 份读回。这里只读一份缓存，谁想听就查缓存——get_pixel 是免费的。
##
## 采的是**玩家自己那一路声场**（喊叫 / 落地 / 心跳 / 激波都在里面）。
## 钟和门的声音不在里面；要让别的声音也能推草，在这里加一个源即可。
##
## 世界坐标 = 场 texel 坐标（1 texel = 1 世界单位，房间原点就是场原点），
## 所以这里不做任何换算，直接靠坐标取像素。

## 多少物理帧读一次。包络半衰约 0.34s，10Hz 足够，也躲开读回的开销
const SAMPLE_EVERY := 6
## 算梯度时的取样间距（world = texel）
const GRAD_STEP := 2.0

var _img: Image
var _src: Node
var _tick := 0


func _physics_process(_delta: float) -> void:
	_tick += 1
	if _tick % maxi(SAMPLE_EVERY, 1) != 0:
		return
	_refresh()


func _refresh() -> void:
	if _src == null or not is_instance_valid(_src):
		_src = _find_player_source()
		if _src == null:
			return
	if not _src.has_method("field_texture"):
		return
	var tex: Texture2D = _src.call("field_texture")
	if tex == null:
		return
	_img = tex.get_image()


# ---------------------------------------------------------------- 查询

## 这一点此刻有多响（包络 B 通道，0..1）
func envelope(pos: Vector2) -> float:
	if _img == null:
		return 0.0
	var p := _clamp_px(pos)
	return _img.get_pixel(p.x, p.y).b


## 3×3 邻域的最大值：贴着实体边缘取样时不会正好落在节点上读到 0
func envelope_max(pos: Vector2) -> float:
	if _img == null:
		return 0.0
	var best := 0.0
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			best = maxf(best, envelope(pos + Vector2(dx, dy)))
	return best


## 包络的梯度：指着"变响"的方向
func gradient(pos: Vector2) -> Vector2:
	if _img == null:
		return Vector2.ZERO
	var l := envelope(pos - Vector2(GRAD_STEP, 0))
	var r := envelope(pos + Vector2(GRAD_STEP, 0))
	var u := envelope(pos - Vector2(0, GRAD_STEP))
	var d := envelope(pos + Vector2(0, GRAD_STEP))
	return Vector2(r - l, d - u) / (2.0 * GRAD_STEP)


## 声辐射压：F ∝ -∇(u²)，也就是**从响的地方被推向安静的地方**。
## 振幅的平方是天然的门槛——心跳那种微光推不动东西，喊叫和激波才推得动。
func radiation(pos: Vector2) -> Vector2:
	var e := envelope(pos)
	if e <= 0.0:
		return Vector2.ZERO
	return -gradient(pos) * e * e * 4.0


# ---------------------------------------------------------------- 内部

func _clamp_px(pos: Vector2) -> Vector2i:
	var w := _img.get_width()
	var h := _img.get_height()
	return Vector2i(
			clampi(int(pos.x), 0, w - 1),
			clampi(int(pos.y), 0, h - 1))


## 玩家自己那一路声源（Player/Echo）
func _find_player_source() -> Node:
	for s in get_tree().get_nodes_in_group("echo_sources"):
		var n: Node = (s as Node).get_parent()
		while n != null:
			if n.is_in_group("player"):
				return s
			n = n.get_parent()
	return null
