extends SceneTree

## 单条射线探针：打印一次完整弹射链路，定位"为什么这面墙没亮"。
## godot --headless --script res://tests/ray_probe.gd -- 240 238 160 40


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var ox := 240.0
	var oy := 238.0
	var tx := 160.0
	var ty := 40.0
	if a.size() >= 4:
		ox = float(a[0]); oy = float(a[1]); tx = float(a[2]); ty = float(a[3])

	var geom := LevelGeometry.new()
	var o := Vector2(ox, oy)
	var tgt := Vector2(tx, ty)
	var d := (tgt - o).normalized()

	print("== 探针 (%s) → (%s)，期望命中 %s ==" % [str(o), str(tgt), str(tgt)])
	print("该点是否在某固体内部: ", _inside(geom, tgt))

	var px := o.x
	var py := o.y
	var dx := d.x
	var dy := d.y
	var energy := 1.0
	var path := 0.0
	for b in 5:
		var best_t := INF
		var best_i := -1
		for s in geom.seg_count:
			var sidx := s / 4
			var r: Rect2 = geom.solids[sidx]
			var o4 := s * 4
			var ax := geom.seg_data[o4]
			var ay := geom.seg_data[o4 + 1]
			var sx := geom.seg_data[o4 + 2]
			var sy := geom.seg_data[o4 + 3]
			var den := dx * sy - dy * sx
			if absf(den) < 1e-9:
				continue
			var qx := ax - px
			var qy := ay - py
			var tt := (qx * sy - qy * sx) / den
			if tt <= 1e-4 or tt >= best_t:
				continue
			var u := (qx * dy - qy * dx) / den
			if u < 0.0 or u > 1.0:
				continue
			best_t = tt
			best_i = s
		if best_i < 0:
			print("  第 %d 段：什么都没打到（飞出地图）" % b)
			break
		var hx := px + dx * best_t
		var hy := py + dy * best_t
		path += best_t
		energy *= 1.0 / (1.0 + path / EchoSim.DIST_K)
		var sidx := best_i / 4
		var r: Rect2 = geom.solids[sidx]
		var abs_val := geom.solid_abs[sidx]
		energy *= (1.0 - abs_val)
		print("  第 %d 段：命中 (%.1f, %.1f)  seg#%d  solid#%d %s  路径 %.1f  能量 %.3f%s" % [
			b, hx, hy, best_i, sidx, str(r), path, energy,
			"  [吸音，终止]" if abs_val >= 0.5 else ""])
		if abs_val >= 0.5:
			break
		var nx := geom.seg_norm[best_i * 2]
		var ny := geom.seg_norm[best_i * 2 + 1]
		if nx * dx + ny * dy > 0.0:
			nx = -nx
			ny = -ny
		var k := 2.0 * (dx * nx + dy * ny)
		dx -= k * nx
		dy -= k * ny
		px = hx + nx * 0.05
		py = hy + ny * 0.05
		energy *= EchoSim.BOUNCE_DECAY
	quit(0)


func _inside(geom: LevelGeometry, p: Vector2) -> bool:
	for r in geom.solids:
		if r.has_point(p):
			return true
	return false
