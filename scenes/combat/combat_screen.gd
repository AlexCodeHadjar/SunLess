class_name CombatScreen
extends Control
## Бой «Столкновение» (docs/12 §5): отдельная карта-поле битвы. Сверху — карты врага и его намерение,
## снизу — мои карты. Симбиозы и конфликты — световые нити между картами, отражающиеся от «стёкол»;
## числа сил и полоса шанса меняются прямо на глазах. Теги — гиперссылки; Shift — сетка связей.

signal closed

enum Phase { PREP, SELECT, RESULT, DONE }

const BOARD := Rect2(150, 70, 1620, 710)

var event_id := ""
var option_id := ""
var phase := Phase.PREP
var _support: Array = []
var _selected := ""
var _hover_tag := ""
var _graph_forced := false
var _anim_token := 0

var _board: Control
var _board_layer: Control
var _hero_card: CardView
var _carriers: Array = []        # [{node, side, tags}]
var _field_plaque: RichTextLabel
var _round_box: PanelContainer
var _round_label: RichTextLabel
var _intent_card: IntentCard
var _scale: ScaleBar
var _beams: Beams
var _hand_box: HBoxContainer
var _action_btn: Button
var _no_tactic_btn: Button
var _ledger_btn: Button
var _ledger_panel: PanelContainer
var _ledger: RichTextLabel
var _pips: Label
var _banner: Label
var _info: TagInfoPanel
var _graph: LinkGraph
var _glass: Array = []
var _last_led: Dictionary = {}


