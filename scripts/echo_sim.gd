class_name EchoSim
extends RefCounted

## 射线声学模拟核心。
##
## 确定性（对应策划案 §3.8）：
##   - 扇面角度 = i * TAU / n，固定公式，无随机抖动
##   - 全流程无 randf()/randi()
##   - 纯函数：同样的 (origin, geom, 参数) 永远给同样的字节序列
##
## 返回 { hits, rings }：
##   hits  每个命中 stride 8，顺序 = 射线顺序，用于统计/哈希
##         [x, y, nx, ny, energy, t_arrive, bounce, terminated]
##   rings 按反弹阶数分组，第 b 圈 stride 5：
##         [x, y, energy, t_arrive, terminated]，无命中处为 INF
##   把同一圈相邻射线的落点连成线段，就能得到与角度分辨率无关的连续表面——
##   否则远处落点间距 > 1 texel，画出来是一串珠子。

const RAYS := 1024
const MAX_REFLECT := 3            # 最多 3 次反弹 → 最多 4 次命中
const BOUNCE_DECAY := 0.9
const DIST_K := 160.0             # 距离衰减 E/(1+d/K)，反线性（不用平方反比）
const DEFAULT_DIST_K := 160.0
## 注：策划案 v0.4 写的是 30。但本项目 1 场单位 = 1 texel、房间宽 480，
## K=30 时远端墙面只剩 0.13 能量，等于"看不见"。按 480 宽重标定到 160：
## 贴身 8 → 0.95，中场 150 → 0.52，远端 300 → 0.35，既保留远近差别又能读。
const FIELD_DIAG := 550.3         # 480x270 对角线
const TRAVERSE := 0.7             # 场穿越时间（秒）
const WAVE_SPEED := FIELD_DIAG / TRAVERSE   # ≈786 场单位/秒
const ABSORB_TERMINATE := 0.5     # 吸收率高于此值 → 终止，不再反弹
const HIT_STRIDE := 8
const RING_STRIDE := 6         # [x, y, energy, t_arrive, terminated, seg_index]
const MIN_ENERGY := 0.002
const EPS := 1e-4
const NORMAL_EPS := 0.05


static func cast(origin: Vector2, geom: LevelGeometry,
		n_rays: int = RAYS, max_reflect: int = MAX_REFLECT,
		dist_k: float = DEFAULT_DIST_K) -> Dictionary:
	var out := PackedFloat32Array()
	var rings: Array[PackedFloat32Array] = []
	for b in max_reflect + 1:
		var ring := PackedFloat32Array()
		ring.resize(n_rays * RING_STRIDE)
		ring.fill(INF)
		rings.append(ring)

	var sd := geom.seg_data
	var nm := geom.seg_norm
	var ab := geom.seg_abs
	var nseg := geom.seg_count
	var step := TAU / float(n_rays)

	for i in n_rays:
		var ang := float(i) * step
		var dx := cos(ang)
		var dy := sin(ang)
		var px := origin.x
		var py := origin.y
		var energy := 1.0
		var path := 0.0
		var b := 0

		while b <= max_reflect:
			# ---- 求交：全部线段取最近命中 ----
			var best_t := INF
			var best_i := -1
			for s in nseg:
				var o := s * 4
				var ax := sd[o]
				var ay := sd[o + 1]
				var sx := sd[o + 2]
				var sy := sd[o + 3]
				var den := dx * sy - dy * sx
				if absf(den) < 1e-9:
					continue
				var qx := ax - px
				var qy := ay - py
				var t := (qx * sy - qy * sx) / den
				if t <= EPS or t >= best_t:
					continue
				var u := (qx * dy - qy * dx) / den
				if u < 0.0 or u > 1.0:
					continue
				best_t = t
				best_i = s

			if best_i < 0:
				break   # 什么都没打到：开阔空间，连终止点都没有

			var hx := px + dx * best_t
			var hy := py + dy * best_t
			path += best_t

			var seg_absorb := ab[best_i]
			energy *= 1.0 / (1.0 + path / dist_k)   # 距离衰减（累计路径）
			energy *= (1.0 - seg_absorb)

			var nx := nm[best_i * 2]
			var ny := nm[best_i * 2 + 1]
			if nx * dx + ny * dy > 0.0:   # 法线翻向入射侧
				nx = -nx
				ny = -ny

			var terminated := 1.0 if seg_absorb >= ABSORB_TERMINATE else 0.0

			out.append(hx)
			out.append(hy)
			out.append(nx)
			out.append(ny)
			out.append(energy)
			out.append(path / WAVE_SPEED)
			out.append(float(b))
			out.append(terminated)

			var ri := i * RING_STRIDE
			rings[b][ri] = hx
			rings[b][ri + 1] = hy
			rings[b][ri + 2] = energy
			rings[b][ri + 3] = path / WAVE_SPEED
			rings[b][ri + 4] = terminated
			rings[b][ri + 5] = float(best_i)   # 命中哪条线段：只有同一条的两个命中才连线

			if terminated > 0.0:
				break   # 打上去就没了，不产生后续波前
			if b >= max_reflect:
				break

			# ---- 反射：d' = d - 2(d·n)n ----
			var k := 2.0 * (dx * nx + dy * ny)
			dx -= k * nx
			dy -= k * ny
			px = hx + nx * NORMAL_EPS
			py = hy + ny * NORMAL_EPS
			energy *= BOUNCE_DECAY
			if energy < MIN_ENERGY:
				break
			b += 1

	return {"hits": out, "rings": rings}


## 诊断用：把命中序列的摘要拼成字符串
static func summarize(hits: PackedFloat32Array) -> String:
	var n := hits.size() / HIT_STRIDE
	var by_bounce := [0, 0, 0, 0]
	var terms := 0
	var max_t := 0.0
	var max_e := 0.0
	for i in n:
		var o := i * HIT_STRIDE
		var bi := int(hits[o + 6])
		if bi >= 0 and bi < 4:
			by_bounce[bi] += 1
		if hits[o + 7] > 0.5:
			terms += 1
		max_t = maxf(max_t, hits[o + 5])
		max_e = maxf(max_e, hits[o + 4])
	return "hits=%d  一/二/三/四阶=%s  终止点=%d  t_max=%.3fs  e_max=%.3f" % [
		n, str(by_bounce), terms, max_t, max_e]
