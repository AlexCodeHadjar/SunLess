class_name EventTablet
extends Control
## Планшет события (docs/11 §5): арт, текст, подготовка слева, три варианта справа.

signal closed
signal resolve_requested(event_id: String, option_id: String)

var event_id := ""
var _panel: PanelContainer
var _art_holder: Control
var _title: Label
var _text: RichTextLabel
var _pocket: DropZone
var _fan: DropZone
var _stats_box: HBoxContainer
var _info_box: VBoxContainer
var _options_box: VBoxContainer
var _header: Label
var _source: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_build()
	EventBus.draft_changed.connect(_on_draft_changed)
	EventBus.state_changed.connect(_on_state_changed)


func _on_draft_changed(eid: String) -> void:
	if eid == event_id:
		refresh()


func _on_state_changed() -> void:
	if visible and event_id != "":
		refresh()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UITheme.box(Palette.BG_PANEL, Palette.LINE, 1, 4, 0))
	_panel.position = Vector2(80, 16)
	_panel.size = Vector2(1760, 748)
	add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	_panel.add_child(root)

	# служебная строка 60 px
	var bar := HBoxContainer.new()
	bar.custom_minimum_size.y = 46
	bar.add_theme_constant_override("separation", 16)
	var pad_l := Control.new()
	pad_l.custom_minimum_size.x = 12
	bar.add_child(pad_l)
	_header = UITheme.label("СОБЫТИЕ", "caps", 22, Palette.SILVER)
	_header.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_header)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	_source = UITheme.label("", "serif_italic", 15, Palette.TEXT_DIM)
	_source.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_source)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.custom_minimum_size = Vector2(48, 48)
	close.add_theme_font_size_override("font_size", 24)
	close.tooltip_text = "Закрыть (Esc)"
	close.pressed.connect(close_tablet)
	bar.add_child(close)
	root.add_child(bar)

	# арт 300 px
	_art_holder = Control.new()
	_art_holder.custom_minimum_size.y = 150
	_art_holder.clip_contents = true
	root.add_child(_art_holder)

	# название и текст
	var text_box := VBoxContainer.new()
	text_box.custom_minimum_size.y = 96
	text_box.add_theme_constant_override("separation", 2)
	_title = UITheme.label("", "title", 36, Palette.TEXT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_box.add_child(_title)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(1300, 0)
	_text.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_text.add_theme_font_size_override("normal_font_size", 19)
	text_box.add_child(_text)
	root.add_child(text_box)

	var sep := ColorRect.new()
	sep.color = Palette.LINE
	sep.custom_minimum_size.y = 1
	root.add_child(sep)

	# нижнее поле: подготовка | варианты
	var bottom := HBoxContainer.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.add_theme_constant_override("separation", 0)
	root.add_child(bottom)

	var left_margin := MarginContainer.new()
	left_margin.custom_minimum_size.x = 860
	for side in ["left", "right", "top", "bottom"]:
		left_margin.add_theme_constant_override("margin_" + side, 14)
	bottom.add_child(left_margin)
	var left := HBoxContainer.new()
	left.add_theme_constant_override("separation", 18)
	left_margin.add_child(left)
	_pocket = DropZone.new()
	_pocket.accepts = ["character"]
	_pocket.hint = "Поместите персонажа"
	_pocket.custom_minimum_size = CardView.SIZE_POCKET
	_pocket.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_pocket.dropped.connect(func(card: String) -> void: GameState.set_executor(event_id, card))
	left.add_child(_pocket)
	var prep := VBoxContainer.new()
	prep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prep.add_theme_constant_override("separation", 6)
	left.add_child(prep)
	_fan = DropZone.new()
	_fan.accepts = ["enhancement"]
	_fan.hint = "До трёх усилений"
	_fan.custom_minimum_size = Vector2(0, CardView.SIZE_FAN.y + 8)
	_fan.dropped.connect(_on_enh_dropped)
	prep.add_child(_fan)
	_stats_box = HBoxContainer.new()
	_stats_box.add_theme_constant_override("separation", 26)
	_stats_box.alignment = BoxContainer.ALIGNMENT_CENTER
	prep.add_child(_stats_box)
	_info_box = VBoxContainer.new()
	_info_box.add_theme_constant_override("separation", 4)
	prep.add_child(_info_box)

	var vsep := ColorRect.new()
	vsep.color = Palette.LINE
	vsep.custom_minimum_size.x = 1
	bottom.add_child(vsep)

	var right_margin := MarginContainer.new()
	right_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		right_margin.add_theme_constant_override("margin_" + side, 14)
	bottom.add_child(right_margin)
	_options_box = VBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 10)
	right_margin.add_child(_options_box)


