extends Node2D

## 主场景。回响场用 GPU 波动方程（wave_field.gd）。
## 射线法已从构建中移除（脚本仍在 scripts/ 下，未使用），F3 保留一个开关方便对照。
##
## 左键/Q 发声   A/D 移动   空格 跳   F1 射线确定性（对照用）   F2 显示几何   R 复位

const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const WAVE_SCRIPT := preload("res://scripts/wave_field.gd")

const SPAWN := Vector2(240, 238)
const SHOUT_CD := 2.0
const HEARTBEAT_HZ := 1.0
const HB_AMP := 0.045          # 心跳：极其微弱，只够亮出贴身的轮廓
const LAND_AMP := 0.05         # 落地基底 + 按冲击速度加成
const LAND_AMP_MAX := 0.20

var geom: LevelGeometry
var wave
var player: CharacterBody2D
var hud: Label

var _cd := 0.0
var _hb := HEARTBEAT_HZ
var _debug_geo := false


func _ready() -> void:
	_setup_input()
	geom = LevelGeometry.new()
	_build_colliders()
	_build_player()
	_build_camera()
	_build_wave()
	_build_hud()
	player.landed.connect(_on_landed)

	if OS.get_cmdline_args().has("--capture") or OS.get_cmdline_user_args().has("--capture"):
		_run_capture()
	if OS.get_cmdline_args().has("--selftest") or OS.get_cmdline_user_args().has("--selftest"):
		_run_selftest()


# ---------------------------------------------------------------- 装配

func _setup_input() -> void:
	_action("move_left", [KEY_A, KEY_LEFT])
	_action("move_right", [KEY_D, KEY_RIGHT])
	_action("jump", [KEY_SPACE, KEY_W, KEY_UP])
	_action("shout", [KEY_Q])
	_action("dbg", [KEY_F2])
	_action("reset", [KEY_R])
	_action("wave_down", [KEY_BRACKETLEFT])
	_action("wave_up", [KEY_BRACKETRIGHT])
	_action("edge_down", [KEY_COMMA])
	_action("edge_up", [KEY_PERIOD])
	_action("blur_down", [KEY_MINUS])
	_action("blur_up", [KEY_EQUAL])


func _action(n: String, keys: Array) -> void:
	if InputMap.has_action(n) and not InputMap.action_get_events(n).is_empty():
		return
	if not InputMap.has_action(n):
		InputMap.add_action(n)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(n, ev)


func _build_colliders() -> void:
	var body := StaticBody2D.new()
	body.name = "Solids"
	add_child(body)
	for r in geom.solids:
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = r.size
		cs.shape = shape
		cs.position = r.position + r.size * 0.5
		body.add_child(cs)


func _build_player() -> void:
	player = PLAYER_SCRIPT.new()
	player.position = SPAWN
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10, 16)
	cs.shape = shape
	player.add_child(cs)
	add_child(player)


func _build_camera() -> void:
	var cam := Camera2D.new()
	cam.position = Vector2(240, 135)
	cam.zoom = Vector2(2, 2)
	add_child(cam)
	cam.make_current()


func _build_wave() -> void:
	wave = WAVE_SCRIPT.new()
	wave.name = "WaveField"
	add_child(wave)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(8, 6)
	hud.add_theme_font_size_override("font_size", 11)
	hud.add_theme_color_override("font_color", Color(0.62, 0.80, 0.92, 0.9))
	layer.add_child(hud)


# ---------------------------------------------------------------- 循环

func _process(delta: float) -> void:
	if _cd > 0.0:
		_cd = maxf(0.0, _cd - delta)

	# 心跳：自己的声音，极其微弱，一直在响
	_hb -= delta
	if _hb <= 0.0:
		_hb += HEARTBEAT_HZ
		wave.emit_heartbeat(player.position, HB_AMP)

	# 听觉范围跟着角色走
	wave.set_listener(player.position)

	if Input.is_action_just_pressed("shout"):
		_shout()
	if Input.is_action_just_pressed("dbg"):
		_debug_geo = not _debug_geo
		queue_redraw()
	if Input.is_action_just_pressed("reset"):
		player.position = SPAWN
		player.velocity = Vector2.ZERO
		wave.clear()

	# 画面参数实时可调：写论文不如自己拧
	if Input.is_action_pressed("wave_down"):
		wave.adjust_view("bg_gain", -0.05)
	if Input.is_action_pressed("wave_up"):
		wave.adjust_view("bg_gain", 0.05)
	if Input.is_action_pressed("edge_down"):
		wave.adjust_view("edge_gain", -0.2)
	if Input.is_action_pressed("edge_up"):
		wave.adjust_view("edge_gain", 0.2)
	if Input.is_action_pressed("blur_down"):
		wave.adjust_view("bg_blur", -0.05)
	if Input.is_action_pressed("blur_up"):
		wave.adjust_view("bg_blur", 0.05)

	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_shout()


