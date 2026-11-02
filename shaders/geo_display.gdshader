shader_type canvas_item;

// 显示视口的那一块：把每个图块压成"显现纹理的值（show）"。
//
// 它和 geo_tile 是同一批镜像的两次绘制，只是取参数图里的不同通道：
//   geo_tile    取 RGB（surface / ior / transmit）+ A 一律写 1（覆盖）
//   geo_display 只取 A（show）
//
// 为什么要单独一遍：一层的图块可能来自多个图集源（前景层就混了 0/1/2），
// 而一层只有一份材质，绑一张小图覆盖不了全部源。用同一套镜像再渲染一张
// 480×270，源的问题就自动没了。
//
// 输出: R = show，A = 覆盖（1）。tile_light 用 A 判断"这里有没有显示数据"，
// 没有（比如实体）就退回 show = 1。

uniform sampler2D params_atlas : filter_nearest, repeat_disable;

void fragment() {
	if (COLOR.a < 0.5) {
		discard;                       // 图块透明的地方就是空气，不要写
	}
	float show = texture(params_atlas, UV).a;
	COLOR = vec4(show, show, show, 1.0);
}
