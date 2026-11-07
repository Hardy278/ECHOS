class_name ParamAtlas
extends RefCounted

## 图块参数图的烘焙：TileSet 的某个图集源 → 一张和它等大的纹理。
##
## 纯函数：不碰节点、不碰视口，所以能在 headless 里单独验，不用造房间。
## 缓存不在这里——谁用谁管（WaveGeometry 换房间时整批清掉）。

## 单面平台默认的"显现纹理"值：0.8（比普通砖暗一档，它只是一块薄板）
const DEFAULT_ONE_WAY_SHOW := 0.8
## 折射介质默认的"显现纹理"值：0.6（水要看着"暗一点、像能看进去"）
const DEFAULT_REFRACTIVE_SHOW := 0.6

## 两种图，通道含义不同，各自喂给一张视口：
##   · display = false（几何视口）: R = surface, G = ior, B = transmit, A = 1（覆盖）
##   · display = true （显示视口）: R = show,    G = alpha, B = 0,      A = 1（覆盖）
## surface / transmit 是美术填的 Z 推出来的（AcousticMedium.surface_from_z /
## transmit_from_z）。Z 这个名字只活在这里，着色器一点都不知道有它。
static func bake(tset: TileSet, src: int, display: bool) -> Texture2D:
	var atlas: TileSetAtlasSource = null
	if tset != null:
		atlas = tset.get_source(src) as TileSetAtlasSource
	var tex: Texture2D = atlas.texture if atlas != null else null
	if tex == null:
		return blank()

	var img := Image.create(tex.get_width(), tex.get_height(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var z_id := tset.get_custom_data_layer_by_name("Z")
	var ior_id := tset.get_custom_data_layer_by_name("ior")
	var show_id := tset.get_custom_data_layer_by_name("show")
	var alpha_id := tset.get_custom_data_layer_by_name("alpha")
	var has_phys := tset.get_physics_layers_count() > 0

	for i in atlas.get_tiles_count():
		var coords := atlas.get_tile_id(i)
		var td := atlas.get_tile_data(coords, 0)

		var one_way := false
		if td != null and has_phys:
			for pi in td.get_collision_polygons_count(0):
				if td.is_collision_polygon_one_way(0, pi):
					one_way = true
					break

		# 折射率：没填 = 空气（1.0）。水 1.33、玻璃 1.5 …… 越大声音越慢。
		# 上限只是防呆：基础 cfl 贴着稳定上限，n < 1 会让场爆掉，所以下限锁在 1。
		var ior := 1.0
		if ior_id >= 0 and td != null:
			ior = clampf(float(td.get_custom_data_by_layer_id(ior_id)), 1.0, AcousticMedium.IOR_MAX)

		# 声阻抗 Z 是美术填的那个量；透声系数由它推出来。
		var z := 0.0
		if z_id >= 0 and td != null:
			z = float(td.get_custom_data_by_layer_id(z_id))
		var transmit := AcousticMedium.transmit_from_z(z)

		# surface：显不显现边缘。由 Z 推出来（反射系数），不单独填。
		var surface := AcousticMedium.surface_from_z(z)

		# show：显不显现纹理。没填时按"材质种类"给默认值。
		var show := 1.0
		if show_id >= 0 and td != null:
			show = clampf(float(td.get_custom_data_by_layer_id(show_id)), 0.0, 1.0)
		elif one_way:
			show = DEFAULT_ONE_WAY_SHOW
		elif ior > 1.01:
			show = DEFAULT_REFRACTIVE_SHOW

		# 吸声 α：介质**内部**的体衰减，和界面上的 transmit 是两回事。
		# 只写进显示图的 G 通道，由 wave_step_fb 每步读。
		var alpha := 0.0
		if alpha_id >= 0 and td != null:
			alpha = clampf(float(td.get_custom_data_by_layer_id(alpha_id)), 0.0, 1.0)

		# 动画图块的每一帧都是图集里的一块矩形，全都要填。
		# 通道是 RGBA8（0~1），所以 c 要归一化：1 → 0，IOR_MAX → 1。
		var col := Color(show, alpha, 0.0, 1.0) if display \
				else Color(surface, AcousticMedium.ior_to_channel(ior), transmit, 1.0)
		var frames := maxi(1, atlas.get_tile_animation_frames_count(coords))
		for f in frames:
			img.fill_rect(atlas.get_tile_texture_region(coords, f), col)

	return ImageTexture.create_from_image(img)


## 1×1 全透明：图集缺失时的兜底。**不能给白**——白会让所有图块都算作有覆盖。
static func blank() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
