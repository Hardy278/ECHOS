shader_type canvas_item;

// 图块的"被回响场照亮"。
//
// 世界本身是黑的：只有波真正到过、并且落在你听力范围内的图块才显形。
// 亮度取三路合成场：
//   max(|u|, 包络 B) —— |u| 是正在扫过的波前，B 是波走过之后的余晖。
// 距离衰减锚在听者身上，和 wave_view 用同一套曲线。
//
// 注意：canvas_item 里 UV 是图集的纹理坐标，不是世界坐标，所以位置要用顶点阶段
// 的 MODEL_MATRIX 算，不能拿 UV 去采场。

uniform sampler2D field_hb : filter_linear, repeat_disable;
uniform sampler2D field_land : filter_linear, repeat_disable;
uniform sampler2D field_shout : filter_linear, repeat_disable;
uniform vec2 field_size = vec2(480.0, 270.0);

uniform vec2 listener_px = vec2(240.0, 238.0);
uniform vec2 rf_hb = vec2(70.0, 2.40);
uniform vec2 rf_land = vec2(127.0, 1.90);
uniform vec2 rf_shout = vec2(280.0, 1.60);

uniform float gain = 4.0;
uniform float blur_px : hint_range(0.0, 4.0) = 1.20;
uniform float layer_gain = 1.0;      // 后景层压暗：0.55 之类
uniform float floor_gain = 0.0;      // 全黑时的底噪；要"彻底黑"就保持 0

varying vec2 world_pos;

float fall(float d, vec2 rf) {
	return pow(clamp(1.0 - d / rf.x, 0.0, 1.0), rf.y);
}

float lum(sampler2D tex, vec2 uv) {
	vec4 s = texture(tex, uv);
	return max(abs(s.r), s.b);
}

float env_field(sampler2D tex, vec2 uv, vec2 px) {
	float s = lum(tex, uv) * 0.36;
	s += lum(tex, uv + vec2(px.x, 0.0)) * 0.16;
	s += lum(tex, uv - vec2(px.x, 0.0)) * 0.16;
	s += lum(tex, uv + vec2(0.0, px.y)) * 0.16;
	s += lum(tex, uv - vec2(0.0, px.y)) * 0.16;
	return s;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 uv = world_pos / field_size;
	vec2 px = (1.0 / field_size) * blur_px;

	float d = distance(world_pos, listener_px);
	float fh = fall(d, rf_hb);
	float fl = fall(d, rf_land);
	float fs = fall(d, rf_shout);

	float l = env_field(field_hb, uv, px) * fh
		+ env_field(field_land, uv, px) * fl
		+ env_field(field_shout, uv, px) * fs;

	float v = clamp(l * gain * layer_gain + floor_gain, 0.0, 1.0);
	COLOR.rgb *= v;
	COLOR.a *= v;
}
