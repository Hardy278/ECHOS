class_name WaveField
extends Node

## 一个声源的**场后端**接口。
##
## `EchoSource` 只认这个接口：它负责"什么时候发声、什么时候停、听者在哪"，
## 后端正负责"场存在哪、一步怎么算"。
##
## 现在有两份实现：
##   · ViewportWaveField —— 原来的 SubViewport ping-pong（一帧一步，可回退）
##   · ComputeWaveField  —— 主 RenderingDevice + Texture2DRD（一帧 N 步）
##
## 约定：
##   · `advance(n)` 推进 n 步；SubViewport 后端最多只能吃 1 步，
##     所以调用方要先问 `max_steps_per_frame()`。
##   · 清场/定场是**挂起状态**：`clear()` / `seed_slab()` 只记下意图，
##     由下一次 `advance()` 执行。`advance(0)` 也要把挂起的状态走完。
##   · `texture()` 是给 canvas 着色器采样的 Texture2D；`read_image()` 是给
##     CPU 采样（门、草、SoundSampler）的 Image。

var geo_tex: Texture2D
var alpha_tex: Texture2D
var acoustics := Vector2.ZERO
var edges := Vector4.ZERO

## 每个物体自己的"嗓子"和余晖，由 EchoSource 在 setup 前填。
## damp / env_decay 是"60 步/秒下的每步系数"；提高步率后后端要按 60/hz 换算，
## 否则声速调快会连带把余晖也调短。
var damp := 0.9955
var env_decay := 0.966
var emit_radius := 14.0
var step_hz := 60.0


## EchoSource 每次声速变化时告知实际步率；默认 60（旧后端的固定步率）。
func set_step_rate(hz: float) -> void:
	step_hz = maxf(hz, 1.0)


func setup(p_geo: Texture2D, p_alpha: Texture2D) -> void:
	geo_tex = p_geo if p_geo != null else blank_texture()
	alpha_tex = p_alpha if p_alpha != null else blank_texture()


## 房间声学（reverb, absorb）和开口（左, 右, 上, 下）
func set_room(p_acoustics: Vector2, p_edges: Vector4) -> void:
	acoustics = p_acoustics
	edges = p_edges


func inject(_pos: Vector2, _amp: float, _steps: int, _clear_before: bool) -> void:
	pass


func clear() -> void:
	pass


func advance(_steps: int) -> void:
	pass


## 没有活着的波时收掉渲染，别让后端空转
func stop() -> void:
	pass


## 还有挂起的清场/定场没走完？
func is_busy() -> bool:
	return false


func max_steps_per_frame() -> int:
	return 1


func texture() -> Texture2D:
	return null


func read_image() -> Image:
	var t := texture()
	return t.get_image() if t != null else null


## 切房时把"正在穿出房间"的那一薄片抄下来（Image，不是 Texture）。
## 子类只负责 `read_image()`；几何、越界检查都在这里，免得两份实现漂移。
func capture_slab(dir: Vector2i) -> Image:
	var img := read_image()
	if img == null or dir == Vector2i.ZERO:
		return null
	var rect := FieldSlab.rect(dir, img.get_width(), img.get_height())
	if rect.position.x < 0 or rect.position.y < 0:
		return null
	if rect.end.x > img.get_width() or rect.end.y > img.get_height():
		return null
	return img.get_region(rect)


func seed_slab(_img: Image, _dir: Vector2i) -> void:
	pass


static func blank_texture() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
