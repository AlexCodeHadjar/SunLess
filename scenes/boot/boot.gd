extends Control
## Первая сцена: проверяет данные и открывает главное меню.
## Если данные сломаны — показывает список ошибок вместо игры.

const MENU := "res://scenes/menu/main_menu.tscn"


func _ready() -> void:
	if not ContentDB.errors.is_empty():
		_show_errors(ContentDB.errors)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mshots="):
			get_tree().root.add_child.call_deferred(load("res://tools/mission_shots.gd").new())
	get_tree().change_scene_to_file.call_deferred(MENU)


func _show_errors(errors: Array[String]) -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0E0F14")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var label := RichTextLabel.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 40
	label.offset_top = 40
	label.text = "Ошибки в данных игры (%d):\n\n• %s" % [errors.size(), "\n• ".join(errors)]
	add_child(label)
