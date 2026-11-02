shader_type canvas_item;

// 图块被"总的照亮显示"照亮。
//
// 世界本身是黑的：只有波真正到过、并且落在你听力范围内的图块才显形。
// light_tex 是所有声源叠加后的光（每个声源用自己的场、自己的听距衰减、自己的音色），
// 所以这里不再有几个"声源槽"，也不关心场上到底有几个声源。
//
// 注意：canvas_item 里 UV 是图集的纹理坐标，不是世界坐标，所以位置要用顶点阶段的
// MODEL_MATRIX 算，不能拿 UV 去采样光。

uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform sampler2D geo_tex : filter_nearest, repeat_disable;
// 每块砖"显现纹理"的值（R）+ 覆盖（A）。和 geo_tex 一样按世界 UV 采样。
uniform sampler2D display_tex : filter_nearest, repeat_disable;
uniform vec2 field_size = vec2(480.0, 270.0);

uniform float gain = 1.0;            // 图块对光的响应
uniform float floor_gain = 0.0;      // 全黑时的底噪；要"彻底黑"就保持 0

// 声呐外观：所有图块共用一个色，但保留贴图的**图案**（砖缝、草叶的形状）
uniform vec3 flat_color = vec3(0.78, 0.86, 1.0);
uniform float art_gain = 1.7;                            // 图案对比提升
// 图案的地板：贴图里纯黑的地方（不透明、也是图案的一部分）不该被画成纯黑，
// 否则在纯黑背景上看起来就是个"洞"。这个值就是最暗那一档的亮度。
uniform float art_floor : hint_range(0.0, 1.0) = 0.35;
uniform float silhouette : hint_range(0.0, 1.0) = 1.0;   // 0 = 只留描边，不画图块主体

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 uv = world_pos / field_size;

	float l = dot(texture(light_tex, uv).rgb, vec3(0.299, 0.587, 0.114));

	// 本体不透明度只跟"这个点有多亮"有关。
	// R 通道（surface）不在这里用——它管的是"出不出边缘高光"，交给 band 那边。
	float v = clamp(l * gain + floor_gain, 0.0, 1.0);

	// 显现纹理：0 = 只留边缘（本体完全不画），1 = 按光强正常显示。
	// 显示纹理在空气处 A = 0，那是"这里没有显示数据"（实体就是这种情况），
	// 必须退回 1，否则所有实体都会消失。
	vec4 d = texture(display_tex, uv);
	float show = d.a > 0.5 ? d.r : 1.0;

	// 声呐式：保留贴图的**图案**，但抹掉原色——声音只告诉你形状和纹理，
	// 不告诉你它本来是砖红还是草绿。
	float art = clamp(dot(COLOR.rgb, vec3(0.299, 0.587, 0.114)) * art_gain, 0.0, 1.0);
	art = mix(art_floor, 1.0, art);   // 黑 = 最暗的图案，不是"没有"
	COLOR = vec4(flat_color * art, COLOR.a * v * silhouette * show);
}