func _shout() -> void:
	if _cd > 0.0:
		return
	_cd = SHOUT_CD
	wave.ping(player.position)


## 落地也是一次发声：冲击越快越响，但上限远低于喊叫
func _on_landed(strength: float) -> void:
	wave.emit_landing(player.position, LAND_AMP + (LAND_AMP_MAX - LAND_AMP) * strength)


func _update_hud() -> void:
	var cd_txt := "可发声" if _cd <= 0.0 else "冷却 %.1fs" % _cd
	hud.text = "A/D 移动  空格 跳  左键/Q 发声  R 复位  F2 几何\n[ ] 行波 %.2f   , . 边缘 %.2f   - = 柔化 %.2f\n%s   子步 %d · stride %d · 波速 %.0f 单位/秒" % [
		wave.view_params["bg_gain"], wave.view_params["edge_gain"],
		wave.view_params["bg_blur"],
		cd_txt, wave.SUBSTEPS, wave.STRIDE, wave.wave_speed()]


func _draw() -> void:
	if not _debug_geo:
		return
	for i in geom.solids.size():
		var r: Rect2 = geom.solids[i]
		var abs_val: float = geom.solid_abs[i]
		var c := Color(0.18, 0.42, 0.26, 0.85) if abs_val < 0.5 else Color(0.55, 0.22, 0.22, 0.85)
		draw_rect(r, c, false, 0.5)


# ---------------------------------------------------------------- 截图 / 自检

func _run_capture() -> void:
	await get_tree().create_timer(0.6).timeout
	wave.ping(SPAWN)
	_cd = SHOUT_CD
	var t0 := Time.get_ticks_msec()

	await _at(t0, 400)
	await _grab("wave_01_0400")
	await _at(t0, 700)
	await _grab("wave_02_0700")
	await _at(t0, 1200)
	await _grab("wave_03_1200")
	await _at(t0, 2400)
	await _grab("wave_04_2400")

	# 验证：把角色挪到左边，亮区应该跟着人走（场的能量本身不动）
	player.position = Vector2(120, 238)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await _grab("wave_05_shift")
	get_tree().quit()


var _peaks := []


func _at(t0: int, ms: int) -> void:
	var remain := (t0 + ms) - Time.get_ticks_msec()
	if remain > 0:
		await get_tree().create_timer(remain / 1000.0).timeout


func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "res://.local/capture_%s.png" % tag
	var err := img.save_png(path)
	print("[capture] %s err=%d" % [path, err])


func _run_selftest() -> void:
	await get_tree().create_timer(0.4).timeout
	print("[自检] 落地: pos=(%.1f, %.1f)  贴地=%s" % [player.position.x, player.position.y, player.is_on_floor()])

	Input.action_press("move_right")
	await get_tree().create_timer(0.5).timeout
	Input.action_release("move_right")
	print("[自检] 右移 0.5s 后: pos=(%.1f, %.1f)" % [player.position.x, player.position.y])

	var y0 := player.position.y
	Input.action_press("jump")
	await get_tree().create_timer(0.1).timeout
	Input.action_release("jump")
	var apex := y0
	for i in 24:
		await get_tree().physics_frame
		apex = minf(apex, player.position.y)
	print("[自检] 跳跃顶点: 上升 %.1f px（规格 36）" % (y0 - apex))

	await get_tree().create_timer(0.9).timeout
	print("[自检] 落回: pos=(%.1f, %.1f)  贴地=%s" % [player.position.x, player.position.y, player.is_on_floor()])
	get_tree().quit()
