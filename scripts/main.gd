extends Node2D

## 主场景：装配 + 流程。
## Player（player.tscn 的实例）、相机、HUD 都是 main.tscn 里的节点；
## 输入动作定义在 project.godot 的 Input Map 里，这里不再用代码注册。
## 几何唯一来源是 TileMapLayer 的碰撞多边形；回响场走 GPU 波动方程
## （wave_field.gd 把图块碰撞烘成场纹理，再用 wave_step_fb / wave_view 两个 shader）。
##
## 左键/Q 发声   A/D 移动   空格 跳   F2 显示几何   R 复位

const WAVE_SCRIPT := preload("res://scripts/wave_field.gd")

const SHOUT_CD := 2.0
const HEARTBEAT_HZ := 1.0
const HB_AMP := 0.045          # 心跳：极其微弱，只够亮出贴身的轮廓
const LAND_AMP := 0.05         # 落地基底 + 按冲击速度加成
const LAND_AMP_MAX := 0.20

@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Camera
@onready var hud: Label = $Hud/Label
@onready var foreground: TileMapLayer = $ForeGround
@onready var midground: TileMapLayer = get_node_or_null("MidGround") as TileMapLayer
@onready var background: TileMapLayer = $Background

var wave
var spawn: Vector2              # 出生点 = main.tscn 里 Player 节点的摆放位置

var _cd := 0.0
var _hb := HEARTBEAT_HZ
var _debug_geo := false


func _ready() -> void:
	spawn = player.position
	camera.make_current()

	# 2D 按树序绘制：后景必须在后面，否则会盖住前景
	background.z_index = -2
	if midground != null:
		midground.z_index = -1

	_build_wave()
	player.landed.connect(_on_landed)

	if OS.get_cmdline_args().has("--capture") or OS.get_cmdline_user_args().has("--capture"):
		_run_capture()
	if OS.get_cmdline_args().has("--selftest") or OS.get_cmdline_user_args().has("--selftest"):
		_run_selftest()


# ---------------------------------------------------------------- 装配

func _build_wave() -> void:
	wave = WAVE_SCRIPT.new()
	wave.name = "WaveField"
	wave.tilemap = foreground
	wave.tilemap_mid = midground
	wave.tilemap_bg = background
	add_child(wave)


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
		player.position = spawn
		player.velocity = Vector2.ZERO
		wave.clear()

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
	hud.text = "A/D 移动  空格 跳  左键/Q 发声  R 复位  F2 几何\n%s\n%s" % [
		cd_txt, wave.debug_line()]


func _draw() -> void:
	if not _debug_geo or wave == null:
		return
	var tex: Texture2D = wave.debug_texture()
	if tex != null:
		# R=实体 G=单向木台 B=无碰撞装饰：直接看烘出来的分类图
		draw_texture_rect(tex, Rect2(0, 0, 480, 270), false, Color(1, 1, 1, 0.5))


# ---------------------------------------------------------------- 截图 / 自检

func _run_capture() -> void:
	await get_tree().create_timer(0.6).timeout
	wave.ping(spawn)
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

	# 输入已搬到 project.godot：真发一个 F2 按键事件，验证 InputMap 映射（而不是只查动作名）
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F2
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().process_frame   # process_frame 在 _process 之前发出
	await get_tree().process_frame   # 再等一帧，让 _process 真正处理这次按下
	print("[自检] F2 → dbg: 动作按下=%s  几何开关=%s" % [
		str(Input.is_action_pressed("dbg")), str(_debug_geo)])
	var key_up := InputEventKey.new()
	key_up.physical_keycode = KEY_F2
	key_up.pressed = false
	Input.parse_input_event(key_up)

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
	print("[自检] 跳跃顶点: 上升 %.1f px（规格 36）" % [y0 - apex])

	await get_tree().create_timer(0.9).timeout
	print("[自检] 落回: pos=(%.1f, %.1f)  贴地=%s" % [player.position.x, player.position.y, player.is_on_floor()])
	get_tree().quit()
