extends Control

## 背包 UI：只读 Inventory，不拥有任何物品。
##
## 4 格，每格 48×48，间距 6，内边距 6；不画整条外框，只留四个格子。
## 普通格 2px 暗金边；当前选中格 3px 亮金橙边。
## 鼠标滚轮切换 active_slot（上滚上一格、下滚下一格）。
##
## 没有 ItemDef.icon 时用程序画的黄绿色浆果占位，不依赖 svg/png。

const SLOT := 48.0
const GAP := 6.0
const PAD := 6.0

const GOLD_BRIGHT := Color(0.9, 0.76, 0.38, 1.0)
const GOLD_DIM := Color(0.46, 0.37, 0.18, 0.95)
const SLOT_BG := Color(0.11, 0.085, 0.045, 0.96)

var _inventory: Inventory


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process_input(true)
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		_inventory = player.get_node_or_null("Inventory") as Inventory
	if _inventory != null:
		_inventory.changed.connect(_on_changed)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if _inventory == null:
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_inventory.cycle_active(-1)
		get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_inventory.cycle_active(1)
		get_viewport().set_input_as_handled()


func _on_changed() -> void:
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for i in Inventory.SLOT_COUNT:
		var r := Rect2(PAD + float(i) * (SLOT + GAP), PAD, SLOT, SLOT)
		draw_rect(r, SLOT_BG, true)

		if _inventory != null:
			var s := _inventory.get_slot(i)
			if s != null and not s.is_empty():
				if s.def != null and s.def.icon != null:
					draw_texture_rect(s.def.icon, r, false)
				else:
					_draw_berry_icon(r)

				var txt := str(s.count)
				var pos := Vector2(r.position.x + 3.0, r.end.y - 4.0)
				draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_RIGHT, SLOT - 6.0,
						14, 4, Color(0.0, 0.0, 0.0, 1.0))
				draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_RIGHT, SLOT - 6.0,
						14, Color(1.0, 0.94, 0.78, 1.0))

		var active := _inventory != null and i == _inventory.active_slot
		if active:
			draw_rect(r, GOLD_BRIGHT, false, 3.0)
		else:
			draw_rect(r, GOLD_DIM, false, 2.0)


## 32×32 的黄绿色浆果，刚好是 16px 图在 TileMap 2× 下的尺寸。
func _draw_berry_icon(r: Rect2) -> void:
	var c := r.get_center()
	var body := Rect2(c - Vector2(16, 16), Vector2(32, 32))
	draw_rect(body.grow(2.0), Color(0.18, 0.25, 0.05, 1.0), true)
	draw_rect(body, Color(0.55, 0.72, 0.18, 1.0), true)
	draw_rect(Rect2(c + Vector2(-10, -12), Vector2(8, 6)),
			Color(0.82, 0.95, 0.45, 1.0), true)
	draw_rect(Rect2(c + Vector2(6, 4), Vector2(6, 8)),
			Color(0.32, 0.45, 0.1, 1.0), true)
	draw_rect(Rect2(c + Vector2(4, 12), Vector2(4, 2)),
			Color(0.42, 0.58, 0.12, 1.0), true)
