class_name EchoLayerSet
extends Resource

## 全局唯一的一份层表（res://world/layer_set.tres）。
##
## **不要按房间 export。** 层顺序一变，几何纹理里的覆盖关系就变，
## 于是"同一堵墙在两个房间声学行为不同"——这会是最难查的那类 bug。
##
## 校验在 EchoLayers（autoload）里启动时跑一次。

## 层列表。顺序不重要（按 z 排序），但 z 必须唯一。
##
## 这里刻意用**无类型 Array**：.tres 里手写 `Array[EchoLayer]` 的序列化形式
## 不稳（要写成 Array[Resource]，赋值时可能不认）。类型检查交给 EchoLayers
## 在 _reload 里做一次即可。
@export var layers: Array = []
