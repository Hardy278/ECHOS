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
// 渗进实体内部的那一份光（低分辨率、线性过滤）。
// 不透声的格子里声场恒为 0，没有它的话砖块内部永远是黑的。
uniform sampler2D bleed_tex : filter_linear, repeat_disable;
uniform float bleed_gain = 1.0;      // 渗光强度倍率
// 渗光给本体染色的强度：0 = 永远是 flat_color（灰蓝），越大越跟着光走
uniform float bleed_tint = 4.0;
uniform vec2 field_size = vec2(480.0, 270.0);

uniform float gain = 1.0;            // 图块对光的响应
// 这一层的默认显示倍率（来自层表）。只作用在图块上——实体有自己的材质。
// 注意它乘在**clamp 之后**的 alpha 上，所以它改的是"最多能有多不透明"，
// 不是"多容易饱和"。
uniform float light_gain = 1.0;
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

	// 渗光：砖块内部本来是 0（不透声 → 场为 0），靠这一项才有"内部亮起来"。
	// 保留颜色——渗进来的光是**声源的颜色**，不是亮度。
	vec3 bleed = texture(bleed_tex, uv).rgb * bleed_gain;
	float bl = max(max(bleed.r, bleed.g), bleed.b);

	float l = dot(texture(light_tex, uv).rgb, vec3(0.299, 0.587, 0.114));
	l = max(l, bl);

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

	// 本体颜色：默认是 cold 的 flat_color（"声音只告诉你形状"）。
	// 但只要这一带有渗进来的光，就往**光的颜色**偏——于是墙内部会显示成
	// 照亮它的那盏声源的颜色（玩家是暖黄、钟是橙），而不是一片灰。
	vec3 col = flat_color;
	if (bl > 0.001) {
		col = mix(flat_color, bleed / bl, clamp(bl * bleed_tint, 0.0, 1.0));
	}

	COLOR = vec4(col * art, COLOR.a * v * silhouette * show * light_gain);
}
