shader_type canvas_item;

// 内侧表面带：有覆盖的格子里，到最近的空气 texel 的切比雪夫距离 <= band_px 的那些格子。
// 严格 1 个 tile 像素厚。输出：R = 表面带。

uniform sampler2D geo_tex : filter_nearest, repeat_disable;
uniform vec2 field_size = vec2(480.0, 270.0);
uniform int band_px = 2;

const int MAX_BAND_PX = 4;

void fragment() {
	vec2 px = 1.0 / field_size;
	float cov = step(0.5, texture(geo_tex, UV).a);
	float near_air = 0.0;
	for (int dy = -MAX_BAND_PX; dy <= MAX_BAND_PX; dy++) {
		if (dy < -band_px || dy > band_px) {
			continue;
		}
		for (int dx = -MAX_BAND_PX; dx <= MAX_BAND_PX; dx++) {
			if (dx < -band_px || dx > band_px) {
				continue;
			}
			if (texture(geo_tex, UV + vec2(float(dx), float(dy)) * px).a < 0.5) {
				near_air = 1.0;
			}
		}
	}
	float b = cov * near_air;
	COLOR = vec4(b, b, b, 1.0);
}
