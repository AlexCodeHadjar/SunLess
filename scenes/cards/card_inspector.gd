class_name CardInspector
extends Control
## Планшет карты: крупная карта слева, справа — вкладки «Описание» и «Сюжет».
## Слева вверху — эмблема типа карты (наведение — что это за тип).
## У персонажа: характеристики иконками (наведение — что это и из чего складывается),
## теги (наведение — что дают), кармашек усилений (прикладываются к событию сами).
## «Сюжет» — «По книге» (data/lore.json) и «В вашем прохождении» (журнал карты).
## Закрывается по ✕, Esc или щелчку по затемнению.

signal closed

const TYPE_TEXT := {
	"character": "[b]Персонаж[/b]\nГерой отряда. Его Сила, Воля и Хитрость решают этапы миссий, травмы ложатся на него, в автобое он — ведущий или союзник в поддержке. Смерть навсегда.",
	"enhancement": "[b]Усиление[/b]\nПредмет, Воспоминание или знание. Лежит в кармашке героя (до трёх) и добавляет характеристики и теги. Предметы изнашиваются и могут сломаться.",
	"trauma": "[b]Травма[/b]\nПоследствие провала. Снижает характеристики персонажа, пока её не вылечат. С третьей травмы каждая новая может убить.",
	"enemy": "[b]Противник[/b]\nКошмарное существо или враг. Сила в бою зависит от ранга, класса и тегов; раны сохраняются между встречами.",
	"ability": "[b]Способность[/b]\nВрождённый дар или приобретённое умение героя. Работает само — не занимает кармашек и не изнашивается.",
	"mission": "[b]Миссия[/b]
Задание на карте главы: прочтите описание и слухи, соберите отряд и отправьте его.",
}
const STAT_TEXT := {
	"power": "[b]Сила[/b] — физическая мощь, скорость, бой, грубое действие.",
	"will": "[b]Воля[/b] — стойкость, решимость, сопротивление боли, страху и ментальному воздействию.",
	"cunning": "[b]Хитрость[/b] — наблюдательность, разведка, обман, анализ, скрытность, импровизация.",
}
const POCKET_MAX := 3

var card_id := ""
var _tab := "info"
var _frame: Control
var _content: Control
var _tabs: Array = []
var _info: TagInfoPanel
var _hint: PanelContainer
var _hint_label: RichTextLabel
var _card: CardView


static func open_for(parent: Node, id: String) -> CardInspector:
	var ci := CardInspector.new()
	ci.card_id = id
	parent.add_child(ci)
	return ci


