shader_type canvas_item;

// 实体的显形：只在它自己的声场里显形，并且按"听者听到多少"整体压暗。
// 采样点取实体周围一圈的最大值：实体可能压在实体图块上，而实体内部的场恒为 0。

uniform sampler2D env_field : filter_linear, repeat_disable;
uniform vec2 field_size = vec2(480.0, 270.0);
uniform vec2 source_px = vec2(0.0);
uniform vec2 listener_px = vec2(240.0, 238.0);
uniform float hear_ref = 0.05;      // 和 source_view 一致：到耳朵多响算"听得清"
uniform float gain = 3.0;
uniform vec4 tint = vec4(1.0, 0.82, 0.45, 1.0);

float lum(sampler2D t, vec2 uv) {
	vec4 s = texture(t, uv);
	return max(abs(s.r), s.b);
}

void fragment() {
	// 实体自己身上有多响
	vec2 uv = source_px / field_size;
	vec2 px = 1.0 / field_size;
	float e = lum(env_field, uv);
	e = max(e, lum(env_field, uv + vec2(px.x * 2.0, 0.0)));
	e = max(e, lum(env_field, uv - vec2(px.x * 2.0, 0.0)));
	e = max(e, lum(env_field, uv + vec2(0.0, px.y * 2.0)));
	e = max(e, lum(env_field, uv - vec2(0.0, px.y * 2.0)));

	// 它到听者耳朵有多响（整层闸门）
	float heard = texture(env_field, listener_px / field_size).b;
	float gate = clamp(heard / max(hear_ref, 0.0001), 0.0, 1.0);

	float v = clamp(e * gain, 0.0, 1.0) * gate;
	COLOR = vec4(tint.rgb, v);
}