class ScaleBar extends Control:
	## Весы силы: числа сторон, полоса долей и шанс раунда; указатель броска.
	var hero := 100.0
	var enemy := 100.0
	var chance := 50
	var marker := -1.0
	var _tw: Tween

	func set_values(h: float, e: float, c: int, dur: float = 0.35) -> void:
		if _tw:
			_tw.kill()
		_tw = create_tween()
		_tw.tween_method(_set_hero, hero, h, dur)
		_tw.parallel().tween_method(_set_enemy, enemy, e, dur)
		if c > 0:
			chance = c
		marker = -1.0
		queue_redraw()

	func _set_hero(v: float) -> void:
		hero = v
		chance = clampi(int(round(100.0 * hero / maxf(1.0, hero + enemy))), 5, 95)
		queue_redraw()

	func _set_enemy(v: float) -> void:
		enemy = v
		chance = clampi(int(round(100.0 * hero / maxf(1.0, hero + enemy))), 5, 95)
		queue_redraw()

	func play_roll(value: int, speed: float) -> void:
		var tw := create_tween()
		tw.tween_method(_set_marker, 0.0, 100.0, 0.35 * maxf(speed, 0.05))
		tw.tween_method(_set_marker, 100.0, float(value), 0.55 * maxf(speed, 0.05)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	func _set_marker(v: float) -> void:
		marker = v
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var y := 46.0
		var h := 18.0
		var share := hero / maxf(1.0, hero + enemy)
		draw_rect(Rect2(0, y, w, h), Color("#0B0C11"))
		draw_rect(Rect2(0, y, w * share, h), Palette.SILVER.darkened(0.1))
		draw_rect(Rect2(w * share, y, w * (1.0 - share), h), Palette.TRAUMA.lightened(0.2))
		draw_rect(Rect2(0, y, w, h), Palette.LINE, false, 1.0)
		var cz := w * chance / 100.0
		draw_line(Vector2(cz, y - 6), Vector2(cz, y + h + 6), Palette.GOLD, 2.0)
		var fb := UITheme.font("title_bold")
		var f := UITheme.font("sans")
		draw_string(fb, Vector2(0, 34), "%d" % int(round(hero)), HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Palette.SILVER)
		draw_string(fb, Vector2(0, 34), "%d" % int(round(enemy)), HORIZONTAL_ALIGNMENT_RIGHT, w, 36, Palette.STAT_DOWN)
		draw_string(f, Vector2(0, 34), "сила героя · шанс раунда · сила врага", HORIZONTAL_ALIGNMENT_CENTER, w, 13, Palette.TEXT_DIM)
		draw_string(fb, Vector2(0, y + h + 44), "%d%%" % chance, HORIZONTAL_ALIGNMENT_CENTER, w, 40,
			Palette.chance_color(chance, SettingsService.get_value("chance_monochrome")))
		if marker >= 0:
			var mx := w * marker / 100.0
			draw_line(Vector2(mx, y - 10), Vector2(mx, y + h + 10), Palette.TEXT, 3.0)
			draw_colored_polygon(PackedVector2Array([Vector2(mx - 7, y - 16), Vector2(mx + 7, y - 16), Vector2(mx, y - 8)]), Palette.TEXT)


class IntentCard extends Control:
	## Карта намерения врага: что он сделает в этом раунде. Погашенное — перечёркнуто.
	var ability: Dictionary = {}
	var negated_by := ""

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(Rect2(r.position + Vector2(0, 6), r.size), Color(0, 0, 0, 0.45))
		draw_rect(r, Color("#1A0F14"))
		var inner := r.grow(-7)
		draw_rect(inner, Color("#231318"))
		draw_rect(r, Palette.STAT_DOWN, false, 2.0)
		draw_rect(inner, Palette.TRAUMA, false, 1.0)
		var f := UITheme.font("sans")
		draw_string(UITheme.font("caps"), inner.position + Vector2(0, 22), "НАМЕРЕНИЕ ВРАГА", HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 13, Palette.STAT_DOWN)
		if ability.is_empty():
			draw_string(f, inner.position + Vector2(0, 110), "раскроется в раунде", HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 15, Palette.TEXT_DIM)
			return
		draw_multiline_string(UITheme.font("title"), inner.position + Vector2(6, 54), str(ability.get("name", "")), HORIZONTAL_ALIGNMENT_CENTER, inner.size.x - 12, 22, 2, Palette.TEXT)
		draw_line(inner.position + Vector2(16, 88), inner.position + Vector2(inner.size.x - 16, 88), Palette.TRAUMA, 1.0)
		draw_multiline_string(f, inner.position + Vector2(8, 108), str(ability.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, inner.size.x - 16, 13, 7, Palette.TEXT_DIM)
		if negated_by != "":
			draw_line(inner.position + Vector2(10, 40), inner.end - Vector2(10, 30), Color(Palette.SILVER, 0.7), 3.0)
			draw_string(UITheme.font("sans_bold"), Vector2(inner.position.x, inner.end.y - 8), "ПОГАШЕНО: %s" % negated_by, HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 13, Palette.SILVER)


# --- построение ---------------------------------------------------------------------

func _ready() -> void:
	# отдельный непрозрачный экран поверх всей игры
	top_level = true
	z_index = 20
	position = Vector2.ZERO
	size = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.get_theme()
	var bg := ColorRect.new()
	bg.color = Color("#06070A")
	bg.position = Vector2(-200, -200)
	bg.size = size + Vector2(400, 400)
	add_child(bg)
	add_child(Vfx.fog(Rect2(Vector2(-200, 600), Vector2(2300, 500)), 0.05))
	add_child(Vfx.ambient_embers(Rect2(Vector2(0, 0), Vector2(1920, 1080))))

	_build_board()

	var title := UITheme.label("СТОЛКНОВЕНИЕ", "caps", 30, Palette.SILVER)
	title.position = Vector2(40, 16)
	add_child(title)
	_pips = UITheme.label("", "title_bold", 24, Palette.TEXT)
	_pips.position = Vector2(560, 20)
	_pips.custom_minimum_size.x = 800
	_pips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_pips)
	var retreat := Button.new()
	retreat.text = "ОТСТУПИТЬ"
	retreat.position = Vector2(1690, 14)
	retreat.custom_minimum_size = Vector2(190, 44)
	retreat.tooltip_text = "Бой прекратится без новых травм. Событие останется, раны врага сохранятся, он станет настороженным."
	retreat.pressed.connect(_on_retreat)
	add_child(retreat)

	_hand_box = HBoxContainer.new()
	_hand_box.add_theme_constant_override("separation", 22)
	_hand_box.position = Vector2(170, 800)
	add_child(_hand_box)
	_ledger_btn = Button.new()
	_ledger_btn.text = "ЛЕТОПИСЬ СИЛЫ"
	_ledger_btn.position = Vector2(1180, 830)
	_ledger_btn.custom_minimum_size = Vector2(230, 46)
	_ledger_btn.tooltip_text = "Пошаговый расчёт обеих сторон"
	_ledger_btn.pressed.connect(_toggle_ledger)
	add_child(_ledger_btn)
	_no_tactic_btn = Button.new()
	_no_tactic_btn.text = "Без приёма"
	_no_tactic_btn.position = Vector2(1180, 890)
	_no_tactic_btn.custom_minimum_size = Vector2(230, 46)
	_no_tactic_btn.pressed.connect(_pick_tactic.bind(""))
	add_child(_no_tactic_btn)
	_action_btn = Button.new()
	_action_btn.position = Vector2(1450, 850)
	_action_btn.custom_minimum_size = Vector2(300, 84)
	_action_btn.add_theme_font_override("font", UITheme.font("caps"))
	_action_btn.add_theme_font_size_override("font_size", 28)
	_action_btn.pressed.connect(_on_action)
	add_child(_action_btn)

	_ledger_panel = PanelContainer.new()
	_ledger_panel.position = Vector2(1010, 380)
	_ledger_panel.custom_minimum_size = Vector2(740, 400)
	_ledger_panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.05, 0.07, 0.97), Palette.LINE, 1, 4, 14))
	_ledger_panel.z_index = 30
	_ledger_panel.visible = false
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(710, 370)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ledger_panel.add_child(sc)
	_ledger = _rich(690, 15)
	sc.add_child(_ledger)
	add_child(_ledger_panel)

	_banner = UITheme.label("", "title_bold", 50, Palette.TEXT)
	_banner.position = Vector2(0, 395)
	_banner.custom_minimum_size = Vector2(1920, 0)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.modulate.a = 0.0
	_banner.z_index = 45
	add_child(_banner)

	_graph = LinkGraph.new()
	add_child(_graph)
	_info = TagInfoPanel.new()
	add_child(_info)


