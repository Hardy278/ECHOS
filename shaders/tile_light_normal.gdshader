shader_type canvas_item;

// 和 tile_light 共用同一份主体，多一条：**按表面朝向称量接到多少声能**。
//
// N 按图集 UV 采（所以法线图必须和 albedo 同布局、同尺寸、同格栅）；
// L 按世界 UV 从合成光里现算 —— 就是声场的能流方向。
//
// 只画"看得见之后长什么样"，不参与可见性判定：
// shade 乘在 art 上，绝不乘 vis。乘 vis 的话暗面会整块消失。

#include "res://shaders/tile_light_base.gdshaderinc"

uniform sampler2D normal_tex : filter_nearest, repeat_disable;
// 0 = 完全平（关掉），1 = 满对比
uniform float normal_strength : hint_range(0.0, 1.0) = 0.0;
// 中央差分的步长（texel）。
// 波每步走 4 texel、最短波长约 8~16，±1 会跟着瞬时波形抖；
// 取大一点相当于在算"宏观能流方向"，这也是它不需要额外低分辨率缓冲的原因。
uniform float normal_step = 6.0;

float lum_at(vec2 uv) {
	return dot(texture(light_tex, uv).rgb, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec3 col;
	float art;
	float vis;
	tile_light_core(COLOR.rgb, col, art, vis);

	vec3 n = texture(normal_tex, UV).rgb * 2.0 - 1.0;

	// L = 光变强的方向 = 声音来的方向（+∇，和 source_view 里"看得见多少"同源）
	vec2 uv = world_pos / field_size;
	vec2 px = vec2(normal_step) / field_size;
	vec2 g = vec2(
			lum_at(uv + vec2(px.x, 0.0)) - lum_at(uv - vec2(px.x, 0.0)),
			lum_at(uv + vec2(0.0, px.y)) - lum_at(uv - vec2(0.0, px.y)));
	float m = length(g);

	// 没有方向（全黑，或者被均匀照亮）→ 不施加明暗，退回平。
	// 不这么做的话暗部会整片乱闪。
	float shade = 1.0;
	if (m > 1e-5) {
		float d = dot(n.xy, g / m);
		shade = mix(1.0, 0.5 + 0.5 * d, normal_strength);
	}

	art *= shade;
	COLOR = vec4(col * art, COLOR.a * vis);
}