func _process(_d: float) -> void:
	# планшет держим по центру при любом соотношении сторон
	var vp := get_viewport_rect().size
	_panel.position = Vector2(round((vp.x - _panel.size.x) / 2), 16)


func open(eid: String) -> void:
	event_id = eid
	GameState.concentration = {}
	GameState.ward = false
	visible = true
	var ev: Dictionary = ContentDB.data.events[eid]
	var num := str(ev.get("numeral", ""))
	var kind_name: String = {"story": "СЮЖЕТНОЕ СОБЫТИЕ", "reward": "НАГРАДНОЕ СОБЫТИЕ", "side": "СОБЫТИЕ", "random": "СЛУЧАЙНОЕ СОБЫТИЕ"}.get(ev.get("type", ""), "СОБЫТИЕ")
	_header.text = "%s%s" % [kind_name, (" · " + num) if num != "" else ""]
	_source.text = str(ev.get("source", ""))
	_title.text = str(ev.get("title", ""))
	_text.text = "[center]%s[/center]" % str(ev.get("text", ""))
	_build_art(ev)
	# если у события ещё нет черновика — ставим единственного свободного персонажа
	var d := GameState.draft(eid)
	if str(d.get("character", "")) == "":
		var chars := _alive_characters()
		if chars.size() == 1 and GameState.state.draft_event_of(chars[0]) == "":
			GameState.set_executor(eid, chars[0])
	refresh()
	AudioManager.play("open", -4.0)
	if not SettingsService.get_value("reduce_motion"):
		_panel.modulate.a = 0.0
		create_tween().tween_property(_panel, "modulate:a", 1.0, 0.22)


## Глобальный прямоугольник карты героя в кармашке (для облачка мыслей).
func pocket_rect() -> Rect2:
	return _pocket.get_global_rect()


func close_tablet() -> void:
	visible = false
	event_id = ""
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_tablet()
		get_viewport().set_input_as_handled()


func _alive_characters() -> Array:
	var out: Array = []
	for card: String in GameState.state.collection:
		if ContentDB.data.card_kind(card) == "character" and GameState.state.is_alive(card):
			out.append(card)
	return out


func _build_art(ev: Dictionary) -> void:
	for c in _art_holder.get_children():
		c.queue_free()
	# своя карта события из дизайна (art/cards/<ID>.webp), иначе арт из данных
	var art: String = "res://art/cards/%s.webp" % ev.get("id", "")
	if not ResourceLoader.exists(art):
		art = ev.get("art", "")
	if art != "" and ResourceLoader.exists(art):
		var tr := TextureRect.new()
		tr.texture = _crop_band(load(art))
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		_art_holder.add_child(tr)
	else:
		var bd := MapBackdrop.new()
		bd.region = str(ev.get("region", "mountain_pass"))
		bd.snow = true
		bd.set_anchors_preset(Control.PRESET_FULL_RECT)
		_art_holder.add_child(bd)
	var fade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(Palette.BG_PANEL, 0.0))
	g.set_color(1, Palette.BG_PANEL)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.55)
	gt.fill_to = Vector2(0, 1)
	fade.texture = gt
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art_holder.add_child(fade)


