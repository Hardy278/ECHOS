shader_type canvas_item;

// 把每个图块压成"属性 + 覆盖"，画进世界几何纹理（EchoWorld 每帧现画的那张）。
//   R = 吸声性（这块图块自己画不画）
//   G = 绝对折射率（1 = 空气，越大声速越慢）
//   B = 透声性（声音能不能穿过去）
//   A = 覆盖（这一格有图块）
//
// 属性是"逐图块"的，可着色器读不到 TileData，所以用一张和**图集等大**的参数图：
// TileMapLayer 里 UV 就是图集纹理坐标，直接按同一套 UV 采样即可，不用算 tile 下标。
// 参数图在世界几何那边由图集的 custom data 生成（见 wave_geometry.gd）。
//
// 图层是后景先画、前景后画，blend_mix + 不透明写入 = 前景覆盖后景。

uniform sampler2D params_atlas : filter_nearest, repeat_disable;

void fragment() {
	if (COLOR.a < 0.5) {
		discard;                       // 图块透明的地方就是空气，不要写
	}
	vec4 p = texture(params_atlas, UV);
	COLOR = vec4(p.r, p.g, p.b, 1.0);
}
