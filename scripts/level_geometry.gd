class_name LevelGeometry
extends RefCounted

## 关卡几何：固体矩形 → 物理碰撞体 + 射线求交线段。
## 单一数据源，保证"玩家撞到的墙"和"声音反弹的墙"永远是同一面墙。

# 材质吸收率。>= ABSORB_TERMINATE 的面会吞掉射线，不产生后续反弹（锁型 B）。
const MAT_STONE := 0.0
const MAT_METAL := 0.05
const MAT_FELT := 0.88

# 场空间 480x270，y 向下。坐标见 .local/opening-90s.md §3。
var solids: Array[Rect2] = []
var solid_abs: PackedFloat32Array = PackedFloat32Array()

# 线段数据（stride 4: ax, ay, sx, sy），法线（stride 2），吸收率（stride 1）
var seg_data: PackedFloat32Array = PackedFloat32Array()
var seg_norm: PackedFloat32Array = PackedFloat32Array()
var seg_abs: PackedFloat32Array = PackedFloat32Array()
var seg_count: int = 0


func _init() -> void:
	_build_level()
	_build_segments()


func _build_level() -> void:
	_add(Rect2(0, 246, 480, 24), MAT_STONE)      # 地板
	_add(Rect2(0, 0, 40, 270), MAT_STONE)        # 左墙
	_add(Rect2(0, 0, 430, 40), MAT_STONE)        # 天花板，右端止于 430
	_add(Rect2(430, 100, 50, 100), MAT_STONE)    # 右墙上段
	# DEMO：右墙下段改成吸音面，用来验证"终止点"机制（锁型 B 的取样）
	_add(Rect2(430, 200, 50, 70), MAT_FELT)      # 右墙下段（吸音）
	_add(Rect2(60, 214, 28, 32), MAT_METAL)      # 钟座
	_add(Rect2(120, 216, 68, 8), MAT_STONE)      # 台 A
	_add(Rect2(214, 186, 68, 8), MAT_STONE)      # 台 B
	_add(Rect2(308, 156, 68, 8), MAT_STONE)      # 台 C
	_add(Rect2(392, 126, 38, 8), MAT_STONE)      # 台 D


func _add(r: Rect2, absorb: float) -> void:
	solids.append(r)
	solid_abs.append(absorb)


func _build_segments() -> void:
	for i in solids.size():
		var r := solids[i]
		var a := solid_abs[i]
		var p := r.position
		var q := r.position + r.size
		# 上右下左四条边
		_add_seg(Vector2(p.x, p.y), Vector2(q.x, p.y), a)
		_add_seg(Vector2(p.x, q.y), Vector2(q.x, q.y), a)
		_add_seg(Vector2(p.x, p.y), Vector2(p.x, q.y), a)
		_add_seg(Vector2(q.x, p.y), Vector2(q.x, q.y), a)


func _add_seg(a: Vector2, b: Vector2, absorb: float) -> void:
	var s := b - a
	seg_data.append(a.x)
	seg_data.append(a.y)
	seg_data.append(s.x)
	seg_data.append(s.y)
	var n := Vector2(s.y, -s.x).normalized()
	seg_norm.append(n.x)
	seg_norm.append(n.y)
	seg_abs.append(absorb)
	seg_count += 1