## Панорамная полоса из вертикального арта карточки (без надписи внизу карты).
func _crop_band(tex: Texture2D) -> Texture2D:
	var at := AtlasTexture.new()
	at.atlas = tex
	var s := tex.get_size()
	at.region = Rect2(0, s.y * 0.08, s.x, s.y * 0.42)
	return at


func _on_enh_dropped(card: String) -> void:
	var err := GameState.attach(event_id, card)
	if err != "":
		EventBus.toast.emit(err)


func refresh() -> void:
	if event_id == "" or GameState.state == null:
		return
	var s := GameState.state
	if not s.is_event_active(event_id):
		close_tablet()
		return
	var d := GameState.draft(event_id)
	var executor: String = d.get("character", "")
	# кармашек
	for c in _pocket.get_children():
		c.queue_free()
	if executor != "":
		var cv := CardView.make(executor, CardView.SIZE_POCKET, true)
		cv.hover_lift = false
		cv.tooltip_text = " "
		cv.clicked.connect(func(_id: String) -> void: GameState.clear_executor(event_id))
		_pocket.add_child(cv)
	_pocket.queue_redraw()
	# веер
	for c in _fan.get_children():
		c.queue_free()
	var enh: Array = d.get("enhancements", [])
	for i in enh.size():
		var ec := CardView.make(str(enh[i]), CardView.SIZE_FAN, true)
		ec.position = Vector2(20 + i * CardView.SIZE_FAN.x * 0.6, 4)
		ec.rotation = deg_to_rad(-5 + i * 5)
		ec.clicked.connect(func(id: String) -> void: GameState.detach(event_id, id))
		_fan.add_child(ec)
	_fan.queue_redraw()

	var previews := GameState.preview(event_id)
	_build_stats(executor, previews)
	_build_info(executor)
	_build_options(previews, executor != "")


func _build_stats(executor: String, previews: Array) -> void:
	for c in _stats_box.get_children():
		c.queue_free()
	var base := {}
	var totals := {}
	if executor != "":
		var r := StatResolver.resolve(ContentDB.data, GameState.state, executor, GameState.draft(event_id)["enhancements"],
			ContentDB.data.events[event_id], {}, GameState.concentration)
		base = r["base"]
		totals = r["totals"]
	for st: String in ["power", "will", "cunning"]:
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 2)
		var icon := TextureRect.new()
		icon.texture = UITheme.stat_icon(st)
		icon.custom_minimum_size = Vector2(46, 46)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		col.add_child(icon)
		var name := UITheme.label(Palette.STAT_NAMES[st].to_upper(), "sans", 13, Palette.TEXT_DIM)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(name)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 4)
		if executor == "":
			row.add_child(UITheme.label("—", "title_bold", 26, Palette.TEXT_DIM))
		else:
			var b := int(base.get(st, 0))
			var t := int(totals.get(st, 0))
			var colr := Palette.STAT_NEUTRAL
			if t > b:
				colr = Palette.STAT_UP
			elif t < b:
				colr = Palette.STAT_DOWN
			var val := UITheme.label(("%d → %d" % [b, t]) if t != b else str(t), "title_bold", 26, colr)
			val.tooltip_text = _breakdown(st, b, previews)
			val.mouse_filter = Control.MOUSE_FILTER_STOP
			row.add_child(val)
			var n := int(GameState.concentration.get(st, 0))
			if n > 0:
				var minus := _mini_button("−◈", "Отменить Концентрацию")
				minus.pressed.connect(_on_unconcentrate.bind(st))
				row.add_child(minus)
			if n < TurnResolver.CONCENTRATION_MAX:
				var plus := _mini_button("+◈", "Концентрация: +1 %s до конца события за 3 маны" % Palette.STAT_NAMES[st])
				plus.pressed.connect(_on_concentrate.bind(st))
				row.add_child(plus)
		col.add_child(row)
		_stats_box.add_child(col)


func _on_unconcentrate(st: String) -> void:
	GameState.remove_concentration(st)
	refresh()


