shader_type canvas_item;

// 实体在"显示纹理"里的那一块：只为了写吸声 α（G 通道）。
// 和 geo_body 是同一批镜子的两次绘制，只是属性图不同：
//   geo_body       写几何: (surface, ior, transmit, 1)
//   geo_body_alpha 写显示: (1,       α,   0,        1)
//
// R 写 1 = 退回"没有显示数据"时的默认 show（1），于是这段不改变任何外观；
// A 写 1 是覆盖标记，和瓦片的显示镜像一致。

uniform float alpha = 0.0;

void fragment() {
	if (COLOR.a < 0.5) {
		discard;                 // 贴图透明 = 空气
	}
	COLOR = vec4(1.0, alpha, 0.0, 1.0);
}
