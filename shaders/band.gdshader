shader_type canvas_item;

// 内侧表面带：有覆盖的格子里，沿上下左右（**不含斜角**）走 band_px 步以内
// 能碰到空气 texel（或碰到另一种介质）的那些格子。严格 1 个 tile 像素厚。
// 输出：R = 表面带强度。
//
// 斜对角不算：采样窗口还是方的（-band_px..band_px），但只采横竖两条线。
// 连斜角一起算的话，拐角会多出一格 45° 方向的带（离表面 √2 格），
// 看起来就比"一格"厚了。
// band_px 的单位是场 texel：2 倍缩放的房间 band_px = 2 = 1 个 tile 像素。
//
// R 通道是**显现边缘**（surface）：0 = 这块砖不出高光，1 = 正常。
//
// 两种触发条件：
//   1. 邻居是空气（没有覆盖）。地形和实体的轮廓都靠这条。
//   2. 邻居是**另一种介质**（transmit 或 c 不同），且自己不是折射介质。
//      没有这条，水和石头、玻璃和砖的交界根本不存在——水泡在石头里的那圈池壁
//      就是它。折射介质（水、玻璃）不画自己的交界边：它们和空气的 Z 是匹配的，
//      本来就没有回声，看得见的应该是**墙**被泡出来的那一圈。
//
// **这条只在图块之间生效**：实体（草、门、钟、花）写进几何纹理的 A 是 0.7，
// 图块写 1.0（都算"有覆盖"，但能分开认）。实体贴着地形时不是"两种材质相撞"，
// 是同一样东西的前后关系——在那里画一条边，看起来就是实体和地面之间裂了道缝。

uniform sampler2D geo_tex : filter_nearest, repeat_disable;
uniform vec2 field_size = vec2(480.0, 270.0);
uniform int band_px = 2;

const int MAX_BAND_PX = 4;
// 通道是 RGBA8，1/255 一档，取 1.5 档当"不同介质"的门槛
const float EPS = 0.006;
// 实体写的 A（图块是 1.0）
const float ENTITY_A = 0.7;

bool is_entity(vec4 t) {
	return t.a < 0.9;
}

void fragment() {
	vec2 px = 1.0 / field_size;
	vec4 self_tex = texture(geo_tex, UV);
	float cov = step(0.5, self_tex.a);
	float near_air = 0.0;
	float near_other = 0.0;
	for (int dy = -MAX_BAND_PX; dy <= MAX_BAND_PX; dy++) {
		if (dy < -band_px || dy > band_px) {
			continue;
		}
		for (int dx = -MAX_BAND_PX; dx <= MAX_BAND_PX; dx++) {
			if (dx < -band_px || dx > band_px) {
				continue;
			}
			// 只认正交方向：dx、dy 都非零 = 斜对角，跳过。
			if (dx != 0 && dy != 0) {
				continue;
			}
			vec4 nb = texture(geo_tex, UV + vec2(float(dx), float(dy)) * px);
			if (nb.a < 0.5) {
				near_air = 1.0;
			} else if (!is_entity(nb) && !is_entity(self_tex)
					&& (abs(nb.g - self_tex.g) > EPS || abs(nb.b - self_tex.b) > EPS)) {
				near_other = 1.0;
			}
		}
	}
	// 介质交界只画"硬"的那一侧：水和玻璃不画自己的交界边。
	// 它们反射本来就近于 0（Z 贴着空气），所以看得见的是**墙被水泡出来的那一圈**，
	// 而不是水的轮廓。水对自己和空气之间那条线仍然照画（上面的空气条件），
	// 那是池子的可见边缘，留着。
	float solid = 1.0 - step(EPS, self_tex.g);
	float edge = max(near_air, near_other * solid);
	float b = cov * edge * self_tex.r;
	COLOR = vec4(b, b, b, 1.0);
}
