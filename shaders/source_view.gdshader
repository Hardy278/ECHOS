shader_type canvas_item;
render_mode blend_add;

// 一个声源在"总的照亮显示"里贡献的那一层。
//
// 每个点先算玩家实际能感知到的亮度：
//   z = x * exp(-d / L)
// x 是这个点原始的声音亮度（声源正常发声的场），d 是玩家到该点的距离。
// z <= τ 时直接为 0；否则过同一条感知曲线：
//   y = z + a z (1-z) (c-z)
// 弱光提亮和强光压暗是同一条曲线的两端，不是两个独立旋钮。
//
// 听者参数由 EchoListener 提供，EchoWorld 每帧推 uniform。
// 没有听者时 enable=0，直接用原始亮度。

uniform sampler2D env_field : filter_linear, repeat_disable;
uniform sampler2D band_tex : filter_nearest, repeat_disable;
uniform vec2 field_size = vec2(480.0, 270.0);
uniform float bg_gain = 0.45;       // 空气里的行波强度（太亮就调小）
uniform float edge_gain = 4.00;     // 撞到表面时的高光倍数
uniform float gain = 1.0;           // 这个物体的总体音量

uniform vec2 listener_px = vec2(240.0, 238.0);
uniform float dist_scale = 100.0;   // L
uniform float min_audible = 0.001;  // τ
uniform float curve_a = 1.0;        // a
uniform float curve_c = 0.1;        // c
uniform float enable = 0.0;         // 0 = 没有听者，直接用原始亮度

uniform float blur_px : hint_range(0.0, 4.0) = 1.20;
uniform vec4 tint = vec4(0.62, 0.82, 1.0, 1.0);

float lum(sampler2D tex, vec2 uv) {
	vec4 s = texture(tex, uv);
	return max(abs(s.r), s.b);
}

void fragment() {
	// ---- 场里的能量：小半径五点模糊，压掉跨步造成的方块感 ----
	vec2 px = (1.0 / field_size) * blur_px;
	float e = lum(env_field, UV) * 0.36;
	e += lum(env_field, UV + vec2(px.x, 0.0)) * 0.16;
	e += lum(env_field, UV - vec2(px.x, 0.0)) * 0.16;
	e += lum(env_field, UV + vec2(0.0, px.y)) * 0.16;
	e += lum(env_field, UV - vec2(0.0, px.y)) * 0.16;

	// 表面带画在实体内侧，而场在实体内部恒为 0 —— 取 3x3 邻域最大值才亮得起来
	float band = texture(band_tex, UV).r;
	if (band > 0.5) {
		vec2 opx = 1.0 / field_size;
		float m = 0.0;
		for (int dy = -1; dy <= 1; dy++) {
			for (int dx = -1; dx <= 1; dx++) {
				m = max(m, lum(env_field, UV + vec2(float(dx), float(dy)) * opx));
			}
		}
		e = max(e, m);
	}

	// x：这个点原始的声音亮度
	float x = clamp((e * bg_gain + band * edge_gain * e) * gain, 0.0, 1.0);
	float y = x;

	if (enable > 0.5) {
		float d = distance(UV * field_size, listener_px);
		float z = x * exp(-d / max(dist_scale, 0.001));
		if (z <= min_audible) {
			y = 0.0;
		} else {
			y = z + curve_a * z * (1.0 - z) * (curve_c - z);
			y = clamp(y, 0.0, 1.0);
		}
	}

	COLOR = vec4(tint.rgb * y, 1.0);
}
