shader_type canvas_item;
render_mode blend_disabled;

// 二维波动方程单步。同一 viewport 里按顺序画 SUBSTEPS 个全屏四边形，
// 每个都用 hint_screen_texture 读上一个四边形刚写下的结果 —— 这就是子帧。
//   u(t+1) = 2u(t) - u(t-1) + CFL * (邻域和 - 4u(t))
//
// 通道：R = u(t)，G = u(t-1)，B = 包络（残影）
// 缓冲必须浮点（use_hdr_2d）；8 位量化的误差会被二阶差分迅速放大。

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D mat_tex : filter_nearest, repeat_disable;
uniform vec2 field_size = vec2(480.0, 270.0);
uniform float cfl = 0.48;
uniform float stride = 2.0;
uniform float damp = 0.998;
uniform float env_decay = 0.9971;
uniform float hf_damp : hint_range(0.0, 0.5) = 0.01;
uniform vec2 emit_px = vec2(240.0, 238.0);
uniform float inject = 0.0;
uniform float inject_r = 6.0;
uniform float reset = 0.0;

bool solid_at(vec2 uv) {
	return texture(mat_tex, uv).r > 0.5;
}

// 邻居取样。半步中点也要查材质：跨步步长可能大于薄墙厚度，
// 只查 ±stride 会让波从平台中间穿过去。
float nb(vec2 nuv, vec2 muv, float center) {
	if (solid_at(nuv) || solid_at(muv)) {
		return center;         // 固体 → 零梯度（Neumann），反射
	}
	return texture(screen_tex, nuv).r;
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
		float un = 2.0 * u - um1 + cfl * lap;

		float navg = (l + r + d + up) * 0.25;
		un = mix(un, navg, hf_damp);

		vec4 m = texture(mat_tex, UV);
		un = mix(un, 0.0, m.r);
		un *= 1.0 - m.g * 0.35;
		un *= damp;
		un = clamp(un, -1.0, 1.0);

		float dsrc = distance(UV * field_size, emit_px);
		un += inject * exp(-(dsrc * dsrc) / (inject_r * inject_r));

		float env = max(abs(un), s.b * env_decay);
		outc = vec3(un, u, clamp(env, 0.0, 1.0));
	}

	COLOR = vec4(outc, 1.0);
}