func _toggle_ledger() -> void:
	_ledger_panel.visible = not _ledger_panel.visible


## Карта-поле битвы: рамка, фон места, стёкла для отражений, слои карт и лучей.
func _build_board() -> void:
	_board = Control.new()
	_board.position = BOARD.position
	_board.size = BOARD.size
	_board.clip_contents = true
	add_child(_board)
	var bd := MapBackdrop.new()
	bd.snow = true
	bd.set_anchors_preset(Control.PRESET_FULL_RECT)
	bd.modulate = Color(0.55, 0.55, 0.62)
	_board.add_child(bd)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.03, 0.05, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(shade)
	var frame := Control.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.draw.connect(_draw_frame.bind(frame))
	_board.add_child(frame)
	_board_layer = Control.new()
	_board_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	_board.add_child(_board_layer)
	_field_plaque = _rich(700, 16)
	_field_plaque.position = Vector2(460, 300)
	_board.add_child(_field_plaque)
	_round_box = PanelContainer.new()
	_round_box.position = Vector2(26, 300)
	_round_box.custom_minimum_size = Vector2(340, 150)
	_round_box.pivot_offset = Vector2(170, 75)
	_round_box.add_theme_stylebox_override("panel", UITheme.box(Color(0.1, 0.09, 0.07, 0.95), Palette.GOLD.darkened(0.2), 1, 4, 12))
	_board.add_child(_round_box)
	var rv := VBoxContainer.new()
	_round_box.add_child(rv)
	rv.add_child(UITheme.label("КАРТА РАУНДА", "caps", 13, Palette.GOLD))
	_round_label = _rich(310, 15)
	rv.add_child(_round_label)
	_scale = ScaleBar.new()
	_scale.position = Vector2(420, 360)
	_scale.size = Vector2(780, 120)
	_board.add_child(_scale)
	_intent_card = IntentCard.new()
	_intent_card.position = Vector2(1380, 30)
	_intent_card.size = Vector2(200, 250)
	_board.add_child(_intent_card)
	_beams = Beams.new()
	add_child(_beams)
	# невидимые «стёкла» — наклонные плоскости в средней полосе, от них отражаются лучи
	var o := BOARD.position
	_glass = [
		[o + Vector2(260, 300), o + Vector2(620, 420)],
		[o + Vector2(700, 280), o + Vector2(930, 460)],
		[o + Vector2(1000, 440), o + Vector2(1340, 300)],
		[o + Vector2(420, 470), o + Vector2(820, 360)],
	]


