class_name CardInspector
extends Control
## Планшет карты: крупная карта слева, справа — две вкладки.
## «Описание» — что это и как работает (характеристики, черты, способности, износ, теги, как использовать).
## «Сюжет» — «По книге» (data/lore.json из проектных документов) и «В вашем прохождении» (журнал карты).
## Закрывается по ✕, Esc или щелчку по затемнению.

signal closed

var card_id := ""
var _tab := "info"
var _body: RichTextLabel
var _tags_row: HFlowContainer
var _tabs: Array = []
var _info: TagInfoPanel


static func open_for(parent: Node, id: String) -> CardInspector:
	var ci := CardInspector.new()
	ci.card_id = id
	parent.add_child(ci)
	return ci


func _ready() -> void:
	top_level = true
	z_index = 70
	position = Vector2.ZERO
	size = get_viewport_rect().size
	theme = UITheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.position = Vector2(-200, -200)
	dim.size = size + Vector2(400, 400)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(120, 60)
	panel.size = Vector2(1680, 960)
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.055, 0.058, 0.075, 0.98), Palette.SILVER.darkened(0.35), 1, 6, 0))
	add_child(panel)
	var frame := Control.new()
	frame.custom_minimum_size = panel.size
	panel.add_child(frame)
	# крупная карта
	var cv := CardView.make(card_id, Vector2(450, 772), false)
	cv.hover_lift = false
	cv.smoke_on_hover = false
	cv.position = Vector2(40, 94)
	frame.add_child(cv)
	var c := ContentDB.data
	var kind := c.card_kind(card_id)
	# шапка
	var title := UITheme.label(c.card_name(card_id), "title_bold", 42, Palette.TEXT)
	title.position = Vector2(530, 24)
	frame.add_child(title)
	var sub := UITheme.label(_type_line(kind), "sans", 21, Palette.TEXT_DIM)
	sub.position = Vector2(534, 82)
	frame.add_child(sub)
	var close := Button.new()
	close.text = "✕"
	close.position = Vector2(1606, 18)
	close.custom_minimum_size = Vector2(52, 52)
	close.add_theme_font_size_override("font_size", 24)
	close.pressed.connect(_close)
	frame.add_child(close)
	# вкладки
	var tabs := HBoxContainer.new()
	tabs.position = Vector2(530, 128)
	tabs.add_theme_constant_override("separation", 8)
	frame.add_child(tabs)
	for t: Array in [["ОПИСАНИЕ", "info", _emblem_for(kind)], ["СЮЖЕТ", "story", "story"]]:
		var b := Button.new()
		b.text = t[0]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(230, 50)
		b.add_theme_font_override("font", UITheme.font("caps"))
		b.add_theme_font_size_override("font_size", 20)
		var em := UITheme.emblem(t[2])
		if em:
			b.icon = em
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 34)
		b.set_meta("tab", t[1])
		b.pressed.connect(_set_tab.bind(t[1]))
		tabs.add_child(b)
		_tabs.append(b)
	var line := ColorRect.new()
	line.color = Palette.LINE
	line.position = Vector2(530, 186)
	line.size = Vector2(1110, 1)
	frame.add_child(line)
	# теги (только во вкладке «Описание»)
	_tags_row = HFlowContainer.new()
	_tags_row.position = Vector2(530, 200)
	_tags_row.custom_minimum_size = Vector2(1110, 0)
	_tags_row.add_theme_constant_override("h_separation", 12)
	_tags_row.add_theme_constant_override("v_separation", 4)
	frame.add_child(_tags_row)
	# текст
	var sc := ScrollContainer.new()
	sc.name = "Scroll"
	sc.position = Vector2(530, 250)
	sc.custom_minimum_size = Vector2(1110, 680)
	sc.size = Vector2(1110, 680)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(sc)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.custom_minimum_size = Vector2(1090, 0)
	_body.add_theme_font_size_override("normal_font_size", 21)
	_body.add_theme_font_size_override("bold_font_size", 21)
	_body.meta_underlined = false
	sc.add_child(_body)
	_info = TagInfoPanel.new()
	add_child(_info)
	_set_tab("info")
	AudioManager.play("open", -6.0, 1.1)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()


func _close() -> void:
	closed.emit()
	queue_free()


func _set_tab(t: String) -> void:
	_tab = t
	for b: Button in _tabs:
		b.button_pressed = b.get_meta("tab") == t
	for ch in _tags_row.get_children():
		ch.queue_free()
	var sc: ScrollContainer = _body.get_parent()
	if t == "info":
		var tags := _combat_tags()
		_tags_row.visible = not tags.is_empty()
		for tag: String in tags:
			var chip := TagChip.make(tag, 19, false)
			chip.hovered.connect(_on_chip_hover)
			_tags_row.add_child(chip)
		sc.position.y = 250 if not tags.is_empty() else 206
		_body.text = _info_text()
	else:
		_tags_row.visible = false
		sc.position.y = 206
		_body.text = _story_text()
	sc.scroll_vertical = 0


