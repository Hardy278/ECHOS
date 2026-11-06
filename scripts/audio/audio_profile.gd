class_name AudioProfile
extends Resource

## 一份声音：素材 + 混音参数。**无状态**，放在 Ability 上，由 `Audio`（导演）消费。
##
## 三条约束都是这一路定下来的决定，别随手加回来：
##
## 1. **没有 chance / 随机**。运行时零随机：多给几条 stream，导演轮转，保证每条
##    变体都会被用到。想要"同一个物体每次不一样"，靠变体，不靠骰子。
##
## 2. **没有跟 strength / 声场绑定的音量**。`volume_db` 是唯一决定"本来多响"的数，
##    距离由引擎的 max_distance / attenuation 衰减。声场的 amp 已经被门的阈值绑死了
##    （0.28 / 0.8 / 0.15），再接到混音上，调画面就会悄悄改耳朵。
##
## 3. **没有 wet_send**。一个 AudioStreamPlayer2D 只能进一条总线，湿声要复制一条声道，
##    等房间混响真的要做的时候再说。

enum Mode {
	ONE_SHOT,   ## 事件触发，播一遍
	SUSTAINED,  ## 一直在响：占一条循环，直到 release（或持有者被释放）
}

## importance 达到这个数就是"关键音"：独占保留槽位，永不被抢。
const CRITICAL := 8

@export var mode := Mode.ONE_SHOT

## 多条 = 每次触发轮转到下一条（不是随机；保证每条都会被用到）。
## 留空 = 这份音频还没做，整条链路上静默，不报错。
@export var streams: Array[AudioStream] = []

@export_group("混音")
## 这个声音本来多响。混音只由它和距离决定。
@export var volume_db := 0.0
## 抢声道时的优先级：数字小的先被抢；>= CRITICAL 的永远不被抢。
@export_range(0, 10) var importance := 5
## 听多远（世界单位）。一屏对角线约 550。
@export var max_distance := 550.0
## 距离衰减的陡度（引擎的 attenuation，1 = 默认）。
@export var attenuation := 1.0
## 进哪条总线。Dry = 干声；Wet = 湿声（现在还没有东西往里送）。
@export var bus := &"Dry"

@export_group("重复")
## 同一个 key 两次触发之间至少隔多久（秒）。0 = 不限制。
@export var min_interval := 0.0


## 还没做素材 = 静默。导演看到它就直接 return，不借声道、不报警。
func is_silent() -> bool:
	return streams.is_empty()


## 给编辑器里看一眼用的摘要。
func describe() -> String:
	return "%s · %d 条素材 · %.1f dB · 重要度 %d" % [
			"持续" if mode == Mode.SUSTAINED else "一次性",
			streams.size(), volume_db, importance]
