#[compute]
#version 450

// ECHOS 声场的一个时间步（compute 后端）。
//
// 和 shaders/viewport/wave_step_fb.gdshader 是同一个方程、同一套物理量，区别只在数据通道：
// 那边是 ping-pong 的 SubViewport 纹理，这边是 RD 存储纹理，用 imageLoad / imageStore
// 按整数 texel 读写。所以没有 UV 舍入，也没有每步一次的管线开销。
//
// 通道：R = u(t)，G = u(t-1)，B = 包络（残影）
//
// 一个 dispatch 只推进一步。多步由 CPU 连续 dispatch，中间 compute_list_add_barrier()。
//
// 几何纹理（set 1 的 geo_tex）通道和 canvas 版一致：
//   R = surface  G = ior  B = transmit  A = 覆盖
// alpha_tex 是显示纹理，G = 体积吸声 α。

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba16f) uniform readonly image2D src_img;
layout(set = 0, binding = 1, rgba16f) uniform writeonly image2D dst_img;

layout(set = 1, binding = 0) uniform sampler2D geo_tex;
layout(set = 1, binding = 1) uniform sampler2D alpha_tex;

layout(push_constant, std430) uniform Params {
	vec2 field_size;
	vec2 emit_px;
	vec4 sponge_edges;
	float inject;
	float inject_r;
	float damp;
	float env_decay;
	float cfl;
	float stride;
	float ior_max;
	float hf_damp;
	float absorb_gain;
	float sponge_w;
	float sponge_absorb;
} pc;

ivec2 size_px() {
	return ivec2(pc.field_size);
}

ivec2 clamp_px(ivec2 q) {
	return clamp(q, ivec2(0), size_px() - ivec2(1));
}

vec4 geo_at(ivec2 q) {
	return texelFetch(geo_tex, clamp_px(q), 0);
}

// 这一格对波的"阻挡度"：1 = 完全挡，0 = 空气 / 水 / 完全透声。
float blockage(ivec2 q) {
	vec4 m = geo_at(q);
	if (m.a < 0.5) {
		return 0.0;
	}
	return clamp(1.0 - m.b, 0.0, 1.0);
}

bool opaque_q(ivec2 q) {
	return blockage(q) > 0.5;
}

// 这一格在吸声层里有多深：0 = 不在吸声层，1 = 紧贴开口那条边。
// 只对空气格生效（调用处乘 (1 - block)），墙那半边仍然自己反射。
float sponge(ivec2 q) {
	vec2 e = vec2(q);
	float d = 1e9;
	if (pc.sponge_edges.x > 0.5) { d = min(d, e.x); }
	if (pc.sponge_edges.y > 0.5) { d = min(d, pc.field_size.x - e.x); }
	if (pc.sponge_edges.z > 0.5) { d = min(d, e.y); }
	if (pc.sponge_edges.w > 0.5) { d = min(d, pc.field_size.y - e.y); }
	if (d >= pc.sponge_w) {
		return 0.0;
	}
	float t = clamp(d / pc.sponge_w, 0.0, 1.0);
	return (1.0 - t) * (1.0 - t);
}

// 从源点到当前 texel 的粗略视线检查：中间有实体就不注入。
// 没有这一步，高斯注入会直接渗到墙背面，看起来像声音"穿墙"了。
bool clear_path(ivec2 a, ivec2 b) {
	for (int k = 2; k <= 8; k++) {
		vec2 t = mix(vec2(a), vec2(b), float(k) / 8.0);
		if (opaque_q(ivec2(t))) {
			return false;
		}
	}
	return true;
}

// 邻居取样。block = 1 时零梯度（Neumann）全反射；block = 0 时正常取邻居；
// 中间值按比例混合 —— 这就是"透声"。
// 和 canvas 版一样，半步中点也要查材质：跨步步长可能大于薄墙厚度。
float nb(ivec2 q, ivec2 mid, float center) {
	float block = max(blockage(q), blockage(mid));
	return mix(imageLoad(src_img, clamp_px(q)).r, center, block);
}

void main() {
	ivec2 q = ivec2(gl_GlobalInvocationID.xy);
	if (q.x >= size_px().x || q.y >= size_px().y) {
		return;
	}

	vec4 s = imageLoad(src_img, q);
	float u = s.r;
	float um1 = s.g;

	int st = int(pc.stride);
	float l = nb(q + ivec2(-st, 0), q + ivec2(-st / 2, 0), u);
	float r = nb(q + ivec2(st, 0), q + ivec2(st / 2, 0), u);
	float d = nb(q + ivec2(0, -st), q + ivec2(0, -st / 2), u);
	float up = nb(q + ivec2(0, st), q + ivec2(0, st / 2), u);

	float lap = l + r + d + up - 4.0 * u;

	vec4 m = geo_at(q);
	// 介质：G 是归一化过的绝对折射率（0 = 空气，1 = ior_max），波速 = 空气速 / n。
	float n = max(1.0 + clamp(m.g, 0.0, 1.0) * (pc.ior_max - 1.0), 1.0);
	float local_cfl = pc.cfl / (n * n);
	float un = 2.0 * u - um1 + local_cfl * lap;

	float navg = (l + r + d + up) * 0.25;
	un = mix(un, navg, pc.hf_damp);

	float block = (m.a > 0.5) ? clamp(1.0 - m.b, 0.0, 1.0) : 0.0;
	un *= (1.0 - block);
	// 吸声：穿过这一格内部时被吃掉的那一份（透声但吸声的材质：厚草、雾、水）
	un *= 1.0 - texelFetch(alpha_tex, q, 0).g * pc.absorb_gain;
	un *= pc.damp;
	// 开口方向的吸声层：走到房间边缘的能量就散了，不会掉头回来
	un *= 1.0 - sponge(q) * pc.sponge_absorb * (1.0 - block);
	un = clamp(un, -1.0, 1.0);

	// 注入：被墙挡住的地方不注入（高斯尾巴不能越过实体）
	if (pc.inject > 0.0001) {
		float dsrc = distance(vec2(q) + vec2(0.5), pc.emit_px);
		float g = exp(-(dsrc * dsrc) / (pc.inject_r * pc.inject_r));
		if (g > 0.002 && !clear_path(ivec2(pc.emit_px), q)) {
			g = 0.0;
		}
		un += pc.inject * g;
	}

	float env = max(abs(un), s.b * pc.env_decay);
	imageStore(dst_img, q, vec4(un, u, clamp(env, 0.0, 1.0), 1.0));
}
