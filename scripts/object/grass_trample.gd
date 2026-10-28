extends Node2D

## 草地被踩的动画。挂在主角下面即可，不需要主场景知道这件事。
##
## 四个图块是草被压弯的四个阶段（编号 1..4）：
##   1=(4,0)  2=(5,0)  3=(0,1)  4=(1,1)
## 主角踩上草格时，那一格按手写序列换帧：1234343344333444，最后停在最弯的 4。
##
## 注意：TileSet 自带的"动画 tile"是全局同帧（所有格子一起动），
## 这里要的是**每格独立**播放，所以只能由脚本逐格 set_cell。

const FRAMES: Array[Vector2i] = [
	Vector2i(4, 0),   # 1
	Vector2i(5, 0),   # 2
	Vector2i(0, 1),   # 3
	Vector2i(1, 1),   # 4
]
## 1234343344333444（0 基）
const SEQUENCE := [0, 1, 2, 3, 2, 3, 2, 2, 3, 3, 2, 2, 2, 3, 3, 3, 0]
const STEP_TIME := 0.1
const FOOT_OFFSET := Vector2(0, 8)   # 从主角中心到脚底


var _player: Node2D
var _layers: Array = []
var _playing := {}        # "layerId:cell" → {layer, cell, step, t}
var _last_cell := {}      # layerId → 上一次所在的格（进入新格才触发）
var _dirty := false


func _ready() -> void:
	_player = get_parent() as Node2D
	# 自己找出场景里所有的 TileMapLayer，不依赖外部装配
	var root := get_tree().current_scene
	if root == null:
		root = get_tree().root
	for n in root.find_children("*", "TileMapLayer", true, false):
		_layers.append(n)


func _process(delta: float) -> void:
	if _player == null:
		return
	_trigger_under_player()
	_advance(delta)
	# 换过帧就通知世界几何重画：不依赖外部装配，没有几何节点也不报错
	if _dirty:
		_dirty = false
		get_tree().call_group(&"wave_geometry", &"request_sync")


func _trigger_under_player() -> void:
	var feet := _player.global_position + FOOT_OFFSET
	for layer in _layers:
		var tml := layer as TileMapLayer
		if tml == null:
			continue
		var id := tml.get_instance_id()
		var cell := tml.local_to_map(tml.to_local(feet))
		if _last_cell.get(id) == cell:
			continue                      # 还是同一格，不重复触发
		_last_cell[id] = cell

		if not FRAMES.has(tml.get_cell_atlas_coords(cell)):
			continue
		var key := "%d:%d,%d" % [id, cell.x, cell.y]
		_playing[key] = {"layer": tml, "cell": cell, "step": 0, "t": 0.0}
		_play(tml, cell, SEQUENCE[0])


func _advance(delta: float) -> void:
	var finished := []
	for key in _playing:
		var st: Dictionary = _playing[key]
		st["t"] += delta
		while st["t"] >= STEP_TIME and st["step"] < SEQUENCE.size() - 1:
			st["t"] -= STEP_TIME
			st["step"] += 1
			_play(st["layer"], st["cell"], SEQUENCE[st["step"]])
		if st["step"] >= SEQUENCE.size() - 1:
			finished.append(key)
	for key in finished:
		_playing.erase(key)


func _play(tml: TileMapLayer, cell: Vector2i, frame_index: int) -> void:
	var src := tml.get_cell_source_id(cell)
	if src < 0:
		return
	tml.set_cell(cell, src, FRAMES[frame_index])
	_dirty = true
