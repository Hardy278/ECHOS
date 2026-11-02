shader_type canvas_item;

// 实体在"世界几何"里的那一块：形状照抄实体自己的贴图，只写属性、不写外观。
//   R = 显现边缘（surface）  G = 折射率  B = 透声性  A = 覆盖
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
	COLOR = vec4(surface, ior_ch, transmit, 1.0);
}
