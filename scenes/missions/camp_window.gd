class_name CampWindow
extends Control
## Окно лагеря (docs/16 §9): койки для героев и доска слухов о том, что ждёт впереди. Правила — CampRules.

signal closed

const PANEL := Rect2(250, 110, 1420, 820)

var _beds: HBoxContainer
var _bench: HBoxContainer
var _timer := 0.0


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
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.055, 0.055, 0.07, 0.98), Palette.REST.darkened(0.4), 1, 6, 0))
	add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(m)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	m.add_child(body)
	var head := HBoxContainer.new()
	var t := UITheme.label("Лагерь", "title_bold", 40, Palette.TEXT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := Button.new()
	x.text = "✕"
	x.flat = true
	x.add_theme_font_size_override("font_size", 26)
	x.pressed.connect(close)
	head.add_child(x)
	body.add_child(head)
	var intro := UITheme.label("Угли, пара драных плащей и тишина. На койке герой отдыхает и успокаивается вдвое быстрее, а лёгкие травмы понемногу проходят (одна за %d с). Уход на миссию освобождает койку." % int(CampRules.HEAL_EVERY),
		"serif_italic", 19, Palette.SILVER)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = PANEL.size.x - 56
	body.add_child(intro)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.custom_minimum_size.x = 760
	cols.add_child(left)
	left.add_child(UITheme.label("Койки", "caps", 22, Palette.SILVER))
	_beds = HBoxContainer.new()
	_beds.add_theme_constant_override("separation", 28)
	left.add_child(_beds)
	left.add_child(UITheme.label("Свободные герои — щелчок укладывает на койку", "sans", 16, Palette.TEXT_DIM))
	_bench = HBoxContainer.new()
	_bench.add_theme_constant_override("separation", 10)
	left.add_child(_bench)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(UITheme.label("Доска слухов", "caps", 22, Palette.SILVER))
	right.add_child(_board())
	EventBus.state_changed.connect(_refresh)
	_refresh()
	AudioManager.play("open", -6.0, 0.9)


func _process(dt: float) -> void:
	_timer += dt
	if _timer >= 1.0 and not get_viewport().gui_is_dragging():
		_timer = 0.0
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	closed.emit()
	queue_free()


func _refresh() -> void:
	if not is_inside_tree():
		return
	var c := ContentDB.data
	var s := GameState.state
	for ch in _beds.get_children():
		ch.queue_free()
	for ch in _bench.get_children():
		ch.queue_free()
	var in_beds := CampRules.beds(s)
	for i in CampRules.BEDS:
		if i < in_beds.size():
			_beds.add_child(_bed(str(in_beds[i])))
		else:
			var dz := DropZone.new()
			dz.accepts = ["character"]
			dz.hint = "свободная койка"
			dz.custom_minimum_size = Vector2(150, 257)
			dz.dropped.connect(_put)
			_beds.add_child(dz)
	for cid: String in MissionFlow.heroes(c, s):
		if in_beds.has(cid):
			continue
		var cv := CardView.make(cid, Vector2(96, 164), false)
		var busy := MissionFlow.on_mission(s, cid)
		cv.dimmed = busy
		cv.badge = "на миссии" if busy else MissionFlow.busy_reason(c, s, cid)
		cv.clicked.connect(_put)
		cv.inspect_requested.connect(func(id: String) -> void: CardInspector.open_for(self, id))
		_bench.add_child(cv)


func _bed(cid: String) -> Control:
	var c := ContentDB.data
	var s := GameState.state
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var cv := CardView.make(cid, Vector2(150, 257), false)
	cv.inspect_requested.connect(func(id: String) -> void: CardInspector.open_for(self, id))
	h.add_child(cv)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size.x = 200
	h.add_child(v)
	v.add_child(UITheme.label(c.card_name(cid), "sans_bold", 20, Palette.TEXT))
	var rest := MissionFlow.busy_reason(c, s, cid)
	v.add_child(UITheme.label(rest if rest != "" else "отдохнул", "sans", 16, Palette.REST if rest != "" else Palette.STAT_UP))
	var pv := PanicRules.value(s, cid)
	if pv > 0:
		v.add_child(UITheme.label("паника %d — %s" % [pv, PanicRules.word(pv)], "sans", 16, SquadLifeUI.panic_color(pv)))
	var tid := CampRules.next_heal(c, s, cid)
	var heal := UITheme.label("пройдёт «%s» через %d с" % [c.card_name(tid), int(ceil(CampRules.heal_left(s, cid)))] if tid != "" else "лёгких травм нет",
		"sans", 16, Palette.STAT_UP if tid != "" else Palette.TEXT_DIM)
	heal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heal.custom_minimum_size.x = 200
	v.add_child(heal)
	var b := Button.new()
	b.text = "ПОДНЯТЬ"
	b.custom_minimum_size = Vector2(160, 40)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_override("font", UITheme.font("caps"))
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(func() -> void:
		GameState.camp_take(cid)
		_refresh())
	v.add_child(b)
	return h


func _put(cid: String) -> void:
	var err := GameState.camp_put(cid)
	if err != "":
		EventBus.toast.emit(err)
	_refresh()


func _board() -> Control:
	var c := ContentDB.data
	var lines: Array = []
	for r: Dictionary in CampRules.rumors(c, GameState.state):
		var text := str(r["text"])
		var i := text.find("[")
		var j := text.find("]")
		if i >= 0 and j > i:
			text = text.substr(0, i) + "[color=#E3C98E][u]%s[/u][/color]" % text.substr(i + 1, j - i - 1) + text.substr(j + 1)
		var place := str(r.get("place", ""))
		lines.append(("[font_size=15][color=#9A9CA6]%s[/color][/font_size]
" % place.to_upper() if place != "" else "") + "— [i]%s[/i]" % text)
	if lines.is_empty():
		lines.append("[i]Ни шёпота. Всё, о чём говорили, уже случилось.[/i]")
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_override("normal_font", UITheme.font("serif"))
	r.add_theme_font_override("italics_font", UITheme.font("serif_italic"))
	r.add_theme_font_size_override("normal_font_size", 19)
	r.add_theme_font_size_override("italics_font_size", 19)
	r.add_theme_color_override("default_color", Palette.SILVER)
	r.text = "\n\n".join(lines)
	return r