func _on_concentrate(st: String) -> void:
	var err := GameState.add_concentration(st)
	if err != "":
		EventBus.toast.emit(err)
	refresh()


func _mini_button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Palette.MANA)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


func _breakdown(st: String, base: int, previews: Array) -> String:
	var lines: Array[String] = ["База: %d" % base]
	if not previews.is_empty():
		for p: Dictionary in previews[0].get("parts", []):
			if p["stat"] == st:
				lines.append("%s: %+d" % [p["source"], int(p["value"])])
	lines.append("(бонусы по тегам варианта учитываются в его шансе)")
	return "\n".join(lines)


func _build_info(executor: String) -> void:
	for c in _info_box.get_children():
		c.queue_free()
	if executor == "":
		_info_box.add_child(UITheme.label("Перетащите персонажа из нижней панели в кармашек или щёлкните по нему.", "sans", 16, Palette.TEXT_DIM))
		return
	var c := ContentDB.data
	var ch := GameState.state.character(executor)
	var abil: Array = []
	for aid: String in ch.get("abilities", []):
		abil.append("✦ " + c.card_name(aid))
	if not abil.is_empty():
		_info_box.add_child(UITheme.label("Способности: " + ", ".join(abil), "sans", 16, Palette.SILVER))
	var traumas: Array = ch.get("traumas", [])
	if traumas.is_empty():
		_info_box.add_child(UITheme.label("Травм нет", "sans", 16, Palette.TEXT_DIM))
	else:
		var tn: Array = []
		for t: String in traumas:
			tn.append(c.card_name(t))
		_info_box.add_child(UITheme.label("Травмы: " + ", ".join(tn), "sans", 16, Palette.STAT_DOWN))
	var n := TraumaRules.counted(traumas)
	var dc := TraumaRules.death_chance(n + 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var dl := UITheme.label("☠ Шанс смерти при новой травме: %d%%" % dc if dc > 0 else "Смерти при провале не будет (травм меньше трёх)", "sans", 16, Palette.TRAUMA_BRIGHT if dc > 0 else Palette.TEXT_DIM)
	row.add_child(dl)
	if dc > 0:
		var ward := CheckBox.new()
		ward.text = "Оберег ◈4 (шанс ÷2)"
		ward.button_pressed = GameState.ward
		ward.add_theme_color_override("font_color", Palette.MANA)
		ward.tooltip_text = "Мана списывается, только если бросок смерти случится"
		ward.toggled.connect(func(on: bool) -> void: GameState.ward = on)
		row.add_child(ward)
	_info_box.add_child(row)
	var mana := int(GameState.state.resources.get("mana", 0))
	var conc := 0
	for st: String in GameState.concentration:
		conc += int(GameState.concentration[st])
	if conc > 0:
		_info_box.add_child(UITheme.label("Концентрация: −%d маны при нажатии варианта (есть %d)" % [conc * 3, mana], "sans", 15, Palette.MANA))


func _build_options(previews: Array, has_executor: bool) -> void:
	for c in _options_box.get_children():
		c.queue_free()
	var s := GameState.state
	var executor: String = GameState.draft(event_id).get("character", "")
	var ability_reveals := 0
	if executor != "":
		for aid: String in s.character(executor).get("abilities", []):
			ability_reveals += int(ContentDB.data.abilities.get(aid, {}).get("reveal", 0))
	for i in previews.size():
		var info: Dictionary = previews[i]
		var oid := str(info["option"]["id"])
		var revealed := s.revealed.has(oid)
		if not revealed and ability_reveals > 0:
			revealed = true
			ability_reveals -= 1
		var row := OptionRow.new()
		_options_box.add_child(row)
		row.setup(i, event_id, info, has_executor, revealed)
		row.chosen.connect(func(opt: String) -> void: resolve_requested.emit(event_id, opt))
		row.foresee.connect(_on_foresee)


func _on_foresee(opt: String) -> void:
	var err := GameState.foresee(opt)
	if err != "":
		EventBus.toast.emit(err)
