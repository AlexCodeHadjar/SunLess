class_name ResultScreen
extends Control
## Экран результата (docs/11 §7): исход, бросок, строки последствий, награда → следующее событие.

signal continued

var _panel: PanelContainer
var _content: VBoxContainer
var _result: Dictionary


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UITheme.box(Palette.BG_PANEL, Palette.LINE, 1, 4, 0))
	_panel.size = Vector2(1480, 840)
	add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	_panel.add_child(margin)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 14)
	margin.add_child(_content)


func _process(_d: float) -> void:
	if not visible:
		return
	var want := ((get_viewport_rect().size - _panel.size) / 2).round()
	if _panel.position.distance_to(want) > 12:
		_panel.position = want


func show_result(result: Dictionary) -> void:
	_result = result
	visible = true
	for c in _content.get_children():
		c.queue_free()
	var c := ContentDB.data
	var ev: Dictionary = c.events.get(result["event_id"], {})
	var o := c.option(result["event_id"], result["option_id"])
	var success: bool = result["success"]

	var head := UITheme.label("РЕЗУЛЬТАТ", "caps", 20, Palette.TEXT_DIM)
	_content.add_child(head)
	var title := UITheme.label("✦  УСПЕХ  ✦" if success else "✖  ПРОВАЛ  ✖", "title_bold", 56, Palette.SILVER if success else Palette.STAT_DOWN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(title)
	var sub := UITheme.label("«%s» · %s · %s" % [str(o.get("label", "")), str(ev.get("title", "")), c.card_name(str(result["executor"]))], "serif_italic", 18, Palette.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(sub)
	var flavor := str(o.get("ok_text" if success else "fail_text", ""))
	if flavor != "":
		var fl := UITheme.label(flavor, "serif", 22, Palette.TEXT)
		fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(fl)

	var roll_row := HBoxContainer.new()
	roll_row.alignment = BoxContainer.ALIGNMENT_CENTER
	roll_row.add_theme_constant_override("separation", 16)
	_content.add_child(roll_row)
	var roll_label := UITheme.label("", "sans", 18, Palette.TEXT)
	if result["rolled"]:
		roll_row.add_child(UITheme.label("БРОСОК", "caps", 18, Palette.TEXT_DIM))
		var bar := ChanceBar.new()
		bar.track_height = 14
		bar.custom_minimum_size = Vector2(520, 30)
		roll_row.add_child(bar)
		bar.set_chance(int(result["chance"]), false)
		roll_row.add_child(UITheme.label("%d%%" % int(result["chance"]), "title_bold", 30, Palette.TEXT))
		roll_label.text = "Шанс %d%% · Выпало %d · %s" % [int(result["chance"]), int(result["roll"]), "Успех" if success else "Провал"]
		AudioManager.play("roll_shake", -4.0)
		bar.roll_finished.connect(_on_roll_finished.bind(bar))
		bar.play_roll.call_deferred(int(result["roll"]))
	else:
		roll_label.text = "Без броска — условия выполнены"
		_on_roll_finished.call_deferred(null)
	roll_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roll_label.add_theme_color_override("font_color", Palette.STAT_UP if success else Palette.STAT_DOWN)
	_content.add_child(roll_label)

	var death: Dictionary = result.get("death", {})
	if not death.is_empty():
		var dl := UITheme.label("☠ Бросок смерти: шанс %d%% · выпало %d · %s" % [int(death["chance"]), int(death["roll"]), "ПОГИБ" if death["died"] else "выжил"], "sans_bold", 18, Palette.TRAUMA_BRIGHT)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_content.add_child(dl)

	var sep := ColorRect.new()
	sep.color = Palette.LINE
	sep.custom_minimum_size.y = 1
	_content.add_child(sep)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 36)
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(bottom)

	var lines := VBoxContainer.new()
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.add_theme_constant_override("separation", 6)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(lines)
	bottom.add_child(scroll)
	var cards: Array = []
	var next_event := ""
	for e: Dictionary in result.get("entries", []):
		var col := _entry_color(str(e.get("kind", "")))
		var l := UITheme.label("• " + str(e["text"]), "sans", 18, col)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lines.add_child(l)
		if e.get("kind", "") in ["card"] and e.has("card"):
			cards.append(e["card"])
		if e.get("kind", "") == "event" and e.has("card") and next_event == "":
			next_event = str(e["card"])
	for w: Dictionary in result.get("wear", []):
		if not w["broken"]:
			var wl := UITheme.label("⚒ %s: износ %d%% → %d%%" % [c.card_name(str(w["card"])), int(w["before"]), int(w["after"])], "sans", 16, Palette.TEXT_DIM)
			lines.add_child(wl)
	if lines.get_child_count() == 0:
		lines.add_child(UITheme.label("Ничего не изменилось.", "sans", 18, Palette.TEXT_DIM))

	var reward_row := HBoxContainer.new()
	reward_row.add_theme_constant_override("separation", 22)
	reward_row.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(reward_row)
	if not cards.is_empty():
		var colr := VBoxContainer.new()
		colr.add_child(UITheme.label("ПОЛУЧЕНО", "caps", 16, Palette.TEXT_DIM))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		for card: String in cards.slice(0, 3):
			hb.add_child(CardView.make(card, CardView.SIZE_PANEL, false))
		colr.add_child(hb)
		reward_row.add_child(colr)
	if next_event != "":
		if not cards.is_empty():
			reward_row.add_child(UITheme.label("→", "title_bold", 48, Palette.SILVER))
		var coln := VBoxContainer.new()
		coln.add_child(UITheme.label("СЛЕДУЮЩЕЕ СОБЫТИЕ", "caps", 16, Palette.TEXT_DIM))
		coln.add_child(CardView.make(next_event, CardView.SIZE_PANEL, false))
		reward_row.add_child(coln)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	var week := UITheme.label("Неделя %d" % int(result.get("week", 0)), "sans", 18, Palette.TEXT_DIM)
	week.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(week)
	var btn := Button.new()
	btn.text = "ПРОДОЛЖИТЬ  ›"
	btn.custom_minimum_size = Vector2(240, 56)
	btn.add_theme_font_override("font", UITheme.font("caps"))
	btn.add_theme_font_size_override("font_size", 22)
	btn.pressed.connect(_on_continue)
	footer.add_child(btn)
	_content.add_child(footer)
	btn.grab_focus.call_deferred()
	_flash(success)


## Итог после остановки указателя: звук исхода, частицы, затем травмы / поломки / смерть.
func _on_roll_finished(bar: ChanceBar) -> void:
	var success: bool = _result["success"]
	if bar:
		AudioManager.play("roll", -6.0)
	AudioManager.play("success" if success else "fail", -2.0, 1.0 if success else 0.8)
	var center := _panel.position + Vector2(_panel.size.x / 2, 150)
	var fx := Vfx.burst(center, success)
	add_child(fx)
	Vfx.autofree(fx)
	if not success:
		_shake()
	await get_tree().create_timer(0.45).timeout
	if not Array(_result.get("traumas", [])).is_empty():
		AudioManager.play("trauma", -3.0)
		await get_tree().create_timer(0.3).timeout
	for w: Dictionary in _result.get("wear", []):
		if w["broken"]:
			AudioManager.play("break", -2.0)
	if bool(_result.get("death", {}).get("died", false)):
		AudioManager.play("death", 0.0, 0.7)


func _shake() -> void:
	if SettingsService.get_value("reduce_motion"):
		return
	var base := _panel.position
	var tw := create_tween()
	for i in 7:
		tw.tween_property(_panel, "position", base + Vector2(randf_range(-3, 3), randf_range(-3, 3)), 0.035)
	tw.tween_property(_panel, "position", base, 0.05)


func _entry_color(kind: String) -> Color:
	match kind:
		"trauma", "broken", "death", "lost": return Palette.STAT_DOWN
		"card", "ability", "stage", "perm", "heal": return Palette.STAT_UP
		"resource": return Palette.COINS
		"event", "pending": return Palette.GOLD
		"reveal", "codex": return Palette.REQ_MET
	return Palette.TEXT


func _flash(success: bool) -> void:
	if SettingsService.get_value("reduce_motion"):
		return
	var st: StyleBoxFlat = UITheme.box(Palette.BG_PANEL, Palette.SILVER if success else Palette.TRAUMA_BRIGHT, 3, 4, 0)
	_panel.add_theme_stylebox_override("panel", st)
	var tw := create_tween()
	tw.tween_interval(0.4)
	tw.tween_callback(func() -> void: _panel.add_theme_stylebox_override("panel", UITheme.box(Palette.BG_PANEL, Palette.LINE, 1, 4, 0)))


func _on_continue() -> void:
	visible = false
	continued.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel")):
		_on_continue()
		get_viewport().set_input_as_handled()
