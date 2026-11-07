extends RefCounted

## 全局物理常量（用 preload 引用，不依赖 class_name 的全局类缓存：
##   const GameConst := preload("res://scripts/world/constants.gd")
## 这样命令行跑 headless 也不会因为缓存没刷新而报"未声明"）。
##
## 单位一律是"世界单位 / 秒"和"世界单位 / 秒²"——**每帧的位移由调用方自己乘 delta**。
##
## 重力是所有东西共用的同一个数：单位一旦不统一（一个按秒²、一个按帧²），
## 两边看仔细也看不出差，只能靠"某个东西掉得不对劲"去猜。

## 重力加速度。玩家和草都从这里取
const GRAVITY := 900.0

## 玩家质量。草的 mass 是各自的导出参数；
## 撞击时的速度分配 = m_player / (m_player + m_grass)
const PLAYER_MASS := 1.0
