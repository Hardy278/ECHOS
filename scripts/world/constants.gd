extends RefCounted

## 全局物理常量（用 preload 引用，不依赖 class_name 的全局类缓存：
##   const GameConst := preload("res://scripts/world/constants.gd")
## 这样命令行跑 headless 也不会因为缓存没刷新而报"未声明"）。
##
## 单位一律是"世界单位 / 秒"和"世界单位 / 秒²"——**每帧的位移由调用方自己乘 delta**。
##
## 为什么要有这个文件：之前玩家的重力写 900（单位/秒²），草的写 0.12（单位/帧²），
## 谁也没发现草的重力其实只有玩家的一半。全局只留一个数，这种错就不会再出现。

## 重力加速度。玩家和草都从这里取
const GRAVITY := 900.0

## 玩家质量。草的 mass 是各自的导出参数；
## 撞击时的速度分配 = m_player / (m_player + m_grass)
const PLAYER_MASS := 1.0
