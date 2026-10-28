shader_type canvas_item;
render_mode blend_add;

// 把"所有声源叠加后的照亮"铺到主视口。
//
// 合成纹理已经是最终颜色（每个声源各自 tint + 听距衰减后加起来的），
// 这里只负责加法混合到画面上：空的地方是黑的，所以加法 = 直接显形。

uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform float gain = 1.0;

void fragment() {
	vec3 c = texture(light_tex, UV).rgb * gain;
	// 空气项提一点中段亮度：线性叠加看着会发灰
	c = c + c * c * 2.0;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
