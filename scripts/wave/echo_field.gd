class_name EchoField
extends RefCounted

## 声场的尺寸：全项目只有这一份数字，别处一律引用这里。
##
## 1 texel = 1 世界单位，所以这同时也是一张"和世界等大"的图：
## 地图、声场 texel、合成出来的光照共用同一把尺。
##
## 为什么单独开一个文件、而不是挂在 EchoWorld 上：EchoWorld 在**编译期**就
## preload 了 WaveGeometry，WaveGeometry 若再去引用 EchoWorld.FW 就成了循环引用
## （Godot 会报 Cyclic reference）。这里谁都不引用，所以谁都能引用它。

const FW := 480
const FH := 270
## SubViewport 的尺寸
const VIEW_SIZE := Vector2i(FW, FH)
## 送给着色器 uniform `field_size`；世界坐标 ÷ 它 = uv
const FIELD_SIZE := Vector2(FW, FH)
