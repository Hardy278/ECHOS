class_name EchoLayer
extends Resource

## 一层。**纯数据**——节点、材质这些运行时对象由 EchoWorld 持有。
## Resource 里塞 Node 引用会跟着序列化跑，跨房间必炸。
##
## 层不是"物理量"的容器：物理参数在每块砖/每个实体身上（tileset custom data、
## AcousticShape）。层只决定三件事：
##   1. 绘制顺序（谁压谁）
##   2. 这一层图块的默认显示倍率（被 per-tile 的 show 覆盖）
##   3. 是否参与声学（不进几何 = 不挡声、不长边缘高光）
enum Kind {
	TILE,     ## 房间里的一个 TileMapLayer
	ENTITY,   ## 房间里的实体（AcousticShape）。全表只能有一个
}

## 这一层是图块还是实体
@export var kind: Kind = Kind.TILE
## 房间里的节点名。kind == TILE 时必填；ENTITY 层留空
@export var path: NodePath = ^""
## 顺序键：小 = 底层，大 = 顶层。
## 它决定几何纹理里"谁压谁"（同一个 texel 上层的参数覆盖下层的）。
## 必须全局唯一——重复就是未定义行为，而画面几乎看不出来。
@export var z: int = 0
## 这一层图块的默认显示倍率。会被每块砖自己的 show 乘上去。
@export var light_gain := 1.0
## 进不进几何：true = 挡声、长边缘高光；false = 纯装饰（远景、天空）
@export var acoustic := true
## 叠加特效（背景抖动、水面扭曲…）。没有就留空
@export var next_pass: ShaderMaterial
