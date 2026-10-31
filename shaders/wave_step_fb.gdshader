shader_type canvas_item;
render_mode blend_disabled;

// 二维波动方程的**一个时间步**：
//   u(t+1) = 2u(t) - u(t-1) + cfl * (邻域和 - 4u(t))
//
// 每帧往一块缓冲里画一个全屏四边形：它采样**另一块**缓冲（src_tex）算出下一步。
// 两块 SubViewport 互相采样、轮流当"正面"（ping-pong），所以状态是一块显式纹理，
// 不依赖 hint_screen_texture——那个"屏幕快照"实测每步会带进约 0.1 texel 的偏差。
//
// 通道：R = u(t)，G = u(t-1)，B = 包络（残影）
// 缓冲必须浮点（use_hdr_2d）；8 位量化的误差会被二阶差分迅速放大。
//
// 墙来自世界几何纹理 geo_tex（EchoWorld 每帧现画的那张），通道含义：
//   R = 吸声性  G = 绝对折射率 n  B = 透声性  A = 覆盖

uniform sampler2D src_tex : filter_nearest, repeat_disable;
uniform sampler2D geo_tex : filter_nearest, repeat_disable;
uniform vec2 field_size = vec2(480.0, 270.0);
uniform float cfl = 0.48;
uniform float stride = 4.0;
uniform float damp = 0.998;
uniform float env_decay = 0.9971;
uniform float hf_damp : hint_range(0.0, 0.5) = 0.01;
// 有出口的那条边做成吸声层：波走到房间边缘被吃掉，不弹回来。
// (左, 右, 上, 下)，1 = 这条边有相邻房间 = 开口 = 吸声；0 = 世界的尽头 = 照旧全反射。
uniform vec4 sponge_edges = vec4(0.0);
uniform float sponge_w = 28.0;         // 吸声层宽度（texel）
uniform float sponge_absorb = 0.5;     // 贴边处每步损失比例（向内侧按平方衰减）
uniform vec2 emit_px = vec2(240.0, 238.0);
uniform float inject = 0.0;
uniform float inject_r = 6.0;
// 没有遮罩：注入只是一个以声源为中心的高斯（半径 inject_r）。
// 一声能传多远，只由 damp、房间声学和中间撞上了什么决定，不再有半径上限。
uniform float reset = 0.0;
// 定场：切房间时把上一间房子门口那一薄片原样写进新房间的入口侧。
// 只在 reset 帧写一次，之后交给场自己演化。
uniform sampler2D seed_tex : filter_nearest, repeat_disable;
uniform float seed = 0.0;                    // 1 = 这一帧在定场
uniform vec2 seed_size = vec2(12.0, 270.0);  // 薄片的像素尺寸
uniform vec2 seed_at = vec2(28.0, 0.0);      // 薄片贴在哪（竖片看 .x，横片看 .y）
uniform float seed_gain = 0.7;               // 只有开口那一部分能量该过去

// 这一格对波的"阻挡度"：1 = 完全挡，0 = 空气 / 水 / 完全透声。
// 透声性是连续的，所以木平台那种"透一点点"的图块给 0.3 → 0.7 的阻挡：
// 波大部分被反射，一小部分漏过去。
float blockage_at(vec2 uv) {
	vec4 m = texture(geo_tex, uv);
	if (m.a < 0.5) {
		return 0.0;          // 没有图块 = 空气
	}
	return clamp(1.0 - m.b, 0.0, 1.0);
}

// 挡住一半以上的才当"看不清那边"用（注入的视线检查）
bool opaque_at(vec2 uv) {
	return blockage_at(uv) > 0.5;
}

// 这一格在吸声层里有多深：0 = 不在吸声层，1 = 紧贴开口那条边。
// 只对空气格生效（调用处乘 (1 - block)），墙那半边仍然自己反射。
float sponge_at(vec2 uv) {
	vec2 e = uv * field_size;
	float d = 1e9;
	if (sponge_edges.x > 0.5) { d = min(d, e.x); }
	if (sponge_edges.y > 0.5) { d = min(d, field_size.x - e.x); }
	if (sponge_edges.z > 0.5) { d = min(d, e.y); }
	if (sponge_edges.w > 0.5) { d = min(d, field_size.y - e.y); }
	if (d >= sponge_w) {
		return 0.0;
	}
	float t = clamp(d / sponge_w, 0.0, 1.0);   // 0 = 贴边，1 = 吸声层内侧
	return (1.0 - t) * (1.0 - t);
}

// 从源点到当前 texel 的粗略视线检查：中间有实体就不注入。
// 没有这一步，高斯注入会直接渗到墙背面，看起来像声音"穿墙"了。
bool clear_path(vec2 a, vec2 b) {
	for (int k = 2; k <= 8; k++) {
		if (opaque_at(mix(a, b, float(k) / 8.0))) {
			return false;
		}
	}
	return true;
}