func _ready() -> void:
	add_to_group(HintTargets.LAYER)
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
	panel.position = Vector2(120, 50)
	panel.size = Vector2(1680, 980)
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.055, 0.058, 0.075, 0.98), Palette.SILVER.darkened(0.35), 1, 6, 0))
	add_child(panel)
	_frame = Control.new()
	_frame.custom_minimum_size = panel.size
	panel.add_child(_frame)
	var c := ContentDB.data
	var kind := c.card_kind(card_id)
	if kind == "" and c.missions.has(card_id):
		kind = "mission"
	# эмблема типа карты
	var type_icon := TextureRect.new()
	type_icon.texture = UITheme.emblem(_emblem_for(kind))
	type_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	type_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	type_icon.position = Vector2(34, 18)
	type_icon.size = Vector2(62, 62)
	type_icon.mouse_filter = Control.MOUSE_FILTER_STOP
	type_icon.mouse_default_cursor_shape = Control.CURSOR_HELP
	type_icon.mouse_entered.connect(_show_hint.bind(TYPE_TEXT.get(kind, "")))
	type_icon.mouse_exited.connect(_hide_hint)
	_frame.add_child(type_icon)
	var type_name := UITheme.label(TYPE_TEXT.get(kind, "").get_slice("\n", 0).replace("[b]", "").replace("[/b]", "").to_upper(), "caps", 18, Palette.SILVER.darkened(0.15))
	type_name.position = Vector2(106, 36)
	_frame.add_child(type_name)
	# крупная карта
	_card = CardView.make(card_id, Vector2(450, 772), false)
	_card.hover_lift = false
	_card.smoke_on_hover = false
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE   # крупная карта не наклоняется за курсором
	_card.position = Vector2(40, 96)
	_frame.add_child(_card)
	# шапка
	var title := UITheme.label(c.card_name(card_id), "title_bold", 42, Palette.TEXT)
	title.position = Vector2(530, 20)
	_frame.add_child(title)
	var sub := UITheme.label(_type_line(kind), "sans", 21, Palette.TEXT_DIM)
	sub.position = Vector2(534, 78)
	_frame.add_child(sub)
	var close := Button.new()
	close.text = "✕"
	close.position = Vector2(1606, 16)
	close.custom_minimum_size = Vector2(52, 52)
	close.add_theme_font_size_override("font_size", 24)
	close.pressed.connect(_close)
	_frame.add_child(close)
	var tabs := HBoxContainer.new()
	tabs.position = Vector2(530, 120)
	tabs.add_theme_constant_override("separation", 8)
	_frame.add_child(tabs)
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
	line.position = Vector2(530, 178)
	line.size = Vector2(1110, 1)
	_frame.add_child(line)
	_content = Control.new()
	_content.position = Vector2(530, 190)
	_content.size = Vector2(1110, 780)
	_frame.add_child(_content)
	# подсказки поверх планшета
	_info = TagInfoPanel.new()
	add_child(_info)
	_info.z_index = 90   # после _ready: панель сама ставит себе 60
	_hint = PanelContainer.new()
	_hint.top_level = true
	_hint.z_index = 90
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := UITheme.box(Color(0.06, 0.06, 0.08, 0.97), Palette.SILVER.darkened(0.3), 1, 6, 16)
	st.shadow_color = Color(0, 0, 0, 0.6)
	st.shadow_size = 16
	_hint.add_theme_stylebox_override("panel", st)
	_hint_label = RichTextLabel.new()
	_hint_label.bbcode_enabled = true
	_hint_label.fit_content = true
	_hint_label.scroll_active = false
	_hint_label.custom_minimum_size = Vector2(520, 0)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.add_theme_font_size_override("normal_font_size", 18)
	_hint_label.add_theme_font_size_override("bold_font_size", 19)
	_hint.add_child(_hint_label)
	_hint.visible = false
	add_child(_hint)
	EventBus.state_changed.connect(_on_state_changed)
	_set_tab("info")
	AudioManager.play("open", -6.0, 1.1)


func _on_state_changed() -> void:
	# кармашек изменился — обновляем карту (облик и теги) и вкладку
	if not is_inside_tree():
		return
	var pos := _card.position
	_card.queue_free()
	_card = CardView.make(card_id, Vector2(450, 772), false)
	_card.hover_lift = false
	_card.smoke_on_hover = false
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.position = pos
	_frame.add_child(_card)
	_set_tab(_tab)


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


func _show_hint(text: String) -> void:
	if text == "":
		return
	_hint_label.text = text
	_hint.visible = true
	await get_tree().process_frame
	if not is_instance_valid(_hint):
		return
	_hint.size = _hint.get_combined_minimum_size()
	var at := get_global_mouse_position()
	var vp := get_viewport_rect().size
	_hint.global_position = Vector2(clampf(at.x + 18, 8, vp.x - _hint.size.x - 8), clampf(at.y + 18, 8, vp.y - _hint.size.y - 8))


func _hide_hint() -> void:
	_hint.visible = false


func _set_tab(t: String) -> void:
	_tab = t
	for b: Button in _tabs:
		b.button_pressed = b.get_meta("tab") == t
	for ch in _content.get_children():
		ch.queue_free()
	_hide_hint()
	_info.visible = false
	if t == "info":
		_build_info()
	else:
		_add_text(_story_text(), 0.0, _content.size.y)


