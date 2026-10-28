shader_type canvas_item;
render_mode blend_add;

// 一个声源在"总的照亮显示"里贡献的那一层。
//
// 1) 场是这个声源自己跑的，遮罩（这一次声音铺多远）已经在**注入时**写进波的振幅里了。
// 2) 这一层再回答"我现在听得见它多少"：取场在**听者坐标**上的包络值，除以参考响度，
//    得到 0..1 的总闸门。所以——
//      · 墙后面的钟：波过不来 → 听者处能量为 0 → 这个声源的整个波根本不画
//      · 远处的钟：到达时已经衰减 → 画得很暗
//      · 自己发出的声音：发声瞬间听者就在源点上，闸门≈1；波离开耳朵后包络衰减，
//        整层跟着变暗 —— 这就是"回声"本身的衰减
//    用包络（B）而不是波前（R）来取样，是因为波本身是振荡的，取 R 会让整层跟着闪。
//
// 输出直接加进合成纹理（blend_add），所以"所有发声源叠加"就是把这层画 N 次。

uniform sampler2D env_field : filter_linear, repeat_disable;
uniform sampler2D band_tex : filter_nearest, repeat_disable;
uniform vec2 field_size = vec2(480.0, 270.0);
uniform vec2 listener_px = vec2(240.0, 238.0);   // 听者坐标（每帧跟随角色）
uniform float hear_ref = 0.05;      // 到达耳朵多响算"听得清"（> 它不再变亮）
uniform float bg_gain = 0.45;       // 空气里的行波强度（太亮就调小）
uniform float edge_gain = 4.00;     // 撞到表面时的高光倍数
uniform float gain = 1.0;           // 这个物体的总体音量
uniform float blur_px : hint_range(0.0, 4.0) = 1.20;
uniform vec4 tint = vec4(0.62, 0.82, 1.0, 1.0);

float lum(sampler2D tex, vec2 uv) {
	vec4 s = texture(tex, uv);
	return max(abs(s.r), s.b);
}

// 听者处"有多响"：包络值，取一点邻域最大值（听者可能贴在实体边上，那里场恒为 0）
float heard_level(vec2 uv) {
	vec2 px = 2.0 / field_size;
	float h = texture(env_field, uv).b;
	h = max(h, texture(env_field, uv + vec2(px.x, 0.0)).b);
	h = max(h, texture(env_field, uv - vec2(px.x, 0.0)).b);
	h = max(h, texture(env_field, uv + vec2(0.0, px.y)).b);
	h = max(h, texture(env_field, uv - vec2(0.0, px.y)).b);
	return h;
}

void fragment() {
	// ---- 听得见多少（整层共用一个闸门）----
	float hear = heard_level(listener_px / field_size);
	float gate = clamp(hear / max(hear_ref, 0.0001), 0.0, 1.0);

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

	float v = clamp((e * bg_gain + band * edge_gain * e) * gain * gate, 0.0, 1.0);
	// alpha 给 1：blend_add 是按 src.a 加权的，这里要的是"线性叠加"，
	// 这样图块读到的光强度才和场能量成正比。
	COLOR = vec4(tint.rgb * v, 1.0);
}