// 邻居取样。半步中点也要查材质：跨步步长可能大于薄墙厚度，
// 只查 ±stride 会让波从平台中间穿过去。
// block = 1 时零梯度（Neumann）全反射；block = 0 时正常取邻居；
// 中间值按比例混合 —— 这就是"透声"。
float nb(vec2 nuv, vec2 muv, float center) {
	float block = max(blockage_at(nuv), blockage_at(muv));
	return mix(texture(src_tex, nuv).r, center, block);
}

// 定场：把上一间房子门口那一薄片写进新房间的入口侧。
// R 和 G 一起搬，方向就自动保住了（G 是上一步，也就是"从哪来"）。
vec3 seed_write(vec2 uv) {
	vec2 p = uv * field_size;
	float along;
	vec2 suv;
	if (seed_size.x < seed_size.y) {          // 竖片：左右出口，按列贴
		along = (p.x - seed_at.x + 0.5) / seed_size.x;
		suv = vec2(along, p.y / field_size.y);
	} else {                                  // 横片：上下出口，按行贴
		along = (p.y - seed_at.y + 0.5) / seed_size.y;
		suv = vec2(p.x / field_size.x, along);
	}
	if (along < 0.0 || along > 1.0) {
		return vec3(0.0);
	}
	vec4 s = texture(seed_tex, suv);
	return vec3(s.r, s.g, s.b);
}

// 按整数像素坐标取邻居：p 是当前 texel 的整数下标，off 是整数偏移。
// 分子全是精确整数（≤ 480），只有最后一次除法会舍入，所以 x 和 y 走的是
// 完全相同的数值路径——之前把小数直接加在 UV 上时，480 与 270 的舍入不同，
// 每步会留下一点方向性偏差。
vec2 uv_at(vec2 p, vec2 off) {
	return (p + off + vec2(0.5)) / field_size;
}

void fragment() {
	vec3 outc = vec3(0.0);

	if (reset < 0.5) {
		vec2 p = floor(UV * field_size);
		vec4 s = texture(src_tex, uv_at(p, vec2(0.0)));
		float u = s.r;
		float um1 = s.g;

		float l  = nb(uv_at(p, vec2(-stride, 0.0)), uv_at(p, vec2(-stride * 0.5, 0.0)), u);
		float r  = nb(uv_at(p, vec2(stride, 0.0)), uv_at(p, vec2(stride * 0.5, 0.0)), u);
		float d  = nb(uv_at(p, vec2(0.0, -stride)), uv_at(p, vec2(0.0, -stride * 0.5)), u);
		float up = nb(uv_at(p, vec2(0.0, stride)), uv_at(p, vec2(0.0, stride * 0.5)), u);

		float lap = l + r + d + up - 4.0 * u;

		vec4 m = texture(geo_tex, UV);
		// 介质：G 是绝对折射率 n（空气 = 1，水 = 1.33，玻璃 ≈ 1.5），波速 = 空气速 / n。
		// cfl 是 (c·dt/dx)²，所以这里除 n²；n 在界面上突变多少，就折射 / 反射多少。
		// 因为基础 cfl 已经贴着 0.5 的稳定上限，只能表达 n >= 1（比空气慢的介质）。
		float n = max(m.g, 1.0);
		float local_cfl = cfl / (n * n);
		float un = 2.0 * u - um1 + local_cfl * lap;

		float navg = (l + r + d + up) * 0.25;
		un = mix(un, navg, hf_damp);

		// 阻挡：完全挡的格子里场恒为 0；透一点声的格子里按比例衰减
		float block = 0.0;
		if (m.a > 0.5) {
			block = clamp(1.0 - m.b, 0.0, 1.0);
		}
		un *= (1.0 - block);
		un *= damp;
		// 开口方向的吸声层：走到房间边缘的能量就散了，不会掉头回来
		un *= 1.0 - sponge_at(UV) * sponge_absorb * (1.0 - block);
		un = clamp(un, -1.0, 1.0);

		// 注入：被墙挡住的地方不注入（高斯尾巴不能越过实体）
		if (inject > 0.0001) {
			float dsrc = distance(p + vec2(0.5), emit_px);
			float g = exp(-(dsrc * dsrc) / (inject_r * inject_r));
			if (g > 0.002 && !clear_path(emit_px / field_size, UV)) {
				g = 0.0;
			}
			un += inject * g;
		}

		float env = max(abs(un), s.b * env_decay);
		outc = vec3(un, u, clamp(env, 0.0, 1.0));
	} else if (seed > 0.5) {
		outc = seed_write(UV) * seed_gain;
	}

	COLOR = vec4(outc, 1.0);
}
