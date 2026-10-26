extends RefCounted

## 把三个 TileMapLayer 的图集 alpha 烘成回响场要的纹理。
##
## 按约定实现：
##   1. 前景 / 中景 / 后景 分别提取到一张 Texture 的 R / G / B 三个通道
##   2. 每个通道**各自**做横向模糊 → 竖向模糊
##   3. 模糊值低于阈值的算边缘
##   4. 再腐蚀，把边缘限制在 1px
##
## 关于"1px"：指 **TileSet 里 tile 的 1 个像素**，不是场坐标的 1 个 texel。
## 所以模糊半径、阈值、腐蚀深度全部由该图层自己的缩放推出
## （r = 每 tile 像素对应多少个场 texel），换缩放不用改任何常量。
##
## 叠加：前景遮挡中景、前+中遮挡后景。挡声 = 三通道并集。
## 缺哪一层通道就留空：目前只有 ForeGround / Background，所以 G（中景）是空的。

const ALPHA_CUT := 0.5
const ERODE_MAX_PASSES := 8
const DEFAULT_ONE_WAY_ABSORB := 0.20


## layers: [fore, mid, back]（可为 null）
static func bake(layers: Array, size: Vector2i) -> Dictionary:
	var w := size.x
	var h := size.y
	var n := w * h

	var channels: Array[PackedFloat32Array] = []
	for c in 3:
		var m := PackedFloat32Array()
		m.resize(n)
		channels.append(m)
	var absorb := PackedFloat32Array()
	absorb.resize(n)

	# 每层自己的"一个 tile 像素 = 几个场 texel"
	var scale_px: Array[int] = [1, 1, 1]
	for idx in 3:
		var l: TileMapLayer = layers[idx] if idx < layers.size() else null
		if l != null:
			scale_px[idx] = maxi(1, roundi((absf(l.global_scale.x) + absf(l.global_scale.y)) * 0.5))

	var classes := Image.create(w, h, false, Image.FORMAT_RGBA8)
	classes.fill(Color(0, 0, 0, 1))
	var cdata := classes.get_data()

	# 从后往前铺，形成遮挡
	var cells := [0, 0, 0]
	for idx in [2, 1, 0]:
		var layer: TileMapLayer = layers[idx] if idx < layers.size() else null
		cells[idx] = _blit(layer, idx, cdata, channels, absorb, w, h)
	classes.set_data(w, h, false, Image.FORMAT_RGBA8, cdata)

	# ---- 每通道各自：横模糊 → 竖模糊 → 阈值 → 腐蚀到 1 tile 像素 ----
	var bands: Array[Dictionary] = []
	for c in 3:
		bands.append(_edge_band(channels[c], w, h, scale_px[c]))

	# ---- 挡声掩码 = 三通道并集 ----
	var solid := PackedFloat32Array()
	solid.resize(n)
	var solid_texels := 0
	for i in n:
		if channels[0][i] > 0.5 or channels[1][i] > 0.5 or channels[2][i] > 0.5:
			solid[i] = 1.0
			solid_texels += 1

	# ---- mat：R=实体 G=吸声 B=单向（absorb>0 视为单向/木料）----
	var mat := Image.create(w, h, false, Image.FORMAT_RGBA8)
	mat.fill(Color(0, 0, 0, 1))
	var mdata := mat.get_data()
	for i in n:
		if solid[i] < 0.5:
			continue
		var bi := i * 4
		mdata[bi] = 255
		mdata[bi + 1] = int(round(clampf(absorb[i], 0.0, 1.0) * 255.0))
		mdata[bi + 2] = 255 if absorb[i] > 0.0 else 0
		mdata[bi + 3] = 255
	mat.set_data(w, h, false, Image.FORMAT_RGBA8, mdata)

	# ---- band：R=前(并后) G=中 B=后，wave_view 读 .r ----
	var band_img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	band_img.fill(Color(0, 0, 0, 0))
	var bdata := band_img.get_data()
	var band_texels := 0
	for i in n:
		var vis: bool = bands[0]["bits"][i] > 0 or bands[2]["bits"][i] > 0 or bands[1]["bits"][i] > 0
		if vis:
			band_texels += 1
			bdata[i * 4] = 255
			bdata[i * 4 + 3] = 255
		if bands[1]["bits"][i] > 0:
			bdata[i * 4 + 1] = 255
		if bands[2]["bits"][i] > 0:
			bdata[i * 4 + 2] = 255
	band_img.set_data(w, h, false, Image.FORMAT_RGBA8, bdata)

	return {
		"mat": ImageTexture.create_from_image(mat),
		"band": ImageTexture.create_from_image(band_img),
		"classes": ImageTexture.create_from_image(classes),
		"summary": "格数 前 %d / 中 %d / 后 %d | 缩放 %d/%d/%d → 边厚 %d/%d/%d texel | 挡声 %d · 表面 %d texel | 腐蚀 %d/%d/%d 轮" % [
			cells[0], cells[1], cells[2],
			scale_px[0], scale_px[1], scale_px[2],
			scale_px[0], scale_px[1], scale_px[2],
			solid_texels, band_texels,
			bands[0]["passes"], bands[1]["passes"], bands[2]["passes"]],
	}


