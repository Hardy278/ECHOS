shader_type canvas_item;
render_mode blend_disabled;

// 二维波动方程单步。同一 viewport 里按顺序画 SUBSTEPS 个全屏四边形，
// 每个都用 hint_screen_texture 读上一个四边形刚写下的结果 —— 这就是子帧。
//   u(t+1) = 2u(t) - u(t-1) + CFL * (邻域和 - 4u(t))
//
// 通道：R = u(t)，G = u(t-1)，B = 包络（残影）
// 缓冲必须浮点（use_hdr_2d）；8 位量化的误差会被二阶差分迅速放大。
//
// 墙来自世界几何纹理 geo_tex（EchoWorld 每帧现画的那张），通道含义：
//   R = 吸声性  G = 绝对折射率 n  B = 透声性  A = 覆盖

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D geo_tex : filter_nearest, repeat_disable;
uniform vec2 field_size = vec2(480.0, 270.0);
uniform float cfl = 0.48;
uniform float stride = 2.0;
uniform float damp = 0.998;
uniform float env_decay = 0.9971;
uniform float hf_damp : hint_range(0.0, 0.5) = 0.01;
uniform vec2 emit_px = vec2(240.0, 238.0);
uniform float inject = 0.0;
uniform float inject_r = 6.0;
// 这一次发声的遮罩：半径 R = mask_span × ln(1 + 振幅/eps)，形状由 emit_falloff（k）决定。
//   - 亮度线性跟着振幅（inject），宽度是对数级增长 → 响度和宽度被拆开了
//   - dR/damp ∝ 1/amp：越响，半径增长越慢
//   - eps 越小，安静端被抬得越多、响度差被压得越平
uniform float mask_span = 30.0;        // 对数上的尺度（世界单位）
uniform float mask_eps = 0.03;         // 压缩强度
uniform float emit_falloff = 1.8;      // 形状：k > 1 时中心陡、边缘趋平
uniform float reset = 0.0;

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
	return mix(texture(screen_tex, nuv).r, center, block);
}

void fragment() {
	vec3 outc = vec3(0.0);

	if (reset < 0.5) {
		vec2 px = (1.0 / field_size) * stride;
		vec2 hpx = px * 0.5;

		vec4 s = texture(screen_tex, UV);
		float u = s.r;
		float um1 = s.g;

		float l  = nb(UV - px, UV - hpx, u);
		float r  = nb(UV + px, UV + hpx, u);
		float d  = nb(UV - vec2(0.0, px.y), UV - vec2(0.0, hpx.y), u);
		float up = nb(UV + vec2(0.0, px.y), UV + vec2(0.0, hpx.y), u);

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
		un = clamp(un, -1.0, 1.0);

		// 注入：被墙挡住的地方不注入（高斯尾巴不能越过实体）
		if (inject > 0.0001) {
			float dsrc = distance(UV * field_size, emit_px);
			float g = exp(-(dsrc * dsrc) / (inject_r * inject_r));
			// x = d / R，R 随强度对数增长：喊叫可以更响，但不会跟着更宽
			float mask_r = mask_span * log(1.0 + inject / max(mask_eps, 0.0001));
			mask_r = max(mask_r, 0.001);
			g *= pow(clamp(1.0 - dsrc / mask_r, 0.0, 1.0), emit_falloff);
			if (g > 0.002 && !clear_path(emit_px / field_size, UV)) {
				g = 0.0;
			}
			un += inject * g;
		}

		float env = max(abs(un), s.b * env_decay);
		outc = vec3(un, u, clamp(env, 0.0, 1.0));
	}

	COLOR = vec4(outc, 1.0);
}
