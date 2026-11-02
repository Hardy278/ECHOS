extends Node

## 层表的全局入口（autoload：EchoLayers）。
##
## 为什么是 autoload 而不是各处 preload：校验只跑一次，层表写错要在**启动时**
## 就报出来，而不是等某个房间绑定时才炸。
##
## 为什么不允许每个房间有自己的层表：层顺序决定几何纹理里谁压谁，
## 两个房间不一致 => 同一堵墙声学行为不同。

const SET_PATH := "res://world/layer_set.tres"

var _layers: Array[EchoLayer] = []


func _ready() -> void:
	_reload()


func _reload() -> void:
	_layers.clear()
	var res := load(SET_PATH) as EchoLayerSet
	if res == null:
		push_error("EchoLayers: 载入不了 %s" % SET_PATH)
		return
	for l in res.layers:
		if l is EchoLayer:
			_layers.append(l as EchoLayer)

	_validate()

	_layers.sort_custom(func(a: EchoLayer, b: EchoLayer) -> bool: return a.z < b.z)


# ---------------------------------------------------------------- 对外

## 全部层，按 z 升序（底层在前）
func layers() -> Array[EchoLayer]:
	return _layers


## 只取图块层，按 z 升序
func tile_layers() -> Array[EchoLayer]:
	var out: Array[EchoLayer] = []
	for l in _layers:
		if l.kind == EchoLayer.Kind.TILE:
			out.append(l)
	return out


## 实体层（全表只有一个）
func entity_layer() -> EchoLayer:
	for l in _layers:
		if l.kind == EchoLayer.Kind.ENTITY:
			return l
	return null


# ---------------------------------------------------------------- 校验

## 层表写错必须**启动时就炸**。这里只查"静态可查"的东西；
## "房间里的节点是否存在"要等绑定时才能查。
func _validate() -> void:
	if _layers.is_empty():
		push_error("EchoLayers: 层表是空的（%s）" % SET_PATH)
		return

	var seen_path := {}
	var seen_z := {}
	var entity_count := 0

	for l in _layers:
		var label := "%s(z=%d)" % [String(l.path), l.z]

		# z 唯一：重复 = 绘制顺序未定义
		if seen_z.has(l.z):
			push_error("EchoLayers: z=%d 重复（%s 和 %s）。重复即覆盖顺序未定义" % [
					l.z, seen_z[l.z], label])
		seen_z[l.z] = label

		if l.kind == EchoLayer.Kind.ENTITY:
			entity_count += 1
			if not String(l.path).is_empty():
				push_warning("EchoLayers: 实体层不该填 path（%s）" % label)
			continue

		# 图块层必须有唯一 path
		var p := String(l.path)
		if p.is_empty():
			push_error("EchoLayers: 图块层没填 path（%s）" % label)
			continue
		if seen_path.has(p):
			push_error("EchoLayers: path '%s' 重复" % p)
		seen_path[p] = true

	if entity_count != 1:
		push_error("EchoLayers: 实体层应当恰好一个，现在是 %d 个" % entity_count)
