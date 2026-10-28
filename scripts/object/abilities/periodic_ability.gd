extends SoundAbility

## 定时发声技能.

## 发声间隔.
@export var period := 1.0:
	set(v):
		period = v
		if _timer != null:
			_timer.wait_time = maxf(v, 0.01)

var _timer: Timer
var _want := false


func _ready() -> void:
	_timer = Timer.new()
	_timer.name = "Cadence"
	_timer.wait_time = maxf(period, 0.01)
	_timer.one_shot = false
	_timer.autostart = true
	_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	_timer.timeout.connect(_on_timeout)
	add_child(_timer)


func _on_timeout() -> void:
	_want = true


func _tick(_delta: float) -> float:
	if not _want:
		return -1.0
	_want = false
	return 1.0