func _draw_frame(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Palette.GOLD.darkened(0.25), false, 3.0)
	c.draw_rect(r.grow(-10), Palette.GOLD.darkened(0.55), false, 1.0)
	for corner: Vector2 in [Vector2(18, 18), Vector2(r.size.x - 18, 18), Vector2(18, r.size.y - 18), r.size - Vector2(18, 18)]:
		c.draw_colored_polygon(PackedVector2Array([corner + Vector2(0, -9), corner + Vector2(9, 0), corner + Vector2(0, 9), corner + Vector2(-9, 0)]), Palette.GOLD.darkened(0.2))
	c.draw_line(Vector2(40, 470), Vector2(r.size.x - 40, 470), Color(Palette.GOLD, 0.15), 1.0)
	c.draw_line(Vector2(40, 290), Vector2(r.size.x - 40, 290), Color(Palette.STAT_DOWN, 0.15), 1.0)


func _rich(width: float, fs: int = 16) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.custom_minimum_size = Vector2(width, 0)
	l.add_theme_font_size_override("normal_font_size", fs)
	l.meta_underlined = false
	l.meta_hover_started.connect(_on_meta_hover)
	l.meta_hover_ended.connect(_on_meta_unhover)
	return l


# --- карты на поле -----------------------------------------------------------------

## Раскладывает карты сторон: враги сверху, мои снизу; под каждой — её теги.
func _layout(cs: CombatSession) -> void:
	for ch in _board_layer.get_children():
		ch.queue_free()
	_carriers.clear()
	var n := cs.enemies.size()
	var esz := Vector2(140, 240) if n <= 3 else Vector2(112, 192)
	var total_w := n * esz.x + (n - 1) * 30
	var x := 790.0 - total_w / 2.0
	for e: Dictionary in cs.enemies:
		var cv := CardView.make(str(e["id"]), esz, false)
		cv.position = Vector2(x, 24)
		cv.sway = true
		cv.set_process(true)
		_board_layer.add_child(cv)
		_add_tags_under(cv, e.get("tags", []), "enemy")
		x += esz.x + 30
	_carriers.append({"node": _intent_card, "side": "intent", "tags": [str(cs.intent.get("name", ""))]})
	var hero_x := 720.0
	_hero_card = CardView.make(cs.hero, Vector2(150, 257), false)
	_hero_card.position = Vector2(hero_x, 440)
	_board_layer.add_child(_hero_card)
	var cdef: Dictionary = ContentDB.data.characters.get(cs.hero, {})
	var stage: String = cs.state.character(cs.hero).get("stage", "")
	var htags: Array = Array(cdef.get("stages", {}).get(stage, {}).get("tags", cdef.get("tags", []))).duplicate()
	for t: String in cs.hero_extra_tags + Array(cs.mods.get("hero_tags", [])):
		if not htags.has(t):
			htags.append(t)
	_add_tags_under(_hero_card, htags, "hero")
	var ex := hero_x + 190
	for e: String in cs.enh:
		var ec := CardView.make(e, Vector2(112, 192), false)
		ec.position = Vector2(ex, 470)
		_board_layer.add_child(ec)
		_add_tags_under(ec, ContentDB.data.enhancements.get(e, {}).get("tags", []), "hero")
		ex += 150
	var ax := hero_x - 160
	for a: String in cs.allies:
		var ac := CardView.make(a, Vector2(112, 192), false)
		ac.position = Vector2(ax, 470)
		_board_layer.add_child(ac)
		_add_tags_under(ac, ContentDB.data.characters.get(a, {}).get("support_tags", []), "hero")
		ax -= 150
	_carriers.append({"node": _field_plaque, "side": "env", "tags": cs.field.get("tags", [])})
	_carriers.append({"node": _round_box, "side": "env", "tags": cs.round_card.get("tags", [])})
	_field_plaque.text = "[center][color=#B89A5E]ПОЛЕ БОЯ[/color]  [b]%s[/b]   %s[/center]" % [cs.field.get("name", ""), TagText.links(cs.field.get("tags", []), "  ", 14)]
	_intent_card.ability = cs.intent
	_intent_card.negated_by = ""
	_intent_card.queue_redraw()


func _add_tags_under(card: Control, tags: Array, side: String) -> void:
	var l := _rich(card.size.x + 80, 12)
	l.text = "[center]%s[/center]" % TagText.links(tags, " ", 13)
	l.position = card.position + Vector2(-40, card.size.y + 4)
	_board_layer.add_child(l)
	_carriers.append({"node": card, "side": side, "tags": tags})