# --- вкладка «Описание» -----------------------------------------------------------

func _build_info() -> void:
	var c := ContentDB.data
	var kind := c.card_kind(card_id)
	var y := 0.0
	var is_hero := kind == "character" and GameState.state != null and GameState.state.characters.has(card_id)
	if is_hero:
		y = _build_stats(y)
	y = _build_tags(y)
	var pocket_h := 300.0 if is_hero and GameState.state.is_alive(card_id) else 0.0
	_add_text(_info_text(), y + 6.0, _content.size.y - y - 6.0 - pocket_h)
	if pocket_h > 0.0:
		_build_pocket(_content.size.y - pocket_h + 8.0)


func _add_text(bb: String, top: float, height: float) -> void:
	var sc := ScrollContainer.new()
	sc.position = Vector2(0, top)
	sc.custom_minimum_size = Vector2(1110, height)
	sc.size = Vector2(1110, height)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(sc)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.custom_minimum_size = Vector2(1090, 0)
	body.add_theme_font_size_override("normal_font_size", 21)
	body.add_theme_font_size_override("bold_font_size", 21)
	body.text = bb
	sc.add_child(body)


## Характеристики иконками: эмблема, итоговое число, изменение; наведение — описание и разбор.
func _build_stats(y: float) -> float:
	var parts := _stat_parts()
	var row := HBoxContainer.new()
	row.position = Vector2(0, y)
	row.add_theme_constant_override("separation", 34)
	_content.add_child(row)
	for st: String in ["power", "will", "cunning"]:
		var p: Dictionary = parts[st]
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		box.mouse_default_cursor_shape = Control.CURSOR_HELP
		box.mouse_entered.connect(_show_hint.bind(_stat_hint(st, p)))
		box.mouse_exited.connect(_hide_hint)
		row.add_child(box)
		var icon := TextureRect.new()
		icon.texture = UITheme.emblem(st)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.custom_minimum_size = Vector2(76, 76)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(col)
		var num := UITheme.label(str(int(p["total"])), "title_bold", 46, Palette.TEXT)
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(num)
		var delta := int(p["total"]) - int(p["base"])
		var dl := UITheme.label("%s  %s" % [Palette.STAT_NAMES.get(st, st), ("(%+d)" % delta) if delta != 0 else ""], "sans", 16,
			Palette.STAT_UP if delta > 0 else (Palette.STAT_DOWN if delta < 0 else Palette.TEXT_DIM))
		dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(dl)
	if GameState.state.is_alive(card_id) and TutorialRules.enabled(GameState.state, "panic"):
		var psy := PsycheRules.psyche(GameState.state, card_id)
		var cst := PsycheRules.crisis(GameState.state, card_id)
		_life_box(row, "panic", str(psy), PsycheRules.NAMES[cst].to_lower() if cst != "" else "психика · " + PsycheRules.word(psy),
			SquadLifeUI.hero_psyche_color(card_id), SquadLifeUI.panic_hint(card_id))
	if GameState.state.is_alive(card_id) and TutorialRules.enabled(GameState.state, "trust"):
		var top := TrustRules.top(ContentDB.data, GameState.state, card_id)
		var ends: Array = []
		for side: String in ["positive", "negative"]:
			if not Array(top[side]).is_empty():
				ends.append("%+d" % int(top[side][0]["value"]))
		_life_box(row, "trust", "  ".join(ends) if not ends.is_empty() else "—", "Доверие", Palette.SILVER, SquadLifeUI.trust_hint(card_id))
	return y + 92.0


