class_name OptionRow
extends PanelContainer
## Строка варианта: название, требования (◆/!), шкала шанса, значки последствий, стрелка.

signal chosen(option_id: String)
signal foresee(option_id: String)

var index := 0
var event_id := ""
var info: Dictionary = {}
var has_executor := false
var revealed := false
var _bar: ChanceBar
var _built := false


func _ready() -> void:
	custom_minimum_size = Vector2(0, 124)


func setup(p_index: int, p_event_id: String, p_info: Dictionary, p_has_executor: bool, p_revealed: bool) -> void:
	index = p_index
	event_id = p_event_id
	var prev_chance := int(info.get("chance", 0)) if _built else -1
	info = p_info
	has_executor = p_has_executor
	revealed = p_revealed
	_rebuild(prev_chance)


func _rebuild(prev_chance: int) -> void:
	for c in get_children():
		c.queue_free()
	_built = true
	var o: Dictionary = info["option"]
	var story := bool(o.get("story", false))
	var done := bool(info.get("done", false))
	var blockers: Array = info.get("blockers", [])
	var style := UITheme.box(Palette.BG_RAISED, Palette.GOLD if story else Palette.LINE, 2 if story else 1, 4, 14)
	if story:
		style.border_width_left = 4
	add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)

	# заголовок
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(UITheme.label("ВЫБОР %d" % (index + 1), "sans_bold", 15, Palette.GOLD if story else Palette.TEXT_DIM))
	var title := UITheme.label(str(o.get("label", "")), "title", 24, Palette.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	head.add_child(title)
	if story:
		head.add_child(UITheme.label("📖 Продвигает историю", "sans", 14, Palette.GOLD))
	col.add_child(head)

	# требования и шанс
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 10)
	col.add_child(mid)
	var check: String = o.get("check", "stat")
	var req: Dictionary = info.get("req", {})
	var totals: Dictionary = info.get("totals", {})
	if check in ["stat", "gate_stat"]:
		for st: String in ["power", "will", "cunning"]:
			var need := int(req.get(st, 0))
			if need <= 0:
				continue
			var icon := TextureRect.new()
			icon.texture = UITheme.stat_icon(st)
			icon.custom_minimum_size = Vector2(30, 30)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.tooltip_text = Palette.STAT_NAMES[st]
			mid.add_child(icon)
			var met := has_executor and int(totals.get(st, 0)) >= need
			var mark := "◆" if met else "!"
			var col_req := Palette.REQ_MET if met else Palette.REQ_MISS
			if not has_executor:
				col_req = Palette.TEXT_DIM
				mark = ""
			mid.add_child(UITheme.label("%d %s" % [need, mark], "title_bold", 22, col_req))
	elif check == "combat":
		var spec: Dictionary = o.get("combat", {})
		var names: Array = []
		for en: String in spec.get("enemies", []):
			names.append(ContentDB.data.card_name(en))
		var counts := {}
		for nme: String in names:
			counts[nme] = int(counts.get(nme, 0)) + 1
		var parts: Array = []
		for nme: String in counts:
			parts.append(nme + (" ×%d" % counts[nme] if int(counts[nme]) > 1 else ""))
		mid.add_child(UITheme.label("⚔ Бой: " + ", ".join(parts), "sans_bold", 16, Palette.STAT_DOWN))
	else:
		mid.add_child(UITheme.label("Без броска", "sans", 16, Palette.TEXT_DIM))
	var cost: Dictionary = o.get("cost", {})
	for r: String in cost:
		mid.add_child(UITheme.label(("✧ %d" if r == "shards" else "◈ %d") % int(cost[r]), "sans_bold", 16, Palette.COINS if r == "shards" else Palette.MANA))
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 8
	mid.add_child(spacer)
	_bar = ChanceBar.new()
	_bar.custom_minimum_size = Vector2(300, 18)
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_child(_bar)
	var chance := int(info.get("chance", 0))
	if has_executor and blockers.is_empty():
		_bar.set_chance(chance, prev_chance >= 0 and prev_chance != chance)
		if prev_chance < 0:
			_bar.set_chance(chance, false)
		mid.add_child(UITheme.label("%d%%" % chance, "title_bold", 26, Palette.TEXT))
		mid.add_child(UITheme.label("1-й раунд" if check == "combat" else ChanceCalculator.label(chance), "sans", 14, Palette.TEXT_DIM))
	else:
		_bar.set_chance(0, false)
		mid.add_child(UITheme.label("—", "title_bold", 26, Palette.TEXT_DIM))

	# последствия
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	col.add_child(bottom)
	if done:
		bottom.add_child(UITheme.label("✓ Выполнено", "sans_bold", 16, Palette.STAT_UP))
	elif not blockers.is_empty():
		bottom.add_child(UITheme.label("🔒 " + "; ".join(blockers), "sans", 16, Palette.REQ_MISS))
	else:
		var ev: Dictionary = ContentDB.data.events.get(event_id, {})
		var effects: Array = o.get("on_success", [])
		var summary := EffectText.summarize(ContentDB.data, effects, revealed)
		if summary == "—" and story:
			summary = "история продолжится"
		bottom.add_child(UITheme.label("Успех: " + summary, "sans", 15, Palette.TEXT if revealed else Palette.TEXT_DIM))
		if not revealed and not effects.is_empty():
			var fs := Button.new()
			fs.text = "?◈ 1"
			fs.tooltip_text = "Прозрение: потратить 1 ману и раскрыть последствия"
			fs.add_theme_font_size_override("font_size", 14)
			fs.pressed.connect(func() -> void: foresee.emit(str(o["id"])))
			bottom.add_child(fs)
		var fail := EffectText.failure(ContentDB.data, ev, o)
		var fl := UITheme.label("·  Провал: " + fail, "sans", 15, Palette.STAT_DOWN)
		bottom.add_child(fl)

	# стрелка
	var go := Button.new()
	go.text = "›"
	go.custom_minimum_size = Vector2(52, 52)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.add_theme_font_override("font", UITheme.font("title_bold"))
	go.add_theme_font_size_override("font_size", 34)
	var circle := UITheme.box(Palette.BG_PANEL, Palette.GOLD if story else Palette.SILVER, 2, 26, 0)
	go.add_theme_stylebox_override("normal", circle)
	var circle_h := UITheme.box(Palette.BG_RAISED, Palette.TEXT, 2, 26, 0)
	go.add_theme_stylebox_override("hover", circle_h)
	go.disabled = done or not blockers.is_empty() or not has_executor
	go.tooltip_text = "Поместите персонажа" if not has_executor else ("Выполнить" if not go.disabled else "")
	go.pressed.connect(func() -> void: chosen.emit(str(o["id"])))
	row.add_child(go)
	modulate = Color(1, 1, 1, 0.55) if done else Color.WHITE