## Центр карты-носителя тега на нужной стороне (или на поле).
func _anchor_for(tag: String, prefer: String) -> Vector2:
	var order := [prefer, "hero" if prefer == "enemy" else "enemy", "env", "intent"]
	for side: String in order:
		for c: Dictionary in _carriers:
			if c["side"] == side and Array(c["tags"]).has(tag) and is_instance_valid(c["node"]):
				var nd: Control = c["node"]
				return nd.get_global_rect().get_center()
	return Vector2()


# --- поток боя ---------------------------------------------------------------------

func open(p_event: String, p_option: String) -> void:
	event_id = p_event
	option_id = p_option
	phase = Phase.PREP
	_build_prep()
	AudioManager.play("open", -2.0, 0.8)


func _preview_session() -> CombatSession:
	var cs := CombatSession.create(ContentDB.data, GameState.state, event_id, option_id, GameState.draft(event_id), _support)
	cs.round_no = 1
	return cs


func _build_prep() -> void:
	_clear_hand()
	var s := GameState.state
	var hero: String = GameState.draft(event_id).get("character", "")
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_hand_box.add_child(col)
	col.add_child(UITheme.label("Союзники в поддержке (до 2) — встанут рядом и добавят свои теги:", "sans", 18, Palette.TEXT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	var any := false
	for card: String in s.collection:
		if ContentDB.data.card_kind(card) != "character" or card == hero or not s.is_alive(card):
			continue
		any = true
		var cv := CardView.make(card, Vector2(98, 168), false)
		cv.highlight = _support.has(card)
		cv.clicked.connect(_toggle_support)
		row.add_child(cv)
	if not any:
		col.add_child(UITheme.label("Спутников нет — Санни сражается один.", "serif_italic", 18, Palette.TEXT_DIM))
	_no_tactic_btn.visible = false
	_action_btn.text = "НАЧАТЬ БОЙ ›"
	var preview := _preview_session()
	_pips.text = "Подготовка · %s" % preview.rounds_total_label()
	_layout(preview)
	_round_label.text = "[color=#9A9CA6]Откроется в начале раунда[/color]"
	_intent_card.ability = {}
	_intent_card.queue_redraw()
	_play_links(preview, preview.ledger({}), true)


func _toggle_support(card: String) -> void:
	if _support.has(card):
		_support.erase(card)
	elif _support.size() < 2:
		_support.append(card)
	AudioManager.play("place")
	_build_prep()


func _on_action() -> void:
	match phase:
		Phase.PREP:
			var err := GameState.start_combat(event_id, option_id, _support)
			if err != "":
				EventBus.toast.emit(err)
				return
			_next_round()
		Phase.SELECT:
			_play()
		Phase.RESULT:
			if GameState.combat.finished:
				_finish()
			else:
				_next_round()


func _next_round() -> void:
	var cs := GameState.combat
	cs.begin_round()
	phase = Phase.SELECT
	_selected = ""
	_layout(cs)
	_show_round_card(cs.round_card)
	for note: String in cs.intent_notes:
		EventBus.toast.emit(note)
	_build_hand()
	_update_pips()
	_action_btn.text = "В БОЙ ›"
	_no_tactic_btn.visible = true
	_play_links(cs, cs.ledger({}), true)


func _build_hand() -> void:
	_clear_hand()
	var cs := GameState.combat
	for t: String in cs.hand:
		var tc := TacticCard.make(t)
		tc.selected = t == _selected
		tc.picked.connect(_pick_tactic)
		_hand_box.add_child(tc)
	if cs.hand.is_empty():
		_hand_box.add_child(UITheme.label("Приёмов нет.", "sans", 18, Palette.TEXT_DIM))


func _clear_hand() -> void:
	for c in _hand_box.get_children():
		c.queue_free()


func _pick_tactic(id: String) -> void:
	if phase != Phase.SELECT:
		return
	_selected = "" if _selected == id else id
	for c in _hand_box.get_children():
		if c is TacticCard:
			c.selected = c.tactic_id == _selected
			c.queue_redraw()
	var cs := GameState.combat
	_play_links(cs, cs.ledger(ContentDB.data.tactics.get(_selected, {})), false)


## Главный эффект: лучи связей по очереди, числа сил и шанс меняются с каждым попаданием.
func _play_links(cs: CombatSession, led: Dictionary, from_base: bool) -> void:
	_anim_token += 1
	var token := _anim_token
	_last_led = led
	_show_ledger(cs, led, true)
	var hsteps: Array = led["hero_steps"]
	var esteps: Array = led["enemy_steps"]
	var h0 := float(hsteps[0]["value"]) if from_base else _scale.hero
	var e0 := float(esteps[0]["value"]) if from_base else _scale.enemy
	var h1 := float(led["hero"])
	var e1 := float(led["enemy"])
	_scale.set_values(h0, e0, 0, 0.2)
	var links: Array = led["links"]
	var n := links.size()
	if n == 0 or Vfx.reduced():
		_scale.set_values(h1, e1, int(led["chance"]))
		_mark_intent(led)
		return
	await get_tree().create_timer(0.25).timeout
	for i in n:
		if token != _anim_token or not is_inside_tree():
			return
		var l: Dictionary = links[i]
		var tags: Array = l["tags"]
		var side: String = l["side"]
		var kind := "synergy" if l["type"] == "synergy" else "conflict"
		if str(l["id"]).begins_with("env:"):
			kind = "env"
		elif bool(l.get("intent", false)):
			kind = "intent"
		var a := _anchor_for(str(tags[0]), side)
		var b := _anchor_for(str(tags[1]) if tags.size() > 1 else str(tags[0]), "enemy" if (kind == "conflict" and side == "hero") else side)
		if kind == "intent":
			a = _anchor_for(str(tags[0]), "hero")
			b = _intent_card.get_global_rect().get_center()
		if a == Vector2():
			a = _hero_card.get_global_rect().get_center() if is_instance_valid(_hero_card) else Vector2(960, 540)
		if b == Vector2() or a.distance_to(b) < 30:
			b = a + Vector2(0, -160)
		var dur := _beams.fire(a, b, kind, i, _glass)
		AudioManager.play("tick", -14.0, 1.2 + i * 0.05)
		await get_tree().create_timer(dur).timeout
		if token != _anim_token or not is_inside_tree():
			return
		var known := ProfileService.is_known(str(l["id"])) or kind in ["env", "intent"]
		var v := float(l["value"])
		var txt := ("%+d%%" % int(round(v * 100))) if absf(v) > 0.001 else "✦"
		var label_name: String = str(l["name"]) if known else "???"
		Beams.popup(self, b, "%s  %s" % [txt, label_name], Beams.COLORS[kind])
		var k := float(i + 1) / n
		_scale.set_values(lerpf(h0, h1, k), lerpf(e0, e1, k), 0, 0.22)
		await get_tree().create_timer(0.12).timeout
	if token == _anim_token and is_inside_tree():
		_scale.set_values(h1, e1, int(led["chance"]))
		_mark_intent(led)


func _mark_intent(led: Dictionary) -> void:
	_intent_card.negated_by = ""
	for l: Dictionary in led["links"]:
		if bool(l.get("intent", false)) and str(l["name"]).contains("гасит"):
			_intent_card.negated_by = str(l["tags"][0])
	_intent_card.queue_redraw()


func _play() -> void:
	var cs := GameState.combat
	_anim_token += 1
	phase = Phase.RESULT
	_no_tactic_btn.visible = false
	_action_btn.disabled = true
	_clear_hand()
	AudioManager.play("roll_shake", -4.0)
	var rec := cs.play_round(_selected)
	var led: Dictionary = rec["ledger"]
	_scale.set_values(float(led["hero"]), float(led["enemy"]), int(led["chance"]), 0.2)
	var speed: float = SettingsService.get_value("roll_speed")
	_scale.play_roll(int(rec["roll"]), speed if speed > 0 else 0.05)
	await get_tree().create_timer(0.95 * maxf(speed, 0.1)).timeout
	AudioManager.play("roll", -6.0)
	var won: bool = rec["hero_won"]
	_clash(won)
	_banner.text = ("РАУНД ВЫИГРАН" if won else "РАУНД ПРОИГРАН") + "  ·  шанс %d%% · выпало %d" % [int(rec["chance"]), int(rec["roll"])]
	_banner.add_theme_color_override("font_color", Palette.SILVER if won else Palette.STAT_DOWN)
	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.4)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.5)
	_show_ledger(cs, led, false)
	_update_pips()
	if is_instance_valid(_hero_card):
		_hero_card.queue_redraw()
	var fresh := ProfileService.discover(_link_ids(led))
	if not fresh.is_empty():
		await get_tree().create_timer(0.8).timeout
		await _reveal_links(fresh, led)
	_action_btn.disabled = false
	if cs.finished:
		_action_btn.text = "ИТОГ БОЯ ›"
		var o := {"win": "ПОБЕДА", "loss": "ПОРАЖЕНИЕ", "death": "ГИБЕЛЬ"}
		_pips.text = "%s  %d : %d" % [o.get(cs.outcome, ""), cs.hero_wins, cs.enemy_wins]
	else:
		_action_btn.text = "СЛЕДУЮЩИЙ РАУНД ›"