func _on_chip_hover(tag: String, on: bool) -> void:
	if on:
		_info.show_tag(tag, get_global_mouse_position())
	else:
		_info.visible = false


# --- содержимое ------------------------------------------------------------------

func _def() -> Dictionary:
	var c := ContentDB.data
	match c.card_kind(card_id):
		"character": return c.characters.get(card_id, {})
		"enhancement": return c.enhancements.get(card_id, {})
		"initiator": return c.initiators.get(card_id, {})
		"trauma": return c.traumas.get(card_id, {})
		"enemy": return c.enemies.get(card_id, {})
	return c.events.get(card_id, {})


func _emblem_for(kind: String) -> String:
	return {"character": "character", "enhancement": "enhancement", "enemy": "monster"}.get(kind, "story")


func _type_line(kind: String) -> String:
	var d := _def()
	var s := GameState.state
	match kind:
		"character":
			var st := ContentDB.data.stage_name(card_id, str(s.character(card_id).get("stage", ""))) if s else ""
			return "Персонаж" + (" · %s" % st if st != "" else "") + (" · погиб" if s and s.characters.has(card_id) and not s.is_alive(card_id) else "")
		"enhancement":
			return "Усиление · " + {"knowledge": "Знание", "memory": "Воспоминание", "improvised": "Подручное"}.get(d.get("origin", ""), "предмет")
		"initiator":
			return "Инициатор · одноразовый"
		"trauma":
			return "Травма"
		"enemy":
			return "Противник · %s · %s" % [CardView.RANKS[clampi(int(d.get("rank", 0)), 0, 6)], CardView.CLASSES[clampi(int(d.get("class", 1)), 1, 7)]]
	return "Событие"


func _combat_tags() -> Array:
	var d := _def()
	var kind := ContentDB.data.card_kind(card_id)
	if kind == "character":
		var s := GameState.state
		var stage: String = s.character(card_id).get("stage", "") if s else ""
		return Array(d.get("stages", {}).get(stage, {}).get("tags", d.get("tags", [])))
	if kind in ["enhancement", "enemy"]:
		return Array(d.get("tags", []))
	return []


func _h(text: String) -> String:
	return "[font_size=25][color=#C9CED6]%s[/color][/font_size]\n" % text


func _dim(text: String) -> String:
	return "[color=#9A9CA6]%s[/color]" % text


func _info_text() -> String:
	var c := ContentDB.data
	var d := _def()
	var s := GameState.state
	var kind := c.card_kind(card_id)
	var out: Array[String] = []
	match kind:
		"character":
			var ch: Dictionary = s.character(card_id) if s else {}
			if str(d.get("role", "")) != "":
				out.append(str(d["role"]))
			var base := c.stage_stats(card_id, str(ch.get("stage", "")))
			var perm: Dictionary = ch.get("perm", {})
			var mods := {"power": 0, "will": 0, "cunning": 0}
			for t: String in ch.get("traumas", []):
				for st: String in c.traumas.get(t, {}).get("mods", {}):
					mods[st] = int(mods.get(st, 0)) + int(c.traumas[t]["mods"][st])
			var rows: Array = []
			for st: String in ["power", "will", "cunning"]:
				var b := int(base.get(st, 0))
				var p := int(perm.get(st, 0))
				var m := int(mods.get(st, 0))
				var parts := "%d" % b
				if p != 0:
					parts += " %+d навсегда" % p
				if m != 0:
					parts += " [color=#B65F63]%+d травмы[/color]" % m
				rows.append("[b]%s[/b]  %s  →  [b]%d[/b]" % [Palette.STAT_NAMES.get(st, st), parts, maxi(0, b + p + m)])
			out.append(_h("Характеристики") + "\n".join(rows))
			var traits: Array = []
			for tr: Dictionary in d.get("traits", []):
				traits.append("• [b]%s[/b] — %s" % [tr.get("name", ""), tr.get("text", "")])
			if not traits.is_empty():
				out.append(_h("Черты") + "\n".join(traits))
			var abil: Array = []
			for aid: String in ch.get("abilities", []):
				var a: Dictionary = c.abilities.get(aid, {})
				abil.append("✦ [b]%s[/b] — %s" % [a.get("name", aid), a.get("text", "")])
			if not abil.is_empty():
				out.append(_h("Способности") + "\n".join(abil))
			var traumas: Array = []
			for t: String in ch.get("traumas", []):
				var td: Dictionary = c.traumas.get(t, {})
				var ms: Array = []
				for st2: String in td.get("mods", {}):
					ms.append("%+d %s" % [int(td["mods"][st2]), Palette.STAT_NAMES.get(st2, st2)])
				traumas.append("[color=#B65F63]✖ %s[/color] — %s" % [td.get("name", t), ", ".join(ms)])
			if not traumas.is_empty():
				var dc := TraumaRules.death_chance(TraumaRules.counted(ch.get("traumas", [])) + 1)
				out.append(_h("Травмы") + "\n".join(traumas) + ("\n[color=#B65F63]☠ Шанс смерти при следующей травме: %d%%[/color]" % dc if dc > 0 else ""))
			var sup: Array = d.get("support_tags", [])
			if not sup.is_empty():
				out.append(_h("В бою в поддержке") + "Встаёт рядом с исполнителем и добавляет теги: " + ", ".join(sup))
			out.append(_h("Как использовать") + _dim("Сделайте исполнителем события: перетащите карту в кармашек планшета или нажмите на неё, когда событие открыто. В бою может стоять в поддержке (до двух союзников)."))
		"enhancement":
			out.append(_h("Эффект") + str(d.get("text", "")))
			if s and WearRules.wears(c, s, card_id):
				out.append(_h("Износ") + "Шанс поломки после следующего использования: [b]%d%%[/b]. Растёт с каждым событием; сломанная карта исчезает. Кузнец сбрасывает износ." % WearRules.current(s, card_id))
			elif bool(d.get("wears", true)):
				out.append(_h("Износ") + "Сейчас не изнашивается.")
			else:
				out.append(_h("Износ") + "Не изнашивается.")
			out.append(_h("Как использовать") + _dim("Приложите к событию: перетащите в веер планшета или нажмите на карту, когда событие открыто. Не больше трёх усилений на событие."))
		"initiator":
			out.append(str(d.get("text", "")))
			var ev: Dictionary = c.events.get(str(d.get("event", "")), {})
			if not ev.is_empty():
				out.append(_h("Создаёт событие") + "«%s»" % ev.get("title", ""))
			out.append(_h("Как использовать") + _dim("Перетащите на карту мира — появится событие, а карта исчезнет."))
		"trauma":
			var ms2: Array = []
			for st3: String in d.get("mods", {}):
				ms2.append("%+d %s" % [int(d["mods"][st3]), Palette.STAT_NAMES.get(st3, st3)])
			out.append(_h("Эффект") + ", ".join(ms2))
		"enemy":
			out.append("%s · %s" % [{"normal": "обычный", "elite": "элита", "boss": "босс"}.get(d.get("kind", "normal"), ""), _type_line(kind)])
			out.append(_h("Добыча") + "✧ %d осколков душ" % int(d.get("shards", 0)))
	var lore: Dictionary = c.lore.get(card_id, {})
	if kind == "trauma" and str(lore.get("text", "")) != "":
		out.insert(0, str(lore["text"]))
	return "\n\n".join(out)


