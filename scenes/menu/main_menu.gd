extends Control
## Главное меню: логотип, «Продолжить», «Новая игра», «Выход».

const MISSIONS := "res://scenes/missions/mission_game.tscn"


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bd := MapBackdrop.new()
	bd.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bd)
	var vp := Vector2(1920, 1080)
	add_child(Vfx.fog(Rect2(Vector2(-200, 300), Vector2(vp.x + 400, 600)), 0.06))
	add_child(Vfx.ambient_embers(Rect2(Vector2(0, 0), vp)))
	AudioManager.play_music()
	AudioManager.play_ambient()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var v := VBoxContainer.new()
	v.position = Vector2(160, 240)
	v.add_theme_constant_override("separation", 14)
	add_child(v)
	v.add_child(UITheme.label("SunLess", "title", 120, Palette.TEXT))
	var sub := UITheme.label("И   ТЕНИ   ПОМНЯТ", "sans", 18, Palette.TEXT_DIM)
	v.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 40
	v.add_child(gap)

	if SaveService.has_save():
		_button(v, "Продолжить", _on_continue).grab_focus.call_deferred()
	var ng := _button(v, "Новая игра", _on_new)
	if not SaveService.has_save():
		ng.grab_focus.call_deferred()
	_button(v, "Выход", func() -> void: get_tree().quit())

	var ver := UITheme.label("Версия %s · демоверсия: Первый Кошмар и Академия · фанатский некоммерческий проект" % ProjectSettings.get_setting("application/config/version"), "sans", 14, Palette.TEXT_DIM)
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = 24
	ver.offset_top = -40
	add_child(ver)


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 58)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", UITheme.font("caps"))
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _on_continue() -> void:
	var err := GameState.continue_run()
	if err != "":
		var l := UITheme.label(err, "sans", 18, Palette.STAT_DOWN)
		l.position = Vector2(160, 760)
		add_child(l)
		return
	get_tree().change_scene_to_file(MISSIONS)


func _on_new() -> void:
	AudioManager.play("shuffle")
	GameState.new_mission_run()
	get_tree().change_scene_to_file(MISSIONS)

