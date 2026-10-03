class_name QuestPanel
extends Control
## Задания справа на экране карты (QuestRules, docs/20; просьба владельца 03.10): текст прямо на фоне игры — у края
## мягкое затемнение, чтобы читалось. Сверху цель главы, ниже — сюжет (золото), угрозы (красный), побочные линии
## (серебро). У каждого задания значок-прицел: щелчок — карта подъезжает к месту, участок загорается и от фигуры
## к нему рисуется путь (show_place). Заголовок «ЗАДАНИЯ» сворачивает список (настройка quests_open).

signal show_place(entry: Dictionary)

const W := 360.0
const COLORS := {"story": Color("#E3C98E"), "threat": Color(1.0, 0.5, 0.42), "side": Color(0.84, 0.87, 0.95)}

var _box: VBoxContainer
var _list: VBoxContainer
var _head: Button
var _shown := ""             # что показано (слепок): не изменилось — не перестраивать
var _seen: Array = []        # id заданий, которые игрок уже видел: новое — вспыхивает
var _open := true
var _has := false            # есть что показать (цель или задания)


func has_entries() -> bool:
	return _has


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, 0)
	_open = bool(SettingsService.get_value("quests_open"))
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.custom_minimum_size = Vector2(W, 0)
	_box.resized.connect(queue_redraw)
	add_child(_box)
	_head = Button.new()
	_head.flat = true
	_head.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_head.add_theme_font_override("font", UITheme.font("caps"))
	_head.add_theme_font_size_override("font_size", 17)
	_head.add_theme_color_override("font_color", Palette.SILVER)
	_head.add_theme_color_override("font_hover_color", Palette.TEXT)
	_head.tooltip_text = "Свернуть или развернуть задания"
	_head.pressed.connect(func() -> void:
		_open = not _open
		SettingsService.values["quests_open"] = _open   # без apply(): окно и звук не трогаем
		SettingsService.save_settings()
		_list.visible = _open
		_update_head()
		queue_redraw())
	_box.add_child(_head)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.visible = _open
	_box.add_child(_list)
	_update_head()
	HintTargets.put("quests", [self])


func _update_head() -> void:
	_head.text = ("ЗАДАНИЯ  ▾" if _open else "ЗАДАНИЯ  ▸")


## Показать цель главы и задания. Повторный вызов с тем же — ничего не перестраивает.
func set_entries(goal: String, entries: Array) -> void:
	var key := goal + JSON.stringify(entries)
	if key == _shown:
		return
	_shown = key
	for ch in _list.get_children():
		ch.queue_free()
	if goal != "":
		var g := _text(goal, "serif_italic", 16, Color(0.8, 0.82, 0.88))
		_list.add_child(g)
	for e: Dictionary in entries:
		_list.add_child(_row(e, not _seen.has(str(e["id"]))))
		if not _seen.has(str(e["id"])):
			_seen.append(str(e["id"]))
	_has = not entries.is_empty() or goal != ""
	visible = _has
	(func() -> void:
		size = _box.get_combined_minimum_size()
		queue_redraw()).call_deferred()


func _row(e: Dictionary, fresh: bool) -> Control:
	var kind := str(e.get("kind", "side"))
	var col: Color = COLORS.get(kind, COLORS["side"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.tooltip_text = "Показать на карте" if str(e.get("place", "")) != "" else ""
	row.alignment = BoxContainer.ALIGNMENT_END
	var col_box := VBoxContainer.new()
	col_box.add_theme_constant_override("separation", 1)
	col_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col_box)
	var group := str(e.get("group", ""))
	if kind == "story":
		group = "Сюжет"
	elif kind == "threat":
		group = "Угроза"
	if group != "":   # «СЮЖЕТ», «УГРОЗА», имя линии — крупно и отчётливо (просьба владельца 03.10)
		var gl := _text(group.to_upper(), "caps", 16 if kind == "story" else 14, col.lightened(0.15))
		gl.add_theme_constant_override("outline_size", 6)
		col_box.add_child(gl)
	col_box.add_child(_text(str(e.get("title", "")), "sans_bold", 17, col))
	col_box.add_child(_text(str(e.get("line", "")), "sans", 14, Color(0.86, 0.87, 0.9)))
	var icon := QuestIcon.new()
	icon.color = col
	icon.can_show = str(e.get("place", "")) != ""
	row.add_child(icon)
	var go := func() -> void:
		show_place.emit(e)
		icon.ping()
	icon.pressed.connect(go)
	row.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			go.call())
	row.mouse_entered.connect(func() -> void: icon.hot = true)
	row.mouse_exited.connect(func() -> void: icon.hot = false)
	if fresh and not Vfx.reduced():   # новое задание — короткая вспышка
		row.modulate = Color(1.6, 1.4, 0.9, 0.0)
		var tw := row.create_tween()
		tw.tween_property(row, "modulate", Color(1.4, 1.25, 0.9, 1.0), 0.35)
		tw.tween_property(row, "modulate", Color.WHITE, 1.4)
	return row


func _text(t: String, font: String, fs: int, col: Color) -> Label:
	var l := UITheme.label(t, font, fs, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size.x = W - 50.0
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Мягкое затемнение у правого края — чтобы текст читался на любой карте: темнее к краю окна, сверху и снизу
## тает без резкой кромки.
func _draw() -> void:
	var h := maxf(_box.size.y, _box.get_combined_minimum_size().y) + 40.0
	var cols := 14
	var rows := 10
	var cw := (W + 110.0) / cols   # до самого края окна (панель стоит в 28 px от него)
	var rh := h / rows
	for i in cols:
		var ax := 0.8 * pow(float(i + 1) / cols, 0.9)
		for j in rows:
			var v := float(j) + 0.5
			var ay := clampf(minf(v, rows - v) / 2.0, 0.0, 1.0)
			draw_rect(Rect2(Vector2(-60.0 + cw * i, -20.0 + rh * j), Vector2(cw + 1.0, rh + 1.0)), Color(0.0, 0.0, 0.02, ax * ay))


## Значок-прицел задания: кольцо с перекрестьем и точкой; наведение — свечение, щелчок — расходящееся кольцо.
class QuestIcon:
	extends Control
	signal pressed
	var color := Color.WHITE
	var can_show := true
	var hot := false:
		set(v):
			hot = v
			queue_redraw()
	var _ping := 0.0

	func _ready() -> void:
		custom_minimum_size = Vector2(36, 36)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "Показать на карте" if can_show else "Подробнее"
		mouse_entered.connect(func() -> void: hot = true)
		mouse_exited.connect(func() -> void: hot = false)
		set_process(false)

	func ping() -> void:
		_ping = 1.0
		set_process(true)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()

	func _process(delta: float) -> void:
		_ping = maxf(0.0, _ping - delta * 1.6)
		queue_redraw()
		if _ping <= 0.0:
			set_process(false)

	func _draw() -> void:
		var c := size / 2.0
		var r := 13.0
		if hot:
			draw_circle(c, r + 6.0, Color(color, 0.18))
		draw_circle(c, r, Color(0.04, 0.04, 0.06, 0.85))
		draw_arc(c, r, 0.0, TAU, 32, color, 2.0, true)
		if can_show:
			for k in 4:
				var d := Vector2.from_angle(TAU * k / 4.0)
				draw_line(c + d * (r - 5.0), c + d * (r + 3.0), color, 2.0, true)
			draw_circle(c, 3.2, color)
		else:
			draw_circle(c, 2.0, color)
		if _ping > 0.0:
			draw_arc(c, r + (1.0 - _ping) * 14.0, 0.0, TAU, 32, Color(color, _ping), 2.0, true)