## Значок «живого отряда» (паника / доверие) в строке характеристик; наведение — подробности.
func _life_box(row: HBoxContainer, m: String, big: String, small: String, col: Color, hint: String) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.mouse_default_cursor_shape = Control.CURSOR_HELP
	box.mouse_entered.connect(_show_hint.bind(hint))
	box.mouse_exited.connect(_hide_hint)
	row.add_child(box)
	box.add_child(SquadLifeUI.make(m, card_id))
	var col_box := VBoxContainer.new()
	col_box.add_theme_constant_override("separation", 0)
	col_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(col_box)
	var num := UITheme.label(big, "title_bold", 46 if m == "panic" else 38, Palette.TEXT)
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col_box.add_child(num)
	var dl := UITheme.label(small, "sans", 16, col)
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col_box.add_child(dl)


## Разбор характеристик персонажа вне события: база стадии, навсегда, кармашек, травмы; условные — отдельно.
func _stat_parts() -> Dictionary:
	return StatResolver.sheet(ContentDB.data, GameState.state, card_id, _pocket())


static func _cap(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1)


func _stat_hint(st: String, p: Dictionary) -> String:
	var lines: Array[String] = [STAT_TEXT.get(st, ""), ""]
	lines.append("База стадии «%s»: [b]%d[/b]" % [p["stage"], int(p["base"])])
	for l: Array in p["lines"]:
		var col := "#9FC29A" if int(l[1]) > 0 else "#B65F63"
		lines.append("[color=%s]%+d[/color]  %s" % [col, int(l[1]), l[0]])
	lines.append("Итог: [b]%d[/b]" % int(p["total"]))
	if not Array(p["cond"]).is_empty():
		lines.append("")
		lines.append("[color=#9A9CA6]Условные бонусы (в подходящих событиях):[/color]")
		for l2: Array in p["cond"]:
			lines.append("[color=#C9CED6]%+d[/color]  %s" % [int(l2[1]), l2[0]])
	return "\n".join(lines)


## Теги карты (наведение — что дают); у персонажа отдельно — теги от кармашка.
func _build_tags(y: float) -> float:
	var own := _combat_tags()
	var extra: Array = []
	for card: String in _pocket():
		for t: String in ContentDB.data.enhancements.get(card, {}).get("tags", []):
			if not own.has(t) and not extra.has(t):
				extra.append(t)
	if own.is_empty() and extra.is_empty():
		return y
	var flow := HFlowContainer.new()
	flow.position = Vector2(0, y)
	flow.custom_minimum_size = Vector2(1110, 0)
	flow.size = Vector2(1110, 0)
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 4)
	_content.add_child(flow)
	for t: String in own:
		var chip := TagChip.make(t, 19, false)
		chip.hovered.connect(_on_chip_hover)
		flow.add_child(chip)
	if not extra.is_empty():
		flow.add_child(UITheme.label("  от кармашка:", "sans", 16, Palette.GOLD.darkened(0.1)))
		for t2: String in extra:
			var chip2 := TagChip.make(t2, 19, false)
			chip2.hovered.connect(_on_chip_hover)
			flow.add_child(chip2)
	var rows := 1 + int((own.size() + extra.size()) / 7)
	y += rows * 30.0 + 8.0
	if ContentDB.data.card_kind(card_id) == "character" and GameState.state != null and GameState.state.characters.has(card_id) and TutorialRules.enabled(GameState.state, "growth"):
		y = _build_growth(y)
	return y


