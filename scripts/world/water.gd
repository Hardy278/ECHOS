class_name Water
extends Node2D

## 水：从当前房间的图块里长出来的水域。
##
## 范围、池底、一共几个池子，全由"哪些格子被标成水"决定，跟画面永远一致。
## 唯一不能从格子推的是**水面那条线的 y**：水面贴图自己带一段透明的浪尖
## （水面动画格四帧都是到第 4 行才覆盖过半），所以顶行的格子往上还空着一条。
## 判定线 = 顶行格子顶边 + surface_inset，默认从图集 alpha 量出来，
## 也可以直接填世界单位覆盖。
##
## 判定线是静止的：水面在动，判定跟着波峰抖会让玩家在"淹死 / 没淹死"之间被弹。
##
## 碰撞箱是 Area2D（每行水格并成一段矩形），顶边就是这条判定线。它只用来感知
## "谁在水里"，不参与物理——水是能穿过去的。
##
## 约定：三层的变换一致（现在所有房间都是 scale 2），所以层里的格子坐标直接
## 当世界格用；这个节点必须留在原点，矩形是按世界坐标算的。

## 水图块的自定义数据名（TileSet 的 custom data 层）
const WATER_KEY := &"water"
## 一行里至少这么多比例是水，就算水面到了这一行
const HALF_COVER := 0.5

## 判定线相对顶行水格的下沉（世界单位）。-1 = 从图集里量
@export var surface_inset := -1.0

var _ref: TileMapLayer            ## 格子 ⇄ 世界坐标的参照层
var _cell := Vector2(16.0, 16.0)  ## 一格的世界尺寸
var _surface: Dictionary = {}     ## 世界格 → 这个池子的水面 y
var _areas: Array = []
var _alpha: Dictionary = {}       ## 纹理 → Image，一张只读一次


func _ready() -> void:
	add_to_group("water")
	var rooms := get_tree().get_first_node_in_group("room_system")
	if rooms == null:
		return
	rooms.connect("room_changed", _on_room_changed)
	var cur: Room = rooms.get("current")
	if cur != null:
		bind_room(cur)


func _on_room_changed(room: Room) -> void:
	bind_room(room)


# ---------------------------------------------------------------- 对外

## 这个矩形是不是整个没进水里：顶边两个角都在水面以下
func submerged(rect: Rect2) -> bool:
	return _wet(Vector2(rect.position.x, rect.position.y)) \
			and _wet(Vector2(rect.end.x, rect.position.y))


## 换房间：整批重来
func bind_room(room: Room) -> void:
	_clear()
	if room == null:
		return
	var layers := room.layers()
	for l in layers:
		var tml := l as TileMapLayer
		if tml != null and tml.tile_set != null:
			_ref = tml
			break
	if _ref == null:
		return
	_cell = Vector2(_ref.tile_set.tile_size) * _ref.global_scale.abs()

	var wet := {}     # 世界格 → 顶行透明厚度（像素）
	for l in layers:
		var tml := l as TileMapLayer
		if tml == null or tml.tile_set == null:
			continue
		for c in tml.get_used_cells():
			if _is_water(tml, c):
				wet[c] = mini(int(wet.get(c, 999)), _inset_px(tml, c))

	var pool := 0
	for start in wet:
		if _surface.has(start):
			continue                      # 这个池子已经算过了
		var cells := _flood(start, wet)
		if not cells.is_empty():
			_fill(cells, wet, _make_area(pool))
			pool += 1


# ---------------------------------------------------------------- 装配

func _clear() -> void:
	_ref = null
	_cell = Vector2(16.0, 16.0)
	_surface.clear()
	for a in _areas:
		var n := a as Node
		if is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	_areas.clear()


func _make_area(index: int) -> Area2D:
	var area := Area2D.new()
	area.name = "Pool%d" % index
	area.collision_layer = 0      # 不挡任何人
	area.collision_mask = 1       # 只在乎玩家那一层
	area.monitoring = true
	add_child(area)
	_areas.append(area)
	return area