func _clash(won: bool) -> void:
	var center := BOARD.position + Vector2(810, 390)
	var fx := Vfx.burst(center, won)
	add_child(fx)
	Vfx.autofree(fx)
	AudioManager.play("success" if won else "fail", -3.0, 1.0 if won else 0.8)
	if Vfx.reduced() or not is_instance_valid(_hero_card):
		return
	var enemies: Array = []
	for c: Dictionary in _carriers:
		if c["side"] == "enemy" and is_instance_valid(c["node"]):
			enemies.append(c["node"])
	if won:
		var base := _hero_card.position
		var tw := create_tween()
		tw.tween_property(_hero_card, "position", base + Vector2(0, -90), 0.12).set_ease(Tween.EASE_OUT)
		tw.tween_property(_hero_card, "position", base, 0.25)
		for e: Control in enemies:
			if e is CardView:
				(e as CardView).shudder()
	else:
		if not enemies.is_empty():
			var target: Control = enemies[0]
			var eb := target.position
			var tw2 := create_tween()
			tw2.tween_property(target, "position", eb + Vector2(0, 90), 0.12).set_ease(Tween.EASE_OUT)
			tw2.tween_property(target, "position", eb, 0.25)
		_hero_card.shudder()
		AudioManager.play("trauma", -4.0)
		var smoke := Vfx.burst(_hero_card.get_global_rect().get_center(), false)
		add_child(smoke)
		Vfx.autofree(smoke)


