shader_type canvas_item;

// 显示视口的那一块：把每个图块压成"显现纹理（show）+ 吸声（alpha）"。
//
// 它和 geo_tile 是同一批镜像的两次绘制，只是取不同的参数图：
//   geo_tile    取 (surface, ior, transmit, 1)
//   geo_display 取 (show,    alpha, 0,       1)
//
// 为什么要单独一遍：一层的图块可能来自多个图集源（前景层就混了 0/1/2），
// 而一层只有一份材质，绑一张小图覆盖不了全部源。用同一套镜像再渲染一张
// 480×270，源的问题就自动没了。
//
// 输出: R = show，G = alpha，A = 覆盖（1）。
//   · tile_light 用 A 判断"这里有没有显示数据"，没有（比如实体）就退回 show = 1，读 R。
//   · wave_step_fb 每步读 G 当体积吸声系数。

uniform sampler2D params_atlas : filter_nearest, repeat_disable;

void fragment() {
	if (COLOR.a < 0.5) {
		discard;                       // 图块透明的地方就是空气，不要写
	}
	vec4 p = texture(params_atlas, UV);
	COLOR = vec4(p.r, p.g, 0.0, 1.0);
}
