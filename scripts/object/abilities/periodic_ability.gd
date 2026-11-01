extends SoundAbility

## 定时发声技能.

## 发声间隔.
@export var period := 1.0:
	set(v):
		period = v
		if _timer != null:
			_timer.wait_time = maxf(v, 0.01)
## 是否一起来就发第一声。
## 关着（默认）的话，第一声要等满一个 period；
## 开着的话在 _ready 之后的第一帧就发——对"房间一进来就该亮着"的声源有用。
@export var start_immediately := false

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

	if start_immediately:
		_want = true


func _on_timeout() -> void:
	_want = true


func _tick(_delta: float) -> float:
	if not _want:
		return -1.0
	_want = false
	return 1.0
