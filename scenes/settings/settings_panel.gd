class_name SettingsPanel
extends VBoxContainer
## Настройки игрока (GDD §9). Применяются сразу и сохраняются в user://settings.cfg.


func _ready() -> void:
	set_meta("title", "НАСТРОЙКИ")
	add_theme_constant_override("separation", 16)
	_check("Полный экран (F11)", "fullscreen")
	_speed()
	_check("Уменьшить движение (без наклонов, тряски и анимаций)", "reduce_motion")
	_check("Монохромная шкала шанса (для различения цветов)", "chance_monochrome")
	_check("Подсказки обучения", "tutorial")


func _check(text: String, key: String) -> void:
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = bool(SettingsService.get_value(key))
	cb.add_theme_font_size_override("font_size", 20)
	cb.toggled.connect(func(on: bool) -> void: SettingsService.set_value(key, on))
	add_child(cb)


func _speed() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(UITheme.label("Анимация броска:", "sans", 20, Palette.TEXT))
	var opt := OptionButton.new()
	opt.add_item("Обычная", 0)
	opt.add_item("Быстрая", 1)
	opt.add_item("Без анимации", 2)
	var cur: float = SettingsService.get_value("roll_speed")
	opt.selected = 0 if cur >= 0.9 else (1 if cur > 0.0 else 2)
	opt.item_selected.connect(func(i: int) -> void: SettingsService.set_value("roll_speed", [1.0, 0.35, 0.0][i]))
	row.add_child(opt)
	add_child(row)