func _reveal_links(fresh: Array, led: Dictionary) -> void:
	for l: Dictionary in led["links"]:
		if fresh.has(l["id"]) and l["type"] in ["synergy", "conflict"] and not str(l["id"]).begins_with("env:") and not bool(l.get("intent", false)):
			var tags: Array = l["tags"]
			AudioManager.play("bell", -10.0, 1.4)
			EventBus.toast.emit("Открыта связь: %s → «%s»" % [" + ".join(tags), l["name"]])
			_graph_forced = true
			_graph.show_for(str(tags[0]), str(l["id"]))
			await get_tree().create_timer(2.4).timeout
			_graph_forced = false
			_graph.visible = false
			return


func _on_retreat() -> void:
	if phase == Phase.PREP:
		closed.emit()
		queue_free()
		return
	if GameState.combat == null or GameState.combat.finished:
		return
	GameState.combat.retreat()
	_finish()


func _finish() -> void:
	phase = Phase.DONE
	_anim_token += 1
	GameState.finish_combat()
	closed.emit()
	queue_free()


# --- отображение --------------------------------------------------------------------

func _update_pips() -> void:
	var cs := GameState.combat
	var marks := ""
	for r: Dictionary in cs.rounds_log:
		marks += "◆ " if r["hero_won"] else "✖ "
	_pips.text = "РАУНД %d  ·  %s  ·  %s" % [cs.round_no, marks if marks != "" else "—", cs.rounds_total_label()]