## Рост тегов (docs/16 §8): опыт каждого тега, «опытный», развитие; наведение — что будет дальше.
func _build_growth(y: float) -> float:
	var c := ContentDB.data
	var s := GameState.state
	var tags: Array = []
	for t: String in _combat_tags():
		if c.tag_growth.has(t):
			tags.append(t)
	for t: String in s.character(card_id).get("growth", {}):
		if not tags.has(t):
			tags.append(t)
	if tags.is_empty():
		return y
	var flow := HFlowContainer.new()
	flow.position = Vector2(0, y)
	flow.custom_minimum_size = Vector2(1110, 0)
	flow.size = Vector2(1110, 0)
	flow.add_theme_constant_override("h_separation", 18)
	flow.add_theme_constant_override("v_separation", 2)
	_content.add_child(flow)
	flow.add_child(UITheme.label("Рост:", "caps", 16, Palette.TEXT_DIM))
	for t: String in tags:
		var st := GrowthRules.stage(s, card_id, t)
		var xpv := GrowthRules.xp(s, card_id, t)
		var text := ""
		var col := Palette.TEXT_DIM
		match st:
			"evo":
				text = "✦ %s" % GrowthRules.grown(c, s, card_id, t).get("name", t)
				col = Color("#E3C98E")
			"mut":
				text = "✺ %s" % GrowthRules.grown(c, s, card_id, t).get("name", t)
				col = Color("#C07BD8")
			"vet":
				text = "%s — опытный %s" % [t, _xp_text(xpv)]
				col = Palette.SILVER
			_:
				text = "%s %s" % [t, _xp_text(xpv)]
		var l := UITheme.label(text, "sans", 16, col)
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.mouse_default_cursor_shape = Control.CURSOR_HELP
		l.mouse_entered.connect(_show_hint.bind(_growth_hint(t)))
		l.mouse_exited.connect(_hide_hint)
		flow.add_child(l)
	return y + 30.0 * (1 + int(tags.size() / 5)) + 4.0


static func _xp_text(v: float) -> String:
	return "%s/%d" % [str(snappedf(v, 0.5)).trim_suffix(".0"), int(GrowthRules.VETERAN if v < GrowthRules.VETERAN else GrowthRules.EVOLVE)]


func _growth_hint(tag: String) -> String:
	var c := ContentDB.data
	var s := GameState.state
	var d: Dictionary = c.tag_growth.get(tag, {})
	var st := GrowthRules.stage(s, card_id, tag)
	var lines: Array[String] = ["[b]Рост тега «%s»[/b]" % tag]
	if st in ["evo", "mut"]:
		var e := GrowthRules.grown(c, s, card_id, tag)
		lines.append("[color=%s]%s «%s»[/color] — %s" % ["#C07BD8" if st == "mut" else "#E3C98E", "Мутация" if st == "mut" else "Эволюция", e.get("name", ""), e.get("text", "")])
		return "\n".join(lines)
	var how: Array = []
	for g: String in d.get("grow", []):
		how.append({"check": "проверки с этим тегом", "combat": "бой, где тег сработал", "panic": "этапы, пройденные в панике", "any": "любые удачные миссии (медленнее)"}.get(g, g))
	lines.append("Опыт %s из %d. Растёт за: %s." % [str(snappedf(GrowthRules.xp(s, card_id, tag), 0.5)).trim_suffix(".0"), int(GrowthRules.EVOLVE), ", ".join(how)])
	var ct: Array = d.get("check_tags", [])
	var vet := "+1 %s в проверках: %s" % [Palette.STAT_NAMES.get(str(d.get("stat", "")), ""), ", ".join(ct.map(func(x: String) -> String: return str(c.tags.get(x, {}).get("name", x)).to_lower()))] if not ct.is_empty() else "+%d%% в бою" % int(GrowthRules.VET_COMBAT * 100)
	lines.append("[b]%d — опытный:[/b] %s%s" % [int(GrowthRules.VETERAN), vet, "  [color=#6FA47B]✓[/color]" if st == "vet" else ""])
	lines.append("[b]%d — развитие:[/b]" % int(GrowthRules.EVOLVE))
	lines.append("  [color=#E3C98E]эволюция %d%% «%s»[/color] — %s" % [int(100 - GrowthRules.MUTATION * 100), d["evo"].get("name", ""), d["evo"].get("text", "")])
	lines.append("  [color=#C07BD8]мутация %d%% «%s»[/color] — %s" % [int(GrowthRules.MUTATION * 100), d["mut"].get("name", ""), d["mut"].get("text", "")])
	return "\n".join(lines)