func _story_text() -> String:
	var c := ContentDB.data
	var d := _def()
	var lore: Dictionary = c.lore.get(card_id, {})
	var out: Array[String] = []
	var book: Array[String] = []
	if str(lore.get("text", "")) != "":
		book.append(str(lore["text"]))
	else:
		book.append(_dim("В книгах эта карта отдельно не описана — это игровая адаптация."))
	if str(lore.get("extra", "")) != "":
		book.append(str(lore["extra"]))
	var src := str(lore.get("source", d.get("source", "")))
	if src != "":
		book.append(_dim("Источник: " + src))
	if bool(lore.get("adaptation", false)):
		book.append(_dim("Игровая адаптация на основе книжных эпизодов."))
	out.append(_h("По книге") + "\n\n".join(book))
	out.append(_h("В вашем прохождении") + _run_story())
	return "\n\n".join(out)


## Журнал карты в текущем прохождении: участие в событиях и отметки (получение, травмы, поломка, гибель).
func _run_story() -> String:
	var s := GameState.state
	if s == null:
		return _dim("Прохождение не начато.")
	var c := ContentDB.data
	var rows: Array = []
	for i in s.log.size():
		var e: Dictionary = s.log[i]
		if not e.has("event"):
			continue
		var role := ""
		if str(e.get("executor", "")) == card_id:
			role = "исполнитель"
		elif Array(e.get("enh", [])).has(card_id):
			role = "усиление"
		if role == "":
			continue
		var ev: Dictionary = c.events.get(str(e["event"]), {})
		var o := c.option(str(e["event"]), str(e.get("option", "")))
		rows.append({"week": int(e["week"]), "seq": i, "kind": 0, "text": "«%s» — %s · %s · %s" % [ev.get("title", e["event"]), o.get("label", ""), role,
			"[color=#9FC29A]успех[/color]" if e.get("success", false) else "[color=#B65F63]провал[/color]"]})
	for n: Dictionary in s.card_log:
		if str(n.get("card", "")) == card_id:
			rows.append({"week": int(n.get("week", 0)), "seq": int(n.get("seq", 0)), "kind": 1, "text": str(n.get("text", ""))})
	if rows.is_empty():
		return _dim("Вы ещё не встречали этого противника." if c.card_kind(card_id) == "enemy" else "Пока эта карта не участвовала в событиях.")
	# по неделям; внутри недели — в порядке журнала, событие раньше своих последствий
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return [int(a["week"]), int(a["seq"]), int(a["kind"])] < [int(b["week"]), int(b["seq"]), int(b["kind"])])
	var lines: Array = []
	for r: Dictionary in rows:
		lines.append("[color=#B89A5E]Неделя %d[/color]  %s" % [r["week"], r["text"]])
	return "\n".join(lines)
