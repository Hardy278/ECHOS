shader_type canvas_item;

// 图块被"总的照亮显示"照亮。
//
// 世界本身是黑的：只有波真正到过、并且落在你听力范围内的图块才显形。
// light_tex 是所有声源叠加后的光（每个声源用自己的场、自己的听距衰减、自己的音色），
// 所以这里不再有几个"声源槽"，也不关心场上到底有几个声源。
//
// 主体逻辑在 tile_light_base.gdshaderinc —— 和带法线的那一版共用同一份，
// 这里只负责最后一行。
//
// 注意：canvas_item 里 UV 是图集的纹理坐标，不是世界坐标，所以位置要用顶点阶段的
// MODEL_MATRIX 算，不能拿 UV 去采样光。

#include "res://shaders/tile_light_base.gdshaderinc"

void fragment() {
	vec3 col;
	float art;
	float vis;
	tile_light_core(COLOR.rgb, col, art, vis);
	COLOR = vec4(col * art, COLOR.a * vis);
}
