extends Node2D

## 钟：不动的矩形，**没有碰撞箱**，而且**只在它自己响的时候显形**。
## 外观是 Sprite2D，显示逻辑在 entity_glow.gdshader 里：
## 亮度取它自己声源的场，不响就是全黑；听者听不见它（比如隔着墙）也是全黑。
## 发声由子节点 EchoSource 负责，定时由 EchoSource/Tick（SoundAbility）负责。

const TINT := Color(1.0, 0.82, 0.45)
const GLOW_SHADER := preload("res://shaders/entity_glow.gdshader")

@onready var _source: Node2D = $EchoSource
@onready var _sprite: Sprite2D = $Sprite

var _mat: ShaderMaterial
var _bound := false


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = GLOW_SHADER
	_mat.set_shader_parameter("field_size", EchoField.FIELD_SIZE)
	_mat.set_shader_parameter("source_px", global_position)
	_mat.set_shader_parameter("listener_px", global_position)
	_mat.set_shader_parameter("hear_ref", 0.05)
	_mat.set_shader_parameter("tint", TINT)
	_sprite.material = _mat


func _process(_delta: float) -> void:
	if _mat == null or _source == null:
		return

	# 声源是延迟初始化的，纹理要等它建好
	if not _bound:
		var tex = _source.field_texture()
		if tex == null:
			return
		_mat.set_shader_parameter("env_field", tex)
		_mat.set_shader_parameter("hear_ref", _source.hear_ref)
		_bound = true

	# 和声源那一层用同一个闸门：听不见就一起灭
	_mat.set_shader_parameter("listener_px", _source.listener_position())
