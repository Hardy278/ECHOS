shader_type canvas_item;
// 必须关混合：canvas_item 默认按 COLOR.a 做 src_alpha 混合，A 只要小于 1
// 就会和背后的东西**混**在一起（几何值被稀释，透声 1.0 会变成 0.7）。
// 而这里 A = 0.7 是"实体标记"，是要原样写进去的数据，不是透明度。
render_mode blend_disabled;

// 实体在"世界几何"里的那一块：形状照抄实体自己的贴图，只写属性、不写外观。
//   R = 显现边缘（surface）  G = 折射率  B = 透声性  A = 0.7（实体标记）
//
// A 为什么不写 1：1.0 是图块用的"覆盖"。实体写 0.7，仍然是"有覆盖"（所有判
// a > 0.5 的地方都照旧），但 band.gdshader 能认出这一格是实体，于是**不在
// 实体和地形之间画介质交界边**——那里画一条边，看起来就是实体和地面裂了道缝。
//
// 规则和图块（geo_tile）完全一样：贴图透明的地方就是"没有东西"。
// 所以实体的声学形状 = 它长什么样，半透明/镂空的地方声音真的会钻进去。
//
// 外观不在这里：实体自己的 Sprite2D / AnimatedSprite2D 挂 tile_light 材质，
// 读的是同一张合成光，表面带、照亮、听者闸门全都自动一致。

uniform float surface = 1.0;
// 折射率是归一化过的通道值（0 = 空气，1 = IOR_MAX）。见 AcousticMedium.ior_to_channel。
uniform float ior_ch = 0.0;
uniform float transmit = 0.0;

void fragment() {
	if (COLOR.a < 0.5) {
		discard;                 // 贴图透明 = 空气
	}
	COLOR = vec4(surface, ior_ch, transmit, 0.7);
}
