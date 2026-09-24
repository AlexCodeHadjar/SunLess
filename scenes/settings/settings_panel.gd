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
	_check("Мысли героя над картой", "thoughts")
	add_child(UITheme.label("Громкость", "caps", 22, Palette.SILVER))
	_slider("Общая", "vol_master")
	_slider("Музыка", "vol_music")
	_slider("Эмбиент", "vol_ambient")
	_slider("Эффекты", "vol_sfx")
	_slider("Интерфейс", "vol_ui")
	add_child(UITheme.label("Звуки и частицы — CC0: Kenney, JaggedStone, Ruhinre (audio/CREDITS.md)", "sans", 14, Palette.TEXT_DIM))


func _check(text: String, key: String) -> void:
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = bool(SettingsService.get_value(key))
	cb.add_theme_font_size_override("font_size", 20)
	cb.toggled.connect(func(on: bool) -> void: SettingsService.set_value(key, on))
	add_child(cb)


func _slider(text: String, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UITheme.label(text, "sans", 18, Palette.TEXT)
	l.custom_minimum_size.x = 140
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.custom_minimum_size = Vector2(360, 24)
	s.value = float(SettingsService.get_value(key))
	s.value_changed.connect(func(v: float) -> void: SettingsService.set_value(key, v))
	row.add_child(s)
	add_child(row)


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
