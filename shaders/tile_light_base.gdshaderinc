// 图块受光的共享主体。
//
// 所有"被合成光照亮"的图块都走这一段，用 #include 引入：
//   · tile_light.gdshader         —— 默认，只让图案跟着光走
//   · tile_light_normal.gdshader  —— 额外按表面朝向称量接到多少声能
// 两份各自只写最后一行，所以没有第二份复制品。
//
// **注意**：这里不能有 shader_type；注释只能用 //（用 ## 会让整个 shader 编译失败）。

uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform sampler2D geo_tex : filter_nearest, repeat_disable;
// 每块砖"显现纹理"的值（R）+ 覆盖（A）。和 geo_tex 一样按世界 UV 采样。
uniform sampler2D display_tex : filter_nearest, repeat_disable;
// 渗进实体内部的那一份光（低分辨率、线性过滤）。
uniform sampler2D bleed_tex : filter_linear, repeat_disable;
uniform float bleed_gain = 1.0;
uniform float bleed_tint = 4.0;
uniform vec2 field_size = vec2(480.0, 270.0);

uniform float gain = 1.0;
uniform float light_gain = 1.0;
uniform float floor_gain = 0.0;

// 声呐外观：所有图块共用一个色，但保留贴图的图案（砖缝、草叶的形状）
uniform vec3 flat_color = vec3(0.78, 0.86, 1.0);
uniform float art_gain = 1.7;
// 图案的地板：贴图里纯黑的地方（不透明、也是图案的一部分）不该被画成纯黑
uniform float art_floor : hint_range(0.0, 1.0) = 0.35;
uniform float silhouette : hint_range(0.0, 1.0) = 1.0;
// 1 = 只画在没有几何的地方（纯画面层用，会被前景覆盖镂空）
uniform float behind_only = 0.0;

varying vec2 world_pos;

void vertex() {
	// VERTEX.xy：写 .xy 而不是直接塞 VERTEX。
	// .gdshaderinc 被编辑器单独校验时没有 shader_type 上下文，VERTEX 会被当成 vec3，
	// 于是 vec4(VERTEX, 0, 1) 变成 5 个分量报错；.xy 在 vec2 / vec3 两种上下文里都成立。
	world_pos = (MODEL_MATRIX * vec4(VERTEX.xy, 0.0, 1.0)).xy;
}

// 一次算完所有共享量：
//   col  本体颜色（flat_color，或者在渗光处偏成光的颜色）
//   art  图案亮度（0..1，调用者可以再乘东西）
//   vis  不透明度（受光强度 × 层倍率 × 显现纹理 × 镂空）
void tile_light_core(vec3 albedo, out vec3 col, out float art, out float vis) {
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
	float a = clamp(dot(albedo, vec3(0.299, 0.587, 0.114)) * art_gain, 0.0, 1.0);
	a = mix(art_floor, 1.0, a);   // 黑 = 最暗的图案，不是"没有"

	// 本体颜色：默认是 cold 的 flat_color（"声音只告诉你形状"）。
	// 但只要这一带有渗进来的光，就往**光的颜色**偏。
	col = flat_color;
	if (bl > 0.001) {
		col = mix(flat_color, bleed / bl, clamp(bl * bleed_tint, 0.0, 1.0));
	}

	// 纯画面层：被前景的覆盖镂空（实体写的 0.7 也算覆盖，所以草和门底下同样让开）
	float mask = 1.0;
	if (behind_only > 0.5) {
		mask = 1.0 - step(0.5, texture(geo_tex, uv).a);
	}

	art = a;
	vis = v * silhouette * show * light_gain * mask;
}