func _on_chip_hover(tag: String, on: bool) -> void:
	if on:
		_info.show_tag(tag, get_global_mouse_position())
	else:
		_info.visible = false


# --- кармашек усилений --------------------------------------------------------------

func _pocket() -> Array:
	var s := GameState.state
	if s == null or not s.characters.has(card_id):
		return []
	var out: Array = []
	for card: String in s.character(card_id).get("pocket", []):
		if s.owns(card):
			out.append(card)
	return out


## Кармашек: до трёх усилений, которые прикладываются к событию сами, когда персонаж — исполнитель.
func _build_pocket(y: float) -> void:
	var s := GameState.state
	var c := ContentDB.data
	var line := ColorRect.new()
	line.color = Palette.LINE
	line.position = Vector2(0, y - 6)
	line.size = Vector2(1110, 1)
	_content.add_child(line)
	var head := UITheme.label("КАРМАШЕК УСИЛЕНИЙ", "caps", 19, Palette.GOLD)
	head.position = Vector2(0, y)
	_content.add_child(head)
	var tip := UITheme.label("Усиления в кармашке сами прикладываются к событию, когда %s — исполнитель. Их бонусы и теги уже учтены выше. Щелчок — положить или убрать." % c.card_name(card_id),
		"sans", 16, Palette.TEXT_DIM)
	tip.position = Vector2(250, y + 2)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(860, 0)
	_content.add_child(tip)
	var row := HBoxContainer.new()
	row.position = Vector2(0, y + 50)
	row.add_theme_constant_override("separation", 12)
	_content.add_child(row)
	var pocket := _pocket()
	var slot := Vector2(128, 219)
	for i in POCKET_MAX:
		if i < pocket.size():
			var cv := CardView.make(pocket[i], slot, false)
			cv.hover_lift = true
			cv.tooltip_text = ""
			cv.clicked.connect(func(id: String) -> void: GameState.pocket_remove(card_id, id))
			row.add_child(cv)
		else:
			var empty := Panel.new()
			empty.custom_minimum_size = slot
			empty.add_theme_stylebox_override("panel", UITheme.box(Color(0.04, 0.04, 0.06, 0.6), Palette.SILVER.darkened(0.55), 1, 6, 0))
			row.add_child(empty)
			var plus := UITheme.label("+", "title", 40, Palette.SILVER.darkened(0.45))
			plus.position = slot / 2 - Vector2(10, 28)
			empty.add_child(plus)
	# доступные усиления
	var sep := ColorRect.new()
	sep.color = Palette.LINE
	sep.custom_minimum_size = Vector2(1, 222)
	row.add_child(sep)
	var avail_col := VBoxContainer.new()
	avail_col.add_theme_constant_override("separation", 4)
	row.add_child(avail_col)
	avail_col.add_child(UITheme.label("Можно положить:", "sans", 16, Palette.TEXT_DIM))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(640, 228)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	avail_col.add_child(sc)
	var avail := HBoxContainer.new()
	avail.add_theme_constant_override("separation", 8)
	sc.add_child(avail)
	var any := false
	for card: String in s.collection:
		if c.card_kind(card) != "enhancement" or pocket.has(card):
			continue
		any = true
		var small := CardView.make(card, Vector2(128, 219), false)
		small.tooltip_text = ""
		var owner := _pocket_owner(card)
		if owner != "":
			small.badge = "у: %s" % c.card_name(owner)
		small.clicked.connect(func(id: String) -> void:
			if _pocket().size() >= POCKET_MAX:
				EventBus.toast.emit("В кармашке не больше трёх усилений")
				return
			GameState.pocket_add(card_id, id))
		avail.add_child(small)
	if not any:
		avail.add_child(UITheme.label("Свободных усилений нет.", "sans", 16, Palette.TEXT_DIM))


