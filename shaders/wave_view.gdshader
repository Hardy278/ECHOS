shader_type canvas_item;
render_mode blend_add;

// 多声源合成。
//
// 距离衰减锚在**听者**（角色当前位置），不是发声点：
// 场里只有波真正到过的位置才有能量，移动遮罩只是改变"我现在能听见哪一片"，
// 不会凭空造出信息。所以听觉半径跟着人走是安全且直观的。
//
// 方块感来自跨步步长（STRIDE）：波只能在相隔 STRIDE texel 的格点上交换。
// 提高缓冲分辨率没用——为保持波速必须同步放大 stride，格点的世界尺寸不变。
// 所以背景行波单独做一次小半径模糊，而物体边缘走另一条路保持锐利。

uniform sampler2D field_hb : filter_linear, repeat_disable;
uniform sampler2D field_land : filter_linear, repeat_disable;
uniform sampler2D field_shout : filter_linear, repeat_disable;
uniform sampler2D mat_tex : filter_nearest, repeat_disable;
uniform sampler2D band_tex : filter_nearest, repeat_disable;
uniform vec2 field_size = vec2(480.0, 270.0);

uniform vec2 listener_px = vec2(240.0, 238.0);      // 听者位置（每帧跟随角色）
uniform vec2 rf_hb = vec2(70.0, 2.40);              // x=射程 y=衰减曲线
uniform vec2 rf_land = vec2(127.0, 1.90);
uniform vec2 rf_shout = vec2(280.0, 1.60);

uniform float bg_gain = 1.15;
uniform float edge_gain = 4.00;
uniform float bg_blur : hint_range(0.0, 4.0) = 1.20;
uniform vec3 bg_weight = vec3(1.0, 1.0, 0.35);      // 各声源对行波的贡献

float fall(float d, vec2 rf) {
	return pow(clamp(1.0 - d / rf.x, 0.0, 1.0), rf.y);
}

// 背景用：五点模糊，只取 |u|
float bg_field(sampler2D tex, vec2 uv, vec2 px) {
	float s = abs(texture(tex, uv).r) * 0.36;
	s += abs(texture(tex, uv + vec2(px.x, 0.0)).r) * 0.16;
	s += abs(texture(tex, uv - vec2(px.x, 0.0)).r) * 0.16;
	s += abs(texture(tex, uv + vec2(0.0, px.y)).r) * 0.16;
	s += abs(texture(tex, uv - vec2(0.0, px.y)).r) * 0.16;
	return s;
}

void fragment() {
	vec2 px = (1.0 / field_size) * bg_blur;

	float bh = bg_field(field_hb, UV, px);
	float bl = bg_field(field_land, UV, px);
	float bs = bg_field(field_shout, UV, px);

	float eh = texture(field_hb, UV).b;
	float el = texture(field_land, UV).b;
	float es = texture(field_shout, UV).b;

	float band = texture(band_tex, UV).r;
	float absorb = texture(mat_tex, UV).g;

	vec2 pos = UV * field_size;
	float d = distance(pos, listener_px);
	float fh = fall(d, rf_hb);
	float fl = fall(d, rf_land);
	float fs = fall(d, rf_shout);

	float bg = (bh * fh * bg_weight.x
		+ bl * fl * bg_weight.y
		+ bs * fs * bg_weight.z) * bg_gain;
	float edge = band * edge_gain * max(eh * fh, max(el * fl, es * fs));

	float v = clamp(bg + edge, 0.0, 1.0);

	vec3 col = mix(vec3(1.00, 0.86, 0.62), vec3(0.34, 0.62, 1.00), absorb);
	if (band > 0.5) {
		col = mix(col, vec3(1.0, 0.96, 0.88), 0.35);
	}
	float g = v + v * v * 2.0;
	COLOR = vec4(col * g, g);
}
