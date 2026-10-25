extends SceneTree

## 无渲染验证：跑射线模拟，打印统计 + 确定性自检。
## godot --headless --path . --script res://tests/sim_check.gd


func _initialize() -> void:
	var geom := LevelGeometry.new()
	print("== 几何 ==")
	print("固体 %d 个，线段 %d 条" % [geom.solids.size(), geom.seg_count])
	var felt := 0
	for a in geom.solid_abs:
		if a >= 0.5:
			felt += 1
	print("吸音面 %d 个（吸收率 >= 0.5）" % felt)

	print("\n== 波速 ==")
	print("场穿越 %.2fs / 对角线 %.1f → 波速 %.1f 单位/秒" % [
		EchoSim.TRAVERSE, EchoSim.FIELD_DIAG, EchoSim.WAVE_SPEED])

	# 三个典型发声点：出生点、钟旁边、台 C 上
	var origins := {
		"出生点 (240,238)": Vector2(240, 238),
		"钟旁 (100,238)": Vector2(100, 238),
		"台C上 (340,146)": Vector2(340, 146),
	}

	print("\n== 射线统计 ==")
	for label in origins:
		var o: Vector2 = origins[label]
		var t0 := Time.get_ticks_usec()
		var res := EchoSim.cast(o, geom)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var hits: PackedFloat32Array = res["hits"]
		print("%s  %s  [%.1f ms]" % [label, EchoSim.summarize(hits), ms])

	print("\n== 确定性 ==")
	var ref_res := EchoSim.cast(Vector2(240, 238), geom)
	var ref_hits: PackedFloat32Array = ref_res["hits"]
	var ref := ref_hits.to_byte_array()
	var ref_md5 := _md5(ref)
	print("基准 md5 = ", ref_md5)
	var ok := true
	for i in 3:
		var again: PackedFloat32Array = EchoSim.cast(Vector2(240, 238), geom)["hits"]
		if _md5(again.to_byte_array()) != ref_md5:
			ok = false
			print("  第 %d 次不一致" % (i + 1))
	# 换一个新建的几何实例（重建线段）也应完全一致
	var geom2 := LevelGeometry.new()
	var other: PackedFloat32Array = EchoSim.cast(Vector2(240, 238), geom2)["hits"]
	if _md5(other.to_byte_array()) != ref_md5:
		ok = false
		print("  新实例几何不一致")
	print("重复 3 次 + 重建几何 → %s" % ("全部一致 ✓" if ok else "不一致 ✗"))

	# 波前能不能覆盖全场：统计最大到达时间
	var hs: PackedFloat32Array = ref_res["hits"]
	var cnt := hs.size() / EchoSim.HIT_STRIDE
	var max_t := 0.0
	for i in cnt:
		max_t = maxf(max_t, hs[i * EchoSim.HIT_STRIDE + 5])
	print("\n== 场窗口 ==")
	print("最大到达时间 %.3fs（残影半衰 2.5s，波前窗口 0.12s）" % max_t)

	quit(0)


func _md5(bytes: PackedByteArray) -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_MD5)
	c.update(bytes)
	return c.finish().hex_encode()