func _pocket_owner(card: String) -> String:
	var s := GameState.state
	for cid: String in s.characters:
		if Array(s.characters[cid].get("pocket", [])).has(card):
			return cid
	return ""


# --- тексты ---------------------------------------------------------------------------

func _def() -> Dictionary:
	var c := ContentDB.data
	match c.card_kind(card_id):
		"character": return c.characters.get(card_id, {})
		"enhancement": return c.enhancements.get(card_id, {})
		"trauma": return c.traumas.get(card_id, {})
		"enemy": return c.enemies.get(card_id, {})
		"ability": return c.abilities.get(card_id, {})
	return c.missions.get(card_id, {})


func _emblem_for(kind: String) -> String:
	return {"character": "character", "enhancement": "enhancement", "enemy": "monster", "trauma": "trauma"}.get(kind, "story")


func _type_line(kind: String) -> String:
	var d := _def()
	var s := GameState.state
	match kind:
		"character":
			var st := ContentDB.data.stage_name(card_id, str(s.character(card_id).get("stage", ""))) if s else ""
			return "Персонаж" + (" · %s" % st if st != "" else "") + (" · погиб" if s and s.characters.has(card_id) and not s.is_alive(card_id) else "")
		"enhancement":
			return "Усиление · " + {"knowledge": "Знание", "memory": "Воспоминание", "improvised": "Подручное"}.get(d.get("origin", ""), "предмет")
		"trauma":
			return "Травма"
		"ability":
			var owners: Array = []
			if s:
				for cid: String in s.characters:
					if Array(s.characters[cid].get("abilities", [])).has(card_id):
						owners.append(ContentDB.data.card_name(cid))
			return "Способность" + (" · " + ", ".join(owners) if not owners.is_empty() else "")
		"enemy":
			return "Противник · %s · %s" % [CardView.RANKS[clampi(int(d.get("rank", 0)), 0, 6)], CardView.CLASSES[clampi(int(d.get("class", 1)), 1, 7)]]
	return "Миссия"


func _combat_tags() -> Array:
	var d := _def()
	var kind := ContentDB.data.card_kind(card_id)
	if kind == "character":
		var s := GameState.state
		var stage: String = s.character(card_id).get("stage", "") if s else ""
		var out := Array(d.get("stages", {}).get(stage, {}).get("tags", d.get("tags", []))).duplicate()
		if s:
			var ch := GrowthRules.tag_changes(ContentDB.data, s, card_id)
			for t: String in ch["remove"]:
				out.erase(t)
			for t: String in ch["add"]:
				if not out.has(t):
					out.append(t)
		return out
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
		"enhancement":
			out.append(_h("Эффект") + str(d.get("text", "")))
			out.append(_memory_text(d))
			if s and WearRules.wears(c, s, card_id):
				out.append(_h("Износ") + "Шанс поломки после следующего использования: [b]%d%%[/b]. Растёт с каждым событием; сломанная карта исчезает. Кузнец сбрасывает износ." % WearRules.current(s, card_id))
			elif bool(d.get("wears", true)):
				out.append(_h("Износ") + "Сейчас не изнашивается.")
			else:
				out.append(_h("Износ") + "Не изнашивается.")
			if s:
				var owner := _pocket_owner(card_id)
				if owner != "":
					out.append(_h("Кармашек") + "Лежит в кармашке персонажа «%s» — идёт с ним на миссии." % c.card_name(owner))
		"trauma":
			var lore: Dictionary = c.lore.get(card_id, {})
			if str(lore.get("text", "")) != "":
				out.append(str(lore["text"]))
			var ms2: Array = []
			for st3: String in d.get("mods", {}):
				ms2.append("%+d %s" % [int(d["mods"][st3]), Palette.STAT_NAMES.get(st3, st3)])
			out.append(_h("Эффект") + ", ".join(ms2))
		"enemy":
			out.append("%s · %s" % [{"normal": "обычный", "elite": "элита", "boss": "босс"}.get(d.get("kind", "normal"), ""), _type_line(kind)])
			out.append(_h("Добыча") + "✧ %d осколков душ" % int(d.get("shards", 0)))
		"ability":
			out.append(_h("Эффект") + str(d.get("text", "")))
			out.append(_memory_text(d))
		_:
			# миссия: описание, угроза, отряд, слухи
			if not d.is_empty():
				out.append(str(d.get("briefing", "")))
				out.append(_h("Угроза и отряд") + "Угроза %d из 5 · в пути ~%d с · отряд %d–%d" % [int(d.get("threat", 1)), int(d.get("duration", 8)),
					int(d.get("squad", {}).get("min", 1)), int(d.get("squad", {}).get("max", 1))])
				var rs: Array = []
				for r: Dictionary in d.get("rumors", []):
					rs.append("— [i]%s[/i]" % str(r.get("text", "")).replace("[", "").replace("]", ""))
				if not rs.is_empty():
					out.append(_h("Что говорят") + "\n".join(rs))
	return "\n\n".join(out)


