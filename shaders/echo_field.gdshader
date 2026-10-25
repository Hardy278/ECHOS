shader_type canvas_item;
render_mode blend_disabled;

// 回响场合成。
// hits 纹理 RGBA8：R=能量  G=到达时间/max_t  B=反弹阶数(255=终止点)  A=有无命中
// 一份命中数据，两种读法：波前（时间窗口内的命中）与残影（各自从到达时刻开始衰减）。

uniform sampler2D hits : filter_nearest, repeat_disable;
uniform float now : hint_range(0.0, 100.0) = 99.0;   // 距本次发声的秒数
uniform float max_t : hint_range(0.1, 10.0) = 2.0;
uniform float win : hint_range(0.01, 1.0) = 0.12;    // 波前窗口
uniform float half_life : hint_range(0.1, 10.0) = 2.5;
uniform float front_gain : hint_range(0.0, 4.0) = 1.5;
uniform float head_gain : hint_range(0.0, 2.0) = 0.8;  // 一阶命中最亮
uniform float exposure : hint_range(0.1, 8.0) = 2.8;
uniform float soften : hint_range(0.0, 1.0) = 0.35;     // 单 texel 命中点的柔化量
uniform vec2 field_size = vec2(480.0, 270.0);          // ColorRect 没有贴图，取不到 TEXTURE_PIXEL_SIZE

const vec3 WARM = vec3(1.00, 0.86, 0.62);
const vec3 COLD = vec3(0.34, 0.62, 1.00);

// 柔化：按能量加权平均到达时间，避免把未命中像素的 t=0 混进来
// 两圈采样：内圈压住单 texel 的硬点，外圈抹掉固定扇面留下的粒度
void sample_soft(vec2 uv, out float e, out float tg, out float flags) {
	vec2 px = 1.0 / field_size;
	vec4 c = texture(hits, uv);
	vec4 l1 = texture(hits, uv - vec2(px.x, 0.0));
	vec4 r1 = texture(hits, uv + vec2(px.x, 0.0));
	vec4 d1 = texture(hits, uv - vec2(0.0, px.y));
	vec4 u1 = texture(hits, uv + vec2(0.0, px.y));
	vec4 l2 = texture(hits, uv - vec2(px.x * 2.0, 0.0));
	vec4 r2 = texture(hits, uv + vec2(px.x * 2.0, 0.0));
	vec4 d2 = texture(hits, uv - vec2(0.0, px.y * 2.0));
	vec4 u2 = texture(hits, uv + vec2(0.0, px.y * 2.0));

	float wc = 0.30;
	float w1 = 0.13 * soften;
	float w2 = 0.055 * soften;

	float es = c.r * wc
		+ (l1.r + r1.r + d1.r + u1.r) * w1
		+ (l2.r + r2.r + d2.r + u2.r) * w2;
	float et = c.r * c.g * wc
		+ (l1.r * l1.g + r1.r * r1.g + d1.r * d1.g + u1.r * u1.g) * w1
		+ (l2.r * l2.g + r2.r * r2.g + d2.r * d2.g + u2.r * u2.g) * w2;
	float ws = wc + 4.0 * (w1 + w2);

	e = es / ws * 1.6;          // 归一化回峰值亮度
	tg = es > 1e-4 ? et / es : 0.0;
	flags = c.b * 255.0;
}

void fragment() {
	float e;
	float tg;
	float flags;
	sample_soft(UV, e, tg, flags);

	float is_term = step(200.0, flags);
	float bounces = floor(flags / 64.0 + 0.5);

	float t = tg * max_t;

	// 残影：从各自到达时刻开始按半衰期衰减（pow(k, dt)，帧率无关）
	float k = pow(0.5, 1.0 / half_life);
	float since = max(now - t, 0.0);
	float decay = pow(k, since);
	float arrived = step(t, now);

	// 波前：只有落在当前时间窗口内的命中才点亮
	float front = 1.0 - smoothstep(0.0, win, abs(now - t));

	float v = e * (arrived * decay + front * front_gain);
	v *= 1.0 - 0.18 * bounces;          // 高阶回弹稍暗，帮助读"第一圈 vs 后续圈"
	v *= mix(1.0, 0.45, is_term);       // 终止点：冷色、极暗，且不会有后续波前
	v *= exposure;

	vec3 col = mix(WARM, COLD, is_term);
	float g = v + v * v * head_gain;    // 轻 bloom：亮部溢出
	COLOR = vec4(col * g, 1.0);
}