## 一个池子：先算水面，写进每个格子，再给每一行建出碰撞箱
func _fill(cells: Array, wet: Dictionary, area: Area2D) -> void:
	var top := 1 << 30
	for c in cells:
		top = mini(top, (c as Vector2i).y)

	var px := 999
	for c in cells:
		if (c as Vector2i).y == top:
			px = mini(px, int(wet[c]))

	var drop := surface_inset
	if drop < 0.0:
		var px_per_unit := _cell.y / float(_ref.tile_set.tile_size.y)
		drop = float(px if px != 999 else 0) * px_per_unit
	var surface_y := _cell_rect(Vector2i(0, top)).position.y + drop

	for c in cells:
		_surface[c] = surface_y

	# 每一行把连续的水格并成一段矩形；顶行的上边抬到判定线
	var rows := {}
	for c in cells:
		var v := c as Vector2i
		if not rows.has(v.y):
			rows[v.y] = []
		(rows[v.y] as Array).append(v.x)
	for ry in rows:
		var xs: Array = rows[ry]
		xs.sort()
		var run := 1
		for i in range(1, xs.size()):
			if int(xs[i]) == int(xs[i - 1]) + 1:
				run += 1
				continue
			_add_box(area, Vector2i(int(xs[i - 1]) - run + 1, int(ry)),
					run, int(ry) == top, surface_y)
			run = 1
		_add_box(area, Vector2i(int(xs[xs.size() - 1]) - run + 1, int(ry)),
				run, int(ry) == top, surface_y)


func _add_box(area: Area2D, cell: Vector2i, length: int, is_top: bool,
		surface_y: float) -> void:
	var r := _cell_rect(cell)
	r.size.x = _cell.x * float(length)
	if is_top:
		var cut := surface_y - r.position.y
		r.position.y += cut
		r.size.y -= cut
	if r.size.y <= 0.5:
		return
	var shape := RectangleShape2D.new()
	shape.size = r.size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = r.get_center()      # Area2D 在原点，所以这就是世界坐标
	area.add_child(cs)


# ---------------------------------------------------------------- 查询

func _wet(p: Vector2) -> bool:
	if _ref == null or not is_instance_valid(_ref):
		return false
	var c := _ref.local_to_map(_ref.to_local(p))
	return _surface.has(c) and p.y >= float(_surface[c])


## 4 连通，把水格分成一个个池子
func _flood(start: Vector2i, wet: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	var stack: Array = [start]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if seen.has(p) or not wet.has(p):
			continue
		seen[p] = true
		out.append(p)
		stack.append(p + Vector2i.LEFT)
		stack.append(p + Vector2i.RIGHT)
		stack.append(p + Vector2i.UP)
		stack.append(p + Vector2i.DOWN)
	return out


func _cell_rect(cell: Vector2i) -> Rect2:
	var mid := _ref.to_global(_ref.map_to_local(cell))
	return Rect2(mid - _cell * 0.5, _cell)


# ---------------------------------------------------------------- 图块

func _is_water(layer: TileMapLayer, cell: Vector2i) -> bool:
	var td := _tile_data(layer, cell)
	return td != null and bool(td.get_custom_data(WATER_KEY))


func _tile_data(layer: TileMapLayer, cell: Vector2i) -> TileData:
	var src := layer.get_cell_source_id(cell)
	if src < 0:
		return null
	var atlas := layer.tile_set.get_source(src) as TileSetAtlasSource
	if atlas == null:
		return null
	return atlas.get_tile_data(layer.get_cell_atlas_coords(cell),
			layer.get_cell_alternative_tile(cell))


## 这个图块顶上透明的厚度（像素）：自上往下找第一行"过半是水"的。
## 动画的几帧里取最靠上的那一帧（波峰），判定线贴着看得见的水面。
func _inset_px(layer: TileMapLayer, cell: Vector2i) -> int:
	var atlas := layer.tile_set.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
	if atlas == null or atlas.texture == null:
		return 0
	var img := _image_of(atlas.texture)
	if img == null:
		return 0
	var coords := layer.get_cell_atlas_coords(cell)
	var best := 1 << 30
	for f in maxi(1, atlas.get_tile_animation_frames_count(coords)):
		var r := atlas.get_tile_texture_region(coords, f)
		var need := int(ceil(float(r.size.x) * HALF_COVER))
		for y in range(r.position.y, r.end.y):
			var n := 0
			for x in range(r.position.x, r.end.x):
				if img.get_pixel(x, y).a >= 0.5:
					n += 1
					if n >= need:
						break
			if n >= need:
				best = mini(best, y - r.position.y)
				break
	return 0 if best == (1 << 30) else best


func _image_of(tex: Texture2D) -> Image:
	if not _alpha.has(tex):
		_alpha[tex] = tex.get_image()
	return _alpha[tex]
