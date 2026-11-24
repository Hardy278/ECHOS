extends Label

## 屏幕下方的交互提示。
## 只监听 Interactor 的 target_changed；不做高亮、不碰物品数据。

func _ready() -> void:
	visible = false
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var interactor := player.get_node_or_null("Interactor") as ItemInteractor
	if interactor != null:
		interactor.target_changed.connect(_on_target_changed)


func _on_target_changed(has_target: bool) -> void:
	visible = has_target