## Особый навык карты (docs/16 §9д): срабатывает в бою сам, когда выполнено условие.
func _memory_text(d: Dictionary) -> String:
	var m: Dictionary = d.get("memory", {})
	if m.is_empty():
		return ""
	var when := "когда раунд проигран" if str(m.get("phase", "round")) == "lose" else "перед раундом"
	var rules: Array = [when, "раз за бой" if bool(m.get("once", true)) else "каждый раз"]
	if int(m.get("wear", 0)) > 0:
		rules.append("износ +%d%%" % int(m["wear"]))
	if bool(m.get("support", false)):
		rules.append("и из поддержки")
	return _h("Особый навык · %s" % m.get("name", "")) + "[color=#E3C98E]Условие:[/color] %s
[color=#E3C98E]Что делает:[/color] %s
%s" % [
		m.get("cond", ""), m.get("text", ""), _dim("Срабатывает сам в бою: %s." % ", ".join(rules))]


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


## Журнал карты в текущем прохождении: миссии героя и отметки (получение, травмы, поломка, гибель).
func _run_story() -> String:
	var s := GameState.state
	if s == null:
		return _dim("Прохождение не начато.")
	var c := ContentDB.data
	var rows: Array = []
	var words := {"success": "[color=#9FC29A]успех[/color]", "partial": "[color=#D08A48]с потерями[/color]",
		"failure": "[color=#B65F63]провал[/color]", "retreat": "[color=#9A9CA6]отступление[/color]"}
	for i in s.log.size():
		var e: Dictionary = s.log[i]
		if not e.has("mission") or not Array(e.get("heroes", [])).has(card_id):
			continue
		var a := MissionFlow.action(c, str(e["mission"]), str(e.get("action", "")))
		rows.append({"t": float(e.get("clock", 0.0)), "seq": i, "kind": 0, "text": "«%s» — %s · %s" % [c.missions.get(str(e["mission"]), {}).get("title", e["mission"]), a.get("label", ""), words.get(str(e.get("outcome", "")), "")]})
	for n: Dictionary in s.card_log:
		if str(n.get("card", "")) == card_id:
			rows.append({"t": float(n.get("t", 0.0)), "seq": int(n.get("seq", 0)), "kind": 1, "text": str(n.get("text", ""))})
	if rows.is_empty():
		return _dim("Вы ещё не встречали этого противника." if c.card_kind(card_id) == "enemy" else "Пока эта карта не участвовала в миссиях.")
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return [int(x["seq"]), int(x["kind"])] < [int(y["seq"]), int(y["kind"])])
	var lines: Array = []
	for r: Dictionary in rows:
		var t := int(r["t"])
		lines.append("[color=#B89A5E]%d:%02d[/color]  %s" % [t / 60, t % 60, r["text"]])
	return "
".join(lines)
