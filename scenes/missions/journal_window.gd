class_name JournalWindow
extends Control
## Журнал (docs/16 §9): бестиарий встреченных врагов и слухи о миссиях — подтверждённые и нет. Правила — JournalRules.

signal closed

const PANEL := Rect2(250, 90, 1420, 880)

var _tab := "bestiary"
var _tabs: Array = []
var _scroll: ScrollContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(dim)
	var panel := PanelContainer.new()
	panel.position = PANEL.position
	panel.size = PANEL.size
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.055, 0.055, 0.07, 0.98), Palette.GOLD.darkened(0.45), 1, 6, 0))
	add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(m)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	m.add_child(body)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var t := UITheme.label("Журнал", "title_bold", 40, Palette.TEXT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	for tt: Array in [["БЕСТИАРИЙ", "bestiary"], ["СЛУХИ", "rumors"]]:
		var b := Button.new()
		b.text = tt[0]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(180, 44)
		b.add_theme_font_override("font", UITheme.font("caps"))
		b.add_theme_font_size_override("font_size", 18)
		b.set_meta("tab", tt[1])
		b.pressed.connect(func() -> void:
			_tab = tt[1]
			_refresh())
		head.add_child(b)
		_tabs.append(b)
	var x := Button.new()
	x.text = "✕"
	x.flat = true
	x.add_theme_font_size_override("font_size", 26)
	x.pressed.connect(close)
	head.add_child(x)
	body.add_child(head)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_refresh()
	AudioManager.play("open", -6.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	closed.emit()
	queue_free()


func _refresh() -> void:
	for b: Button in _tabs:
		b.button_pressed = b.get_meta("tab") == _tab
	for ch in _scroll.get_children():
		ch.queue_free()
	_scroll.add_child(_bestiary() if _tab == "bestiary" else _rumors())


func _bestiary() -> Control:
	var c := ContentDB.data
	var best := JournalRules.bestiary(GameState.state)
	if best.is_empty():
		return UITheme.label("Пока никого. Враг попадает сюда после первого боя с ним.", "serif_italic", 20, Palette.TEXT_DIM)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 18)
	var ids: Array = best.keys()
	ids.sort()
	for eid: String in ids:
		var rec: Dictionary = best[eid]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		h.custom_minimum_size.x = 660
		var cv := CardView.make(eid, Vector2(110, 188), false)
		cv.inspect_requested.connect(func(id: String) -> void: CardInspector.open_for(self, id))
		h.add_child(cv)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(UITheme.label(c.card_name(eid), "title_bold", 24, Palette.TEXT))
		v.add_child(UITheme.label("боёв %d · побед %d · последний: %s" % [int(rec["fights"]), int(rec["wins"]), rec.get("last", "")], "sans", 16, Palette.TEXT_DIM))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		v.add_child(flow)
		var seen: Array = rec.get("tags", [])
		var hidden := 0
		for tg: String in c.enemies.get(eid, {}).get("tags", []):
			if seen.has(tg):
				var chip := TagChip.make(tg, 17, false)
				flow.add_child(chip)
			else:
				hidden += 1
		if hidden > 0:
			flow.add_child(UITheme.label("??? ×%d — победа раскроет" % hidden, "sans", 15, Palette.TEXT_DIM))
		grid.add_child(h)
	return grid


func _rumors() -> Control:
	var c := ContentDB.data
	var s := GameState.state
	var lines: Array = []
	for mid: String in MissionFlow._sorted(s.missions):
		var m: Dictionary = c.missions.get(mid, {})
		var rs: Array = m.get("rumors", [])
		if rs.is_empty():
			continue
		var block: Array = ["[font_size=22][color=#E6E1D6]%s[/color][/font_size]" % m.get("title", mid)]
		for i in rs.size():
			var text := str(rs[i].get("text", "")).replace("]", "§").replace("[", "[u]").replace("§", "[/u]")
			if JournalRules.confirmed(s, mid, i):
				block.append("  [color=#6FA47B]✓ %s[/color]" % text)
			else:
				block.append("  [color=#9A9CA6]— %s[/color]" % text)
		lines.append("\n".join(block))
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_override("normal_font", UITheme.font("serif"))
	r.add_theme_font_size_override("normal_font_size", 19)
	r.add_theme_color_override("default_color", Palette.SILVER)
	r.text = "\n\n".join(lines) if not lines.is_empty() else "[i]Слухов пока нет.[/i]"
	return r
