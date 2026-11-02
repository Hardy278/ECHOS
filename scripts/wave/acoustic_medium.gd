class_name AcousticMedium
extends RefCounted

## 物理三量 → 纹理通道的**唯一**换算处。
## 图块（TileSet custom data）和声学实体（AcousticShape）都从这里取，
## 所以"Z / c / α 是什么、怎么变成通道"只有一个答案。
##
## 美术只填三样：
##   Z    声阻抗：1 = 与空气匹配（声音照穿），越大越硬、越挡声
##   c    （就是 ior）折射率：1 = 空气，越大声速越慢
##   α    吸声：介质**内部**的体衰减（0 = 不吸声，和"挡不挡"是两回事）
##
## 换出来的通道：
##   surface  = surface_from_z(Z)     几何 R / 显现边缘
##   ior      = c                     几何 G / 折射率
##   transmit = transmit_from_z(Z)    几何 B / 透声
##   alpha    = α                     显示 G / 吸声
##   show     由美术单独填（图块有这一层；实体固定 1）
##
## 全部是 static：这里没有状态，也不该有。

## 声阻抗的"实心"上限：Z ≥ 这个值就当彻底挡声。
const Z_HARD := 8.0
## 折射率的编码上限。几何纹理是 RGBA8，通道只有 0~1，
## 所以 c 要按 [1, IOR_MAX] 归一化后才能进纹理（1 → 0，4 → 1）。
## 不归一化的话 1.33 会被夹成 1.0——水就永远不折射。
const IOR_MAX := 4.0
## 显现边缘的地板：完全不该出回声的东西（水）也留一条淡轮廓。
## 水在这游戏里是**淹死判定**，彻底看不见等于看不见陷阱。
## 0 = 纯物理（匹配介质彻底隐身），1 = 所有材质边缘一样亮。
const SURFACE_FLOOR := 0.55


## 声阻抗 → 透声系数。
##   Z = 1    → 1.0（与空气匹配：水和空气都是全通）
##   Z = 5.9  → 0.3（单面平台：只漏三成激波）
##   Z ≥ 8    → 0   （砖石：全挡）
## Z ≤ 0 当实心：custom data 没填就是 0，宁可让忘填的砖变成墙，别变成洞。
static func transmit_from_z(z: float) -> float:
	if z <= 0.0:
		return 0.0
	return clampf((Z_HARD - z) / (Z_HARD - 1.0), 0.0, 1.0)


## 声阻抗 → 显现边缘。物理上就是**反射系数** |Z-1|/|Z+1|：
## 和空气匹配（Z = 1）时声音直接穿过去、不回头，于是没有回声，也就没有轮廓；
## 越硬反射越强，轮廓越亮。
## 结果归一化到 Z = Z_HARD 正好 1.0，这样砖石（最常见的材质）高光一点不变，
## 只有比它软的材质才变暗；最软的落到 SURFACE_FLOOR。
## Z ≤ 0（没填）当成实心 → 1.0。
static func surface_from_z(z: float) -> float:
	var r := absf(z - 1.0) / (z + 1.0)
	r = clampf(r * (Z_HARD + 1.0) / (Z_HARD - 1.0), 0.0, 1.0)
	return SURFACE_FLOOR + (1.0 - SURFACE_FLOOR) * r


## 反算：手上有"想透多少声"（比如门是 0.9），填 Z 时用这个，别自己凑小数。
static func z_for_transmit(t: float) -> float:
	return Z_HARD - (Z_HARD - 1.0) * clampf(t, 0.0, 1.0)


## c → 纹理通道（0~1）。1 = 空气，IOR_MAX = 上限。
static func ior_to_channel(c: float) -> float:
	return clampf((c - 1.0) / (IOR_MAX - 1.0), 0.0, 1.0)


## 纹理通道 → c。着色器里用的是同一个式子（wave_step_fb 的 ior_max uniform）。
static func channel_to_ior(v: float) -> float:
	return 1.0 + clampf(v, 0.0, 1.0) * (IOR_MAX - 1.0)
