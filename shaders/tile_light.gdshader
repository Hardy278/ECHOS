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
uniform vec2 field_size = vec2(480.0, 270.0);

uniform float gain = 1.0;            // 图块对光的响应
uniform float layer_gain = 1.0;      // 后景层压暗：0.55 之类
uniform float floor_gain = 0.0;      // 全黑时的底噪；要"彻底黑"就保持 0

// 声呐外观：所有图块共用一个色，但保留贴图的**图案**（砖缝、草叶的形状）
uniform vec3 flat_color = vec3(0.78, 0.86, 1.0);
uniform float art_gain = 1.7;                            // 图案对比提升
uniform float silhouette : hint_range(0.0, 1.0) = 1.0;   // 0 = 只留描边，不画图块主体
uniform float absorb_gain = 1.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 uv = world_pos / field_size;

	float l = dot(texture(light_tex, uv).rgb, vec3(0.299, 0.587, 0.114));

	// 吸声性：这块图块"能不能渲染本体"。1 = 完全不留形（吸声到底）
	vec4 g = texture(geo_tex, uv);
	float absorb = g.r;
	// 折射率 > 1 的介质，本体也要画（不然动画帧看不见），
	// 但压暗一点，读起来像"看进水里"。空气 = 1.0，所以普通图块不会被画。
	float body = g.g > 1.01 ? 0.6 : 1.0;
	float v = clamp(l * gain * layer_gain * (1.0 - absorb * absorb_gain) + floor_gain, 0.0, 1.0);

	// 声呐式：保留贴图的**图案**，但抹掉原色——声音只告诉你形状和纹理，
	// 不告诉你它本来是砖红还是草绿。
	float art = clamp(dot(COLOR.rgb, vec3(0.299, 0.587, 0.114)) * art_gain, 0.0, 1.0);
	COLOR = vec4(flat_color * art, COLOR.a * v * silhouette * body);
}