## 单通道：横模糊 → 竖模糊 → 阈值取边 → 腐蚀到 1 个 tile 像素（厚 = scale_px 个场 texel）
static func _edge_band(mask: PackedFloat32Array, w: int, h: int, scale_px: int) -> Dictionary:
	var r := maxi(1, scale_px)                       # 模糊半径：1 个 tile 像素
	var win := (2 * r + 1) * (2 * r + 1)
	var thr := 1.0 - 0.5 / float(win)                # 窗口里只要混进空气就算边缘

	var hb := _box(mask, w, h, r, true)
	var vb := _box(hb, w, h, r, false)

	var bits := PackedByteArray()
	bits.resize(w * h)
	for i in w * h:
		if mask[i] > 0.5 and vb[i] < thr:
			bits[i] = 255

	# 腐蚀：把"周围 r 内没有空气"的边削掉，保证厚度不超过 1 个 tile 像素。
	# 阈值选得对时这一轮删 0 个，收敛即停。
	var passes := 0
	while passes < ERODE_MAX_PASSES:
		var removed := 0
		var next := bits.duplicate()
		for y in h:
			for x in w:
				var i := y * w + x
				if bits[i] == 0:
					continue
				if _air_within(mask, x, y, r, w, h):
					continue
				next[i] = 0
				removed += 1
		bits = next
		passes += 1
		if removed == 0:
			break

	var count := 0
	for i in w * h:
		if bits[i] > 0:
			count += 1
	return {"bits": bits, "count": count, "passes": passes}


static func _air_within(mask: PackedFloat32Array, x: int, y: int, r: int, w: int, h: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx == 0 and dy == 0:
				continue
			var xx := x + dx
			var yy := y + dy
			if xx < 0 or yy < 0 or xx >= w or yy >= h:
				continue
			if mask[yy * w + xx] < 0.5:
				return true
	return false


## 把一层的图集 alpha 铺进场地。ch = 0/1/2 → R/G/B。
static func _blit(layer: TileMapLayer, ch: int, cdata: PackedByteArray,
		channels: Array, absorb: PackedFloat32Array, w: int, h: int) -> int:
	if layer == null or layer.tile_set == null:
		return 0

	var gt := layer.global_transform
	if is_zero_approx(gt.determinant()):
		return 0
	var inv := gt.affine_inverse()

	var absorb_layer := layer.tile_set.get_custom_data_layer_by_name("absorb")
	var img_cache := {}
	var count := 0
	var front: Array[int] = []
	for c in ch:
		front.append(c)

	for cell in layer.get_used_cells():
		var src_id := layer.get_cell_source_id(cell)
		var atlas := layer.tile_set.get_source(src_id) as TileSetAtlasSource
		if atlas == null or atlas.texture == null:
			continue
		if not img_cache.has(src_id):
			img_cache[src_id] = atlas.texture.get_image()
		var art: Image = img_cache[src_id]
		if art == null:
			continue

		var coords := layer.get_cell_atlas_coords(cell)
		var region := atlas.get_tile_texture_region(coords)
		var td := layer.get_cell_tile_data(cell)

		var one_way := false
		if td != null and layer.tile_set.get_physics_layers_count() > 0:
			for i in td.get_collision_polygons_count(0):
				if td.is_collision_polygon_one_way(0, i):
					one_way = true

		var ab := 0.0
		if absorb_layer >= 0 and td != null:
			ab = clampf(float(td.get_custom_data_by_layer_id(absorb_layer)), 0.0, 1.0)
		elif one_way:
			ab = DEFAULT_ONE_WAY_ABSORB

		count += 1

		# 图块在世界空间的 AABB 用四角换算，再逐个**场 texel** 反查图集像素：
		# 任何缩放/旋转都能对上，且"1px"始终由 _edge_band 的 scale_px 决定。
		var ts := layer.tile_set.tile_size
		var tl := layer.map_to_local(cell) - Vector2(ts) * 0.5
		var minx := INF
		var maxx := -INF
		var miny := INF
		var maxy := -INF
		for corner in [tl, tl + Vector2(ts.x, 0), tl + Vector2(0, ts.y), tl + Vector2(ts.x, ts.y)]:
			var wp: Vector2 = layer.to_global(corner)
			minx = minf(minx, wp.x)
			maxx = maxf(maxx, wp.x)
			miny = minf(miny, wp.y)
			maxy = maxf(maxy, wp.y)
		var x0 := maxi(0, int(floor(minx)))
		var x1 := mini(w - 1, int(ceil(maxx)) - 1)
		var y0 := maxi(0, int(floor(miny)))
		var y1 := mini(h - 1, int(ceil(maxy)) - 1)

		for wy in range(y0, y1 + 1):
			for wx in range(x0, x1 + 1):
				var lp: Vector2 = inv * Vector2(wx + 0.5, wy + 0.5) - tl
				if lp.x < 0.0 or lp.y < 0.0 or lp.x >= float(ts.x) or lp.y >= float(ts.y):
					continue
				var ax := clampi(int(lp.x), 0, ts.x - 1)
				var ay := clampi(int(lp.y), 0, ts.y - 1)
				if art.get_pixel(region.position.x + ax, region.position.y + ay).a < ALPHA_CUT:
					continue

				var i := wy * w + wx
				for f in front:
					channels[f][i] = 0.0
				channels[ch][i] = 1.0
				if ch != 0:
					absorb[i] = 0.0
				elif ab > 0.0:
					absorb[i] = ab

				var bi := i * 4
				cdata[bi] = 255 if ch == 0 else 0
				cdata[bi + 1] = 255 if ch == 1 else 0
				cdata[bi + 2] = 255 if ch == 2 else 0
	return count


## 方框模糊，半径 r（单位：场 texel），横或竖
static func _box(src: PackedFloat32Array, w: int, h: int, r: int, horizontal: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(w * h)
	var inv := 1.0 / float(2 * r + 1)
	for y in h:
		for x in w:
			var sum := 0.0
			for k in range(-r, r + 1):
				var xx := clampi(x + k, 0, w - 1) if horizontal else x
				var yy := y if horizontal else clampi(y + k, 0, h - 1)
				sum += src[yy * w + xx]
			out[y * w + x] = sum * inv
	return out
