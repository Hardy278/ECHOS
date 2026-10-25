shader_type canvas_item;
render_mode blend_disabled;

// 二维波动方程单步（显式中心差分）。
//   u(t+1) = 2u(t) - u(t-1) + CFL * (邻域和 - 4u(t))
//
// 状态必须存在浮点缓冲里（Viewport.use_hdr_2d = true）。
// 用 8 位 offset 编码会在每步引入 1/255 的量化误差，被二阶差分迅速放大，
// 几十步内整个场就会退化成噪声糊——这不是参数问题，是精度问题。
//
// 通道：R = u(t)，G = u(t-1)，B = 包络（|u| 的衰减记忆）
// 稳定性：二维显式格式要求 CFL <= 0.5（Courant 数 <= 1/√2）

uniform sampler2D state : filter_nearest, repeat_disable;
uniform sampler2D mat_tex : filter_nearest, repeat_disable;
uniform vec2 field_size = vec2(480.0, 270.0);
uniform float cfl = 0.45;
uniform float damp = 0.9988;
uniform float env_decay = 0.9988;
uniform float hf_damp : hint_range(0.0, 0.5) = 0.10;   // 高频阻尼：压住粗网格上的数值色散先导
uniform vec2 src_px = vec2(240.0, 238.0);
uniform float inject = 0.0;
uniform float inject_r = 5.0;
uniform float reset = 0.0;

void fragment() {
	vec3 outc = vec3(0.0);

	if (reset < 0.5) {
		vec2 px = 1.0 / field_size;
		vec4 s = texture(state, UV);
		float u = s.r;
		float um1 = s.g;

		vec2 lu = UV - vec2(px.x, 0.0);
		vec2 ru = UV + vec2(px.x, 0.0);
		vec2 du = UV - vec2(0.0, px.y);
		vec2 uu = UV + vec2(0.0, px.y);

		// 固体邻居按零梯度（Neumann）处理 → 干净的正向反射
		float l = texture(mat_tex, lu).r > 0.5 ? u : texture(state, lu).r;
		float r = texture(mat_tex, ru).r > 0.5 ? u : texture(state, ru).r;
		float d = texture(mat_tex, du).r > 0.5 ? u : texture(state, du).r;
		float up = texture(mat_tex, uu).r > 0.5 ? u : texture(state, uu).r;

		float lap = l + r + d + up - 4.0 * u;
		float un = 2.0 * u - um1 + cfl * lap;

		// 轻度低通：只削网格尺度的高频（色散先导、棋盘噪声），几乎不动主波前
		float navg = (l + r + d + up) * 0.25;
		un = mix(un, navg, hf_damp);

		vec4 m = texture(mat_tex, UV);
		un = mix(un, 0.0, m.r);        // 固体内部不传播
		un *= 1.0 - m.g * 0.35;        // 吸音材质
		un *= damp;
		un = clamp(un, -1.0, 1.0);

		float dsrc = distance(UV * field_size, src_px);
		un += inject * exp(-(dsrc * dsrc) / (inject_r * inject_r));

		float env = max(abs(un), s.b * env_decay);
		outc = vec3(un, u, clamp(env, 0.0, 1.0));
	}

	COLOR = vec4(outc, 1.0);
}
