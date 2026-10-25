extends SceneTree

## 把截图降采样成 ASCII 强度图，用于量化验证场亮度和几何位置。
## godot --headless --script res://tests/dump_png.gd -- res://.local/capture_02_field.png


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := "res://.local/capture_02_field.png"
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

	# 1440x810 窗口对应 480x270 场：先把 HUD 顶部切掉（约 60px）
	var top := 60
	var cw := 96
	var ch := 46
	var ramp := " .:-=+*#%@"

	var max_v := 0.0
	var sum_v := 0.0
	var cnt_v := 0
	for cy in ch:
		var line := ""
		var y0 := top + int(cy * (h - top) / ch)
		var y1 := top + int((cy + 1) * (h - top) / ch)
		for cx in cw:
			var x0 := int(cx * w / cw)
			var x1 := int((cx + 1) * w / cw)
			var s := 0.0
			var n := 0
			for y in range(y0, y1, 2):
				for x in range(x0, x1, 2):
					var c := img.get_pixel(x, y)
					var v: float = maxf(c.r, maxf(c.g, c.b))
					s += v
					n += 1
			var avg := 0.0 if n == 0 else s / n
			max_v = maxf(max_v, avg)
			sum_v += avg
			cnt_v += 1
			line += ramp[clampi(int(avg * 9.99), 0, 9)]
		print(line)

	print("平均亮度 %.4f  峰值格平均 %.4f" % [sum_v / maxf(1.0, cnt_v), max_v])
	quit(0)