func _show_round_card(card: Dictionary) -> void:
	var stat: String = card.get("stat", "")
	var stat_name: String = EffectApplier.STAT_NAMES.get(stat, "по кругу")
	_round_label.text = "[font_size=21][b]%s[/b][/font_size]\n%s\n[color=#9A9CA6]%s[/color]\n[color=#C9CED6]Характеристика: %s[/color]" % [
		card.get("name", ""), TagText.links(card.get("tags", []), " ", 14), card.get("text", ""), stat_name]
	if not Vfx.reduced():
		_round_box.scale.x = 0.0
		var tw := create_tween()
		tw.tween_property(_round_box, "scale:x", 1.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	AudioManager.play("fan", -4.0)


func _link_ids(led: Dictionary) -> Array:
	var out: Array = []
	for l: Dictionary in led["links"]:
		out.append(str(l["id"]))
	return out


## Летопись силы (панель по кнопке): шаги обеих сторон и связи; до броска неизвестные скрыты.
func _show_ledger(cs: CombatSession, led: Dictionary, before_roll: bool) -> void:
	var lines: Array[String] = []
	lines.append("[b]ЛЕТОПИСЬ СИЛЫ[/b]   [color=#9A9CA6]наведите на тег — описание, Shift — сетка связей[/color]")
	lines.append(_steps_line(ContentDB.data.card_name(cs.hero), led["hero_steps"], "#C9CED6"))
	lines.append(_steps_line("Враг", led["enemy_steps"], "#B65F63"))
	for l: Dictionary in led["links"]:
		var id := str(l["id"])
		var known := ProfileService.is_known(id) or id.begins_with("env:") or id.begins_with("tac:") or id.begins_with("int:") or not before_roll
		var who := "герой" if l["side"] == "hero" else "враг"
		var v := float(l["value"])
		var pct := "%+d%%" % int(round(v * 100)) if absf(v) > 0.001 else "погашено"
		var sign := "✦ СИМБИОЗ" if l["type"] == "synergy" else "✖ КОНФЛИКТ"
		var col := "#C9CED6" if l["type"] == "synergy" else "#B65F63"
		if known:
			var shown: Array = []
			for t: Variant in l["tags"]:
				shown.append(TagText.link(str(t), 15) if ContentDB.data.combat_tags.has(str(t)) else str(t))
			lines.append("[color=%s]%s[/color]  %s → «%s»  %s (%s)" % [col, sign, " · ".join(shown), l["name"], pct, who])
		else:
			lines.append("[color=#8A8D96]%s: неизвестная связь  %s (%s) — откроется после раунда[/color]" % [sign, pct, who])
	_ledger.text = "\n".join(lines)


func _steps_line(who: String, steps: Array, color: String) -> String:
	var parts: Array = []
	for st: Dictionary in steps:
		if st.has("pct"):
			parts.append("%s %+d%%" % [st["label"], int(round(float(st["pct"]) * 100))])
		else:
			parts.append("%s %d" % [st["label"], int(round(float(st["value"])))])
	var final_v := int(round(float(steps[-1]["value"]))) if not steps.is_empty() else 0
	return "[color=%s][b]%s[/b][/color]  %s  [b]= %d[/b]" % [color, who, " · ".join(parts), final_v]


# --- гиперссылки и сетка ------------------------------------------------------------

func _on_meta_hover(meta: Variant) -> void:
	var m := str(meta)
	if not m.begins_with("tag:"):
		return
	_hover_tag = m.substr(4)
	_info.show_tag(_hover_tag, get_global_mouse_position(), _contribution(_hover_tag))


func _on_meta_unhover(_meta: Variant) -> void:
	_hover_tag = ""
	_info.visible = false


func _contribution(tag: String) -> String:
	if _last_led.is_empty():
		return ""
	var led := _last_led
	var parts: Array = []
	if Array(led["hero_tags"]).has(tag):
		parts.append("есть у героя")
	if Array(led["enemy_tags"]).has(tag):
		parts.append("есть у врага")
	if Array(led["env_tags"]).has(tag):
		parts.append("на поле боя")
	for l: Dictionary in led["links"]:
		if Array(l["tags"]).has(tag) and (ProfileService.is_known(str(l["id"])) or str(l["id"]).begins_with("env:")):
			parts.append("%s %+d%%" % [l["name"], int(round(float(l["value"]) * 100))])
	return "В этом бою: " + ", ".join(parts) if not parts.is_empty() else ""


func _process(_d: float) -> void:
	if _graph_forced:
		return
	var shift := Input.is_key_pressed(KEY_SHIFT)
	if shift and _hover_tag != "":
		if not _graph.visible or _graph.tag != _hover_tag:
			_graph.show_for(_hover_tag)
	elif _graph.visible:
		_graph.visible = false
