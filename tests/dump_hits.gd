extends SceneTree

## 命中纹理的逐像素体检：R=能量 G=到达时间 B=阶数。
## godot --headless --script res://tests/dump_hits.gd -- res://.local/hits_spawn.png


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := "res://.local/hits_spawn.png"
	if args.size() > 0:
		path = args[0]
	var img := Image.load_from_file(path)
	if img == null:
		print("无法读取: ", path)
		quit(1)
		return

	var w := img.get_width()
	var h := img.get_height()
	print("== %s  %dx%d ==" % [path, w, h])

	# 每个字符代表 CW x CH 个 texel，取最大值（细线不被平均掉）
	var cw := 4
	var ch := 5
	var ramp := " .:-=+*#%@"
	var lit := 0
	var total := 0
	var emax := 0.0
	var esum := 0.0
	var tmax := 0.0
	var terms := 0

	print("     " + "".join(PackedStringArray(_ruler(w, cw))))
	for cy in range(0, h, ch):
		var line := "%3d| " % cy
		for cx in range(0, w, cw):
			var m := 0.0
			var mm := 0.0
			var mt := 0.0
			for y in range(cy, mini(cy + ch, h)):
				for x in range(cx, mini(cx + cw, w)):
					var c := img.get_pixel(x, y)
					var v := c.r
					if v > m:
						m = v
						mt = c.g
					if c.b > 0.9:
						pass
			if m > 0.0:
				lit += 1
				esum += m
			emax = maxf(emax, m)
			tmax = maxf(tmax, mt)
			total += 1
			line += ramp[clampi(int(m * 9.99), 0, 9)]
		print(line)

	# 终止点（B 通道 >= 0.9 表示 255/255）
	for y in h:
		for x in w:
			if img.get_pixel(x, y).b > 0.9:
				terms += 1

	print("格子 %d，有命中 %d（%.1f%%），峰值能量 %.3f，平均能量 %.3f，终止点 texel %d" % [
		total, lit, 100.0 * lit / maxf(1.0, total), emax, esum / maxf(1.0, lit), terms])

	# 行扫描：给定 y，每 8 px 打印能量
	if args.size() > 1:
		for i in range(1, args.size()):
			var yy := int(args[i])
			var row := ""
			for x in range(0, w, 8):
				var best := 0.0
				for y in range(maxi(0, yy - 1), mini(h, yy + 2)):
					best = maxf(best, img.get_pixel(x, y).r)
				row += "%4d" % int(best * 99.0)
			print("y=%d: %s" % [yy, row])
	quit(0)


func _ruler(w: int, cw: int) -> Array:
	var s := ""
	for x in range(0, w, cw):
		if x % 80 == 0:
			s += "|"
		elif x % 20 == 0:
			s += "'"
		else:
			s += " "
	return s.split("")
