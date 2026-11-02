shader_type canvas_item;

// 光渗：把"总的照亮"往四周扩散，让撞在表面上的光渗进实体内部。
//
// 为什么需要它：不透声的格子里声场恒为 0（wave_step_fb 里 un *= (1-block)），
// 所以砖块内部一点光都没有。看得见的只有 band 那 2 texel 的一圈，
// 于是几块砖宽的凸起会变成"中空的描边"。
//
// 做法：在低分辨率上跑（BLEED_SIZE，一个 texel = 8 个世界单位）。
// 每帧一步：取上一步的四邻域/对角最大值、乘衰减，再和这一帧的光取 max。
//
// **保留 RGB**：渗进来的光是"声源的颜色"，不是亮度。
// 之前的版本用 dot(...) 压成标量，颜色就在第一步丢了，墙体只能显示灰色。
//
// 注意：Godot 着色器不允许在 fragment() 里 return，所以用 if/else 分支。

uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform sampler2D src_tex : filter_linear, repeat_disable;
// 低分辨率缓冲的尺寸（不是源纹理的尺寸）
uniform vec2 low_size = vec2(60.0, 34.0);
// 每步的衰减：0.9 渗得很远，0.4 只在表面附近亮
uniform float decay = 0.62;
// 1 = 这一步输出全黑（换房间时用来清场）
uniform float reset = 0.0;

vec3 prev_at(vec2 uv) {
	return texture(src_tex, uv).rgb;
}

void fragment() {
	vec2 px = 1.0 / low_size;
	vec3 m = vec3(0.0);

	if (reset > 0.5) {
		m = vec3(0.0);
	} else {
		// 中心自己**也要乘 decay**：不乘的话缓冲永远保持自己的值，
		// 只往外扩、不往下掉——声音停了画面还是亮的。
		m = prev_at(UV) * decay;
		m = max(m, prev_at(UV + vec2(px.x, 0.0)) * decay);
		m = max(m, prev_at(UV - vec2(px.x, 0.0)) * decay);
		m = max(m, prev_at(UV + vec2(0.0, px.y)) * decay);
		m = max(m, prev_at(UV - vec2(0.0, px.y)) * decay);
		// 对角也算，不然扩散出来是方的
		float d = decay * 0.7071;
		m = max(m, prev_at(UV + vec2(px.x, px.y)) * d);
		m = max(m, prev_at(UV + vec2(-px.x, px.y)) * d);
		m = max(m, prev_at(UV + vec2(px.x, -px.y)) * d);
		m = max(m, prev_at(UV + vec2(-px.x, -px.y)) * d);

		// 这一帧的光要一直注进来，否则几帧后就被衰减吃光了
		m = max(m, texture(light_tex, UV).rgb);
	}

	COLOR = vec4(m, 1.0);
}
