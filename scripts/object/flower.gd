class_name Flower
extends Node2D

## 会发光的花：一盏很小、很软的灯。
##
## 和钟、果实同一套东西，只是更安静：
##   Sprite      挂实体材质（tile_light）——照亮它的是**声音**，不是别的
##   Echo        EchoSource，自己不发声，等 Hum 推它
##   Hum         每 0.1 秒推一声很轻的响 → 它周围那一圈就一直是亮的
##   Body        AcousticBody：形状就是它自己的贴图轮廓，Z = 1（只留形状、不挡声）
##
## 所以"花会发光"这件事在世界里等于"花一直在很轻地响"：
## 走过它身边，光会跟着洒出来；冲它喊一声，它会被照亮一下。
## 想让它变成一跳一跳的，把 Hum 的 period 调大就行，代码不用改。

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	var world := get_tree().get_first_node_in_group("echo_world")
	if world != null and world.has_method("entity_material"):
		_sprite.material = world.entity_material()
	# AcousticBody.visual 走场景里的 NodePath 读出来是 null（见 shooter.gd），只能在代码里给
	var body := get_node_or_null("Body") as AcousticBody
	if body != null:
		body.visual = _sprite
