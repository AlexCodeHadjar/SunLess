class_name CombatScreen
extends Control
## Бой «Столкновение» (docs/12 §5): просмотр автобоя миссии (docs/15) — отдельная карта-поле битвы. Сверху — карты врага и его намерение,
## снизу — мои карты. Симбиозы и конфликты — световые нити от тега к тегу, отражающиеся от «стёкол»;
## числа сил и полоса шанса меняются прямо на глазах. Теги — чипы с карточкой; Shift — сетка связей.

signal closed

enum Phase { PREP, SELECT, RESULT, DONE }

const BOARD := Rect2(40, 60, 1840, 744)
# вертикальная раскладка поля (координаты внутри BOARD)
const MID_X := 920.0
const ENEMY_Y := 16.0
const FIELD_Y := 306.0
const SCALE_Y := 338.0
const HERO_Y := 442.0
const SIDE_Y := 470.0
const ENEMY_SIZE := Vector2(164, 282)
const ENEMY_COMPACT := Vector2(120, 206)
const HERO_SIZE := Vector2(170, 292)
const SIDE_SIZE := Vector2(136, 234)
const SIDE_COMPACT := Vector2(112, 192)
const TAG_COL := 200.0      # ширина столбца тегов справа от карты героя/врага
const SIDE_COL := 158.0     # то же для союзников и усилений
const STAGES := ["base", "tags", "synergy", "conflict", "field", "round_no", "state", "memory", "intent", "stat"]

var phase := Phase.PREP
var _hover_tag := ""
var _graph_forced := false
var _anim_token := 0

var _board: Control
var _board_layer: Control
var _hero_card: CardView
var _carriers: Array = []        # [{node, side, tags, chips:{тег: TagChip}, name}]
var _field_row: HFlowContainer
var _round_box: PanelContainer
var _round_title: Label
var _round_tags: HFlowContainer
var _round_label: RichTextLabel
var _intent_card: IntentCard
var _scale: ScaleBar
var _beams: Beams
var _hand_box: HBoxContainer
var _action_btn: Button
var _ledger_btn: Button
var _ledger_panel: PanelContainer
var _ledger: RichTextLabel
var _pips: Label
var _banner: Label
var _info: TagInfoPanel
var _graph: LinkGraph
var _glass: Array = []
var _last_led: Dictionary = {}
# просмотр автобоя миссии (docs/15): навыки карт срабатывают сами, исход уже в отчёте
var _retreat_btn: Button


class ScaleBar extends Control:
	## Весы силы: числа сторон, полоса долей и шанс раунда; указатель броска.
	## Во время набора силы числа досчитываются по шагам, у каждого числа — подпись шага.
	var hero := 100.0
	var enemy := 100.0
	var chance := 50
	var marker := -1.0
	var building := false
	var _caps := {"hero": "", "enemy": ""}
	var _cap_cols := {"hero": Color.WHITE, "enemy": Color.WHITE}
	var _cap_a := {"hero": 0.0, "enemy": 0.0}
	var _pulse := {"hero": 0.0, "enemy": 0.0}
	var _tws := {}

	func _kill(key: String) -> void:
		var tw: Tween = _tws.get(key)
		if tw and tw.is_valid():
			tw.kill()

	func set_values(h: float, e: float, c: int, dur: float = 0.35) -> void:
		for k: String in ["hero", "enemy", "roll"]:
			_kill(k)
		var tw := create_tween()
		tw.tween_method(_set_hero, hero, h, maxf(dur, 0.01))
		tw.parallel().tween_method(_set_enemy, enemy, e, maxf(dur, 0.01))
		_tws["hero"] = tw
		if c > 0:
			chance = c
		marker = -1.0
		queue_redraw()

	## Обе силы в ноль — начало набора.
	func reset() -> void:
		for k: String in ["hero", "enemy", "roll", "cap_hero", "cap_enemy"]:
			_kill(k)
		hero = 0.0
		enemy = 0.0
		marker = -1.0
		_cap_a = {"hero": 0.0, "enemy": 0.0}
		queue_redraw()

	## Один шаг одной стороны: число плавно доезжает до value, рядом вспыхивает подпись.
	func step(side: String, value: float, caption: String, col: Color, dur: float) -> void:
		_kill(side)
		var tw := create_tween()
		tw.tween_method(_set_hero if side == "hero" else _set_enemy, hero if side == "hero" else enemy, value, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.parallel().tween_method(_set_pulse.bind(side), 1.0, 0.0, dur + 0.2)
		_tws[side] = tw
		if caption != "":
			_caps[side] = caption
			_cap_cols[side] = col
			_kill("cap_" + side)
			var ct := create_tween()
			ct.tween_method(_set_cap.bind(side), 1.0, 1.0, 1.1)
			ct.tween_method(_set_cap.bind(side), 1.0, 0.0, 0.5)
			_tws["cap_" + side] = ct

	func _set_cap(v: float, side: String) -> void:
		_cap_a[side] = v
		queue_redraw()

	func _set_pulse(v: float, side: String) -> void:
		_pulse[side] = v
		queue_redraw()

	func _recalc() -> void:
		chance = clampi(int(round(100.0 * hero / maxf(1.0, hero + enemy))), 5, 95)
		queue_redraw()

	func _set_hero(v: float) -> void:
		hero = v
		_recalc()

	func _set_enemy(v: float) -> void:
		enemy = v
		_recalc()

	func play_roll(value: int, speed: float) -> void:
		_kill("roll")
		var tw := create_tween()
		tw.tween_method(_set_marker, 0.0, 100.0, 0.35 * maxf(speed, 0.05))
		tw.tween_method(_set_marker, 100.0, float(value), 0.55 * maxf(speed, 0.05)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_tws["roll"] = tw

	## Размер шрифта подписи, чтобы она влезла в ширину (от 19 до 13).
	func _fit(f: Font, text: String, width: float) -> int:
		var fs := 19
		while fs > 13 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
			fs -= 1
		return fs

	func _set_marker(v: float) -> void:
		marker = v
		queue_redraw()

	## Сверху: сила героя — шанс — сила врага; ниже полоса долей; подпись под ней. Всё в 96 px высоты.
	func _draw() -> void:
		var w := size.x
		var y := 52.0
		var h := 20.0
		var both := hero >= 1.0 and enemy >= 1.0
		var share := hero / (hero + enemy) if both else 0.5
		draw_rect(Rect2(0, y, w, h), Color("#0B0C11"))
		if hero >= 1.0 or enemy >= 1.0:
			draw_rect(Rect2(0, y, w * share, h), Palette.SILVER.darkened(0.1))
			draw_rect(Rect2(w * share, y, w * (1.0 - share), h), Palette.TRAUMA.lightened(0.2))
		draw_rect(Rect2(0, y, w, h), Palette.LINE, false, 1.0)
		var fb := UITheme.font("title_bold")
		var f := UITheme.font("sans")
		var fsb := UITheme.font("sans_bold")
		if both:
			var cz := w * chance / 100.0
			draw_line(Vector2(cz, y - 6), Vector2(cz, y + h + 6), Palette.GOLD, 2.0)
		# числа сторон с «пульсом» на каждом шаге
		var hs := 46 + int(10 * _pulse["hero"])
		var es := 46 + int(10 * _pulse["enemy"])
		var htxt := "%d" % int(round(hero))
		var etxt := "%d" % int(round(enemy))
		draw_string(fb, Vector2(0, 40), htxt, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Palette.SILVER.lightened(0.3 * _pulse["hero"]))
		draw_string(fb, Vector2(0, 40), etxt, HORIZONTAL_ALIGNMENT_RIGHT, w, es, Palette.STAT_DOWN.lightened(0.3 * _pulse["enemy"]))
		draw_string(fb, Vector2(0, 44), ("%d%%" % chance) if both else "…", HORIZONTAL_ALIGNMENT_CENTER, w, 54,
			Palette.chance_color(chance, SettingsService.get_value("chance_monochrome")))
		# подписи шагов: у героя — справа от числа, у врага — слева
		var cap_w := w / 2.0 - 110.0
		if _cap_a["hero"] > 0.01:
			var x0 := fb.get_string_size(htxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x + 16.0
			var hf := _fit(fsb, _caps["hero"], cap_w - x0)
			draw_string(fsb, Vector2(x0, 34), _caps["hero"], HORIZONTAL_ALIGNMENT_LEFT, cap_w - x0, hf, Color(_cap_cols["hero"], _cap_a["hero"]))
		if _cap_a["enemy"] > 0.01:
			var x1 := w - fb.get_string_size(etxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x - 16.0
			var avail := x1 - (w - cap_w)
			var ef := _fit(fsb, _caps["enemy"], avail)
			var cw := minf(fsb.get_string_size(_caps["enemy"], HORIZONTAL_ALIGNMENT_LEFT, -1, ef).x, avail)
			draw_string(fsb, Vector2(x1 - cw, 34), _caps["enemy"], HORIZONTAL_ALIGNMENT_LEFT, cw, ef, Color(_cap_cols["enemy"], _cap_a["enemy"]))
		var hint := "сила героя · шанс раунда · сила врага" + ("   ·   щелчок — сразу итог" if building else "")
		draw_string(f, Vector2(0, y + h + 22), hint, HORIZONTAL_ALIGNMENT_CENTER, w, 16, Palette.TEXT_DIM)
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
		draw_string(UITheme.font("caps"), inner.position + Vector2(0, 26), "НАМЕРЕНИЕ ВРАГА", HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 16, Palette.STAT_DOWN)
		var em := UITheme.emblem("monster")
		if em:
			draw_texture_rect(em, Rect2(inner.end - Vector2(44, 44), Vector2(38, 38)), false, Color(1, 1, 1, 0.85))
		if ability.is_empty():
			draw_string(f, inner.position + Vector2(0, 140), "раскроется в раунде", HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 19, Palette.TEXT_DIM)
			return
		draw_multiline_string(UITheme.font("title"), inner.position + Vector2(6, 64), str(ability.get("name", "")), HORIZONTAL_ALIGNMENT_CENTER, inner.size.x - 12, 27, 2, Palette.TEXT)
		draw_line(inner.position + Vector2(16, 108), inner.position + Vector2(inner.size.x - 16, 108), Palette.TRAUMA, 1.0)
		draw_multiline_string(f, inner.position + Vector2(10, 134), str(ability.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, inner.size.x - 20, 17, 7, Palette.TEXT_DIM)
		if negated_by != "":
			draw_line(inner.position + Vector2(10, 40), inner.end - Vector2(10, 30), Color(Palette.SILVER, 0.7), 3.0)
			draw_string(UITheme.font("sans_bold"), Vector2(inner.position.x, inner.end.y - 10), "ПОГАШЕНО: %s" % negated_by, HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 16, Palette.SILVER)


# --- построение ---------------------------------------------------------------------

func _ready() -> void:
	add_to_group(HintTargets.LAYER)
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

	var title := UITheme.label("СТОЛКНОВЕНИЕ", "caps", 34, Palette.SILVER)
	title.position = Vector2(40, 8)
	add_child(title)
	_pips = UITheme.label("", "title_bold", 29, Palette.TEXT)
	_pips.position = Vector2(560, 10)
	_pips.custom_minimum_size.x = 800
	_pips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_pips)
	var retreat := Button.new()
	retreat.text = "ОТСТУПИТЬ"
	retreat.position = Vector2(1670, 8)
	retreat.custom_minimum_size = Vector2(210, 46)
	retreat.add_theme_font_size_override("font_size", 20)
	retreat.tooltip_text = "Бой прекратится без новых травм. Событие останется, раны врага сохранятся, он станет настороженным."
	retreat.pressed.connect(_on_retreat)
	add_child(retreat)
	_retreat_btn = retreat

	_hand_box = HBoxContainer.new()
	_hand_box.add_theme_constant_override("separation", 22)
	_hand_box.position = Vector2(40, 818)
	add_child(_hand_box)
	_ledger_btn = Button.new()
	_ledger_btn.text = "ЛЕТОПИСЬ СИЛЫ"
	_ledger_btn.position = Vector2(1060, 850)
	_ledger_btn.custom_minimum_size = Vector2(270, 54)
	_ledger_btn.add_theme_font_size_override("font_size", 21)
	_ledger_btn.tooltip_text = "Пошаговый расчёт обеих сторон"
	_ledger_btn.pressed.connect(_toggle_ledger)
	add_child(_ledger_btn)
	_action_btn = Button.new()
	_action_btn.position = Vector2(1400, 856)
	_action_btn.custom_minimum_size = Vector2(440, 110)
	_action_btn.add_theme_font_override("font", UITheme.font("caps"))
	_action_btn.add_theme_font_size_override("font_size", 30)
	_action_btn.pressed.connect(_on_action)
	add_child(_action_btn)

	_ledger_panel = PanelContainer.new()
	_ledger_panel.position = Vector2(960, 290)
	_ledger_panel.custom_minimum_size = Vector2(900, 500)
	_ledger_panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.05, 0.07, 0.97), Palette.LINE, 1, 4, 14))
	_ledger_panel.z_index = 30
	_ledger_panel.visible = false
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(870, 470)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ledger_panel.add_child(sc)
	_ledger = _rich(850, 18)
	sc.add_child(_ledger)
	add_child(_ledger_panel)

	_banner = UITheme.label("", "title_bold", 58, Palette.TEXT)
	_banner.position = Vector2(0, 270)
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
	_board.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_board)
	var bd := MapBackdrop.new()
	bd.snow = true
	bd.set_anchors_preset(Control.PRESET_FULL_RECT)
	bd.modulate = Color(0.55, 0.55, 0.62)
	if GameState.state:
		bd.region = GameState.state.region
		bd.snow = GameState.state.region == "mountain_pass"
	_board.add_child(bd)
	if GameState.state:
		bd.set_sky(Atmosphere.sky(ContentDB.data, GameState.state), false)
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
	_field_row = _flow(1100)
	_field_row.position = Vector2(MID_X - 550, FIELD_Y)
	_board.add_child(_field_row)
	_round_box = PanelContainer.new()
	_round_box.position = Vector2(22, 22)
	_round_box.custom_minimum_size = Vector2(300, 272)
	_round_box.pivot_offset = Vector2(150, 136)
	_round_box.add_theme_stylebox_override("panel", UITheme.box(Color(0.1, 0.09, 0.07, 0.95), Palette.GOLD.darkened(0.2), 1, 4, 12))
	_board.add_child(_round_box)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 3)
	_round_box.add_child(rv)
	rv.add_theme_constant_override("separation", 6)
	rv.add_child(UITheme.label("КАРТА РАУНДА", "caps", 16, Palette.GOLD))
	_round_title = UITheme.label("", "sans_bold", 25, Palette.TEXT)
	_round_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_round_title.custom_minimum_size.x = 272
	rv.add_child(_round_title)
	_round_tags = _flow(272)
	_round_tags.alignment = FlowContainer.ALIGNMENT_BEGIN
	rv.add_child(_round_tags)
	_round_label = _rich(272, 18)
	rv.add_child(_round_label)
	_scale = ScaleBar.new()
	_scale.position = Vector2(MID_X - 520, SCALE_Y)
	_scale.size = Vector2(1040, 96)
	_board.add_child(_scale)
	_intent_card = IntentCard.new()
	_intent_card.size = Vector2(270, 300)
	_intent_card.position = Vector2(BOARD.size.x - 22 - 270, 18)
	_board.add_child(_intent_card)
	_beams = Beams.new()
	add_child(_beams)
	# невидимые «стёкла» — наклонные плоскости в средней полосе, от них отражаются лучи
	var o := BOARD.position
	_glass = [
		[o + Vector2(MID_X - 640, 312), o + Vector2(MID_X - 250, 436)],
		[o + Vector2(MID_X - 160, 300), o + Vector2(MID_X + 100, 440)],
		[o + Vector2(MID_X + 180, 436), o + Vector2(MID_X + 600, 312)],
		[o + Vector2(MID_X - 440, 440), o + Vector2(MID_X + 20, 330)],
	]


func _draw_frame(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Palette.GOLD.darkened(0.25), false, 3.0)
	c.draw_rect(r.grow(-10), Palette.GOLD.darkened(0.55), false, 1.0)
	for corner: Vector2 in [Vector2(18, 18), Vector2(r.size.x - 18, 18), Vector2(18, r.size.y - 18), r.size - Vector2(18, 18)]:
		c.draw_colored_polygon(PackedVector2Array([corner + Vector2(0, -9), corner + Vector2(9, 0), corner + Vector2(0, 9), corner + Vector2(-9, 0)]), Palette.GOLD.darkened(0.2))
	c.draw_line(Vector2(40, HERO_Y - 8), Vector2(r.size.x - 40, HERO_Y - 8), Color(Palette.GOLD, 0.15), 1.0)
	c.draw_line(Vector2(40, FIELD_Y - 5), Vector2(r.size.x - 40, FIELD_Y - 5), Color(Palette.STAT_DOWN, 0.15), 1.0)


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

## Раскладывает карты сторон: враги сверху, мои снизу. Теги — столбцом справа от карты;
## если карт на стороне много — карты компактнее, а теги рядом под ними.
func _layout(cs: CombatSession) -> void:
	for ch in _board_layer.get_children():
		ch.queue_free()
	_carriers.clear()
	var n := cs.enemies.size()
	var beside := n <= 3
	var esz := ENEMY_SIZE if beside else ENEMY_COMPACT
	var block := esz.x + 16.0 + TAG_COL if beside else esz.x + 50.0
	var gap := 40.0 if beside else 16.0
	var x := MID_X - (n * block + (n - 1) * gap) / 2.0
	for e: Dictionary in cs.enemies:
		var cv := CardView.make(str(e["id"]), esz, false)
		cv.aura_wounds = int(cs.state.enemy_wounds.get(cs.event_id, 0)) + cs.session_wounds
		cv.position = Vector2(x + (0.0 if beside else 25.0), ENEMY_Y)
		cv.sway = true
		cv.set_process(true)
		_board_layer.add_child(cv)
		_place_tags(cv, e.get("tags", []), "enemy", beside, TAG_COL if beside else block - 6.0, 18 if beside else 15, FIELD_Y - 6.0)
		x += block + gap
	_carriers.append({"node": _intent_card, "side": "intent", "tags": [str(cs.intent.get("name", ""))], "chips": {}})
	# герой: карта и столбец тегов, блок по центру поля
	var hero_x := MID_X - (HERO_SIZE.x + 10.0 + TAG_COL) / 2.0
	_hero_card = CardView.make(cs.hero, HERO_SIZE, false)
	_hero_card.position = Vector2(hero_x, HERO_Y)
	_board_layer.add_child(_hero_card)
	var cdef: Dictionary = ContentDB.data.characters.get(cs.hero, {})
	var stage: String = cs.state.character(cs.hero).get("stage", "")
	var htags: Array = Array(cdef.get("stages", {}).get(stage, {}).get("tags", cdef.get("tags", []))).duplicate()
	for t: String in cs.hero_extra_tags:
		if not htags.has(t):
			htags.append(t)
	_place_tags(_hero_card, htags, "hero", true, TAG_COL, 19, BOARD.size.y - 10.0)
	# усиления справа от героя, союзники слева; больше двух на стороне — компактно
	var right := hero_x + HERO_SIZE.x + 10.0 + TAG_COL + 24.0
	var enh_compact := cs.enh.size() > 2
	for e: String in cs.enh:
		right += _side_card(e, ContentDB.data.enhancements.get(e, {}).get("tags", []), right, enh_compact) + 20.0
	var left := hero_x - 24.0
	var ally_compact := cs.allies.size() > 2
	for a: String in cs.allies:
		left -= _side_block_width(ally_compact)
		_side_card(a, ContentDB.data.characters.get(a, {}).get("support_tags", []), left, ally_compact)
		left -= 20.0
	_fill_field(cs.field)
	_fill_round(cs.round_card)
	_intent_card.ability = cs.intent
	_intent_card.negated_by = ""
	_intent_card.queue_redraw()


func _side_block_width(compact: bool) -> float:
	return SIDE_COMPACT.x + 44.0 if compact else SIDE_SIZE.x + 8.0 + SIDE_COL


## Карта союзника или усиления с тегами; x — левый край блока. Возвращает ширину блока.
func _side_card(id: String, tags: Array, x: float, compact: bool) -> float:
	var w := _side_block_width(compact)
	var c := CardView.make(id, SIDE_COMPACT if compact else SIDE_SIZE, false)
	c.position = Vector2(x + (22.0 if compact else 0.0), SIDE_Y + (12.0 if compact else 0.0))
	_board_layer.add_child(c)
	_place_tags(c, tags, "hero", not compact, w if compact else SIDE_COL, 15 if compact else 17, BOARD.size.y - 10.0)
	return w


## Теги карты: столбцом справа (beside) или рядом под ней, не ниже max_y.
## Не влезают — шрифт мельче, в крайнем случае только иконки.
func _place_tags(card: Control, tags: Array, side: String, beside: bool, width: float, fs0: int, max_y: float) -> void:
	var pos: Vector2
	var max_h: float
	if beside:
		pos = card.position + Vector2(card.size.x + 16.0, 2.0)
		max_h = card.size.y - 2.0
	else:
		pos = Vector2(card.position.x + card.size.x / 2.0 - width / 2.0, card.position.y + card.size.y + 4.0)
		max_h = max_y - pos.y
	var fs := fs0
	var icon_only := false
	for opt: Array in [[fs0, false], [fs0 - 1, false], [fs0 - 2, false], [fs0 - 3, false], [18, true]]:
		fs = opt[0]
		icon_only = opt[1]
		if _rows_needed(tags, width, fs, icon_only) * (fs + 9) <= max_h + 3:
			break
	var row := _flow(width)
	if beside:
		row.alignment = FlowContainer.ALIGNMENT_BEGIN
	if icon_only:
		row.add_theme_constant_override("h_separation", 5)
	row.position = pos
	_board_layer.add_child(row)
	var chips := _add_chips(row, tags, fs, icon_only)
	_carriers.append({"node": card, "side": side, "tags": tags, "chips": chips})


## Табличка поля боя: подпись, название (якорь лучей поля) и теги-чипы.
func _fill_field(field: Dictionary) -> void:
	for ch in _field_row.get_children():
		ch.queue_free()
	_field_row.add_child(UITheme.label("ПОЛЕ БОЯ", "caps", 17, Palette.GOLD))
	var name_l := UITheme.label(str(field.get("name", "")), "sans_bold", 21, Palette.TEXT)
	_field_row.add_child(name_l)
	var tags: Array = field.get("tags", [])
	var chips := _add_chips(_field_row, tags, 18, false)
	_carriers.append({"node": name_l, "side": "env", "tags": tags, "chips": chips, "name": str(field.get("name", ""))})


## Содержимое карты раунда; её название — якорь лучей раунда.
func _fill_round(card: Dictionary) -> void:
	for ch in _round_tags.get_children():
		ch.queue_free()
	if card.is_empty():
		_round_title.text = ""
		_round_tags.visible = false
		_round_label.text = "[color=#9A9CA6]Откроется в начале раунда[/color]"
		return
	var stat: String = card.get("stat", "")
	var stat_name: String = EffectApplier.STAT_NAMES.get(stat, "по кругу")
	_round_title.text = str(card.get("name", ""))
	var tags: Array = card.get("tags", [])
	_round_tags.visible = not tags.is_empty()
	var chips := _add_chips(_round_tags, tags, 18, false)
	_round_label.text = "[color=#9A9CA6]%s[/color]\n[color=#C9CED6]Характеристика: %s[/color]" % [card.get("text", ""), stat_name]
	_carriers.append({"node": _round_title, "side": "env", "tags": tags, "chips": chips, "name": str(card.get("name", ""))})


func _flow(width: float) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.alignment = FlowContainer.ALIGNMENT_CENTER
	f.custom_minimum_size = Vector2(width, 0)
	f.size = Vector2(width, 0)
	f.mouse_filter = Control.MOUSE_FILTER_PASS
	f.add_theme_constant_override("h_separation", 10)
	f.add_theme_constant_override("v_separation", 3)
	return f


func _add_chips(parent: Control, tags: Array, fs: int, icon_only: bool) -> Dictionary:
	var chips := {}
	for t: Variant in tags:
		var c := TagChip.make(str(t), fs, icon_only)
		c.hovered.connect(_on_chip_hover)
		parent.add_child(c)
		chips[str(t)] = c
	return chips


func _rows_needed(tags: Array, width: float, fs: int, icon_only: bool) -> int:
	var sep := 5.0 if icon_only else 10.0
	var rows := 1
	var x := 0.0
	for t: Variant in tags:
		var w := TagChip.width_of(str(t), fs, icon_only)
		if x > 0.0 and x + sep + w > width:
			rows += 1
			x = w
		else:
			x += (sep if x > 0.0 else 0.0) + w
	return rows


## Узел, в который бьёт луч тега: сам чип на нужной стороне, иначе карта этой стороны.
func _tag_node(tag: String, sides: Array) -> Control:
	for side: String in sides:
		for c: Dictionary in _carriers:
			if c["side"] == side and c["chips"].has(tag) and is_instance_valid(c["chips"][tag]):
				return c["chips"][tag]
	for side: String in sides:
		for c: Dictionary in _carriers:
			if c["side"] == side and Array(c["tags"]).has(tag) and is_instance_valid(c["node"]):
				return c["node"]
	if sides[0] == "hero":
		return _hero_card
	for c: Dictionary in _carriers:
		if c["side"] == sides[0] and is_instance_valid(c["node"]):
			return c["node"]
	return null


## Источник луча поля или раунда — их название на табличке.
func _env_node(src_name: String) -> Control:
	for c: Dictionary in _carriers:
		if c["side"] == "env" and str(c.get("name", "")) == src_name and is_instance_valid(c["node"]):
			return c["node"]
	return _field_row


## Карта навыка на полке у ведущего (или сам ведущий, если полки нет).
func _memory_node(card: String) -> Control:
	for c in _hand_box.get_children():
		if c.has_meta("memory") and str(c.get_meta("memory")) == card:
			return c
	return _hero_card


## Отрезки лучей связи [[откуда, куда], …] — от тега к тегу, с которым он взаимодействует.
func _link_segments(l: Dictionary, kind: String) -> Array:
	var tags: Array = l["tags"]
	var side: String = l["side"]
	var other := "enemy" if side == "hero" else "hero"
	var id := str(l["id"])
	match kind:
		"env":
			return [[_env_node(str(tags[0])), _tag_node(str(tags[1]), [side])]]
		"intent":
			if str(tags[1]) == "герой":
				return [[_intent_card, _hero_card]]
			return [[_tag_node(str(tags[0]), ["hero"]), _intent_card]]
		"synergy":
			var segs: Array = []
			for j in range(tags.size() - 1):
				segs.append([_tag_node(str(tags[j]), [side, "env"]), _tag_node(str(tags[j + 1]), [side, "env"])])
			return segs
	# конфликт: луч летит от победившего тега к проигравшему
	if id.begins_with("mem:"):
		return [[_memory_node(id.substr(4).get_slice(">", 0)), _tag_node(str(tags[1]), ["enemy"])]]
	var c: Dictionary = ContentDB.data.conflicts.get(id, {})
	var loser := str(c.get("a", "")) if c.get("loser", "b") == "a" else str(c.get("b", ""))
	var winner := str(tags[1]) if str(tags[0]) == loser else str(tags[0])
	return [[_tag_node(winner, [other, "env"]), _tag_node(loser, [side])]]


static func _anchor_of(node: Control) -> Vector2:
	if node is TagChip:
		return (node as TagChip).anchor()
	return node.get_global_rect().get_center()


# --- поток боя ---------------------------------------------------------------------



## Просмотр автобоя миссии: тот же бой, что посчитал MissionResolver (тот же RNG — тот же исход).
func open_replay(setup: Dictionary) -> void:
	GameState.combat = MissionResolver.replay_session(ContentDB.data, setup)
	phase = Phase.PREP
	_clear_hand()
	_retreat_btn.text = "ПРОМОТАТЬ"
	_retreat_btn.tooltip_text = "Закрыть просмотр — итог боя уже в отчёте"
	_action_btn.text = "СМОТРЕТЬ ›"
	var cs := GameState.combat
	cs.round_no = 1
	_pips.text = "Автобой · %s" % cs.rounds_total_label()
	_layout(cs)
	cs.round_no = 0
	_build_memories()
	AudioManager.play("open", -2.0, 0.8)
	_replay_later(1.2)


func _replay_later(delay: float) -> void:
	var token := _anim_token
	await get_tree().create_timer(delay).timeout
	if not is_inside_tree() or token != _anim_token or phase == Phase.DONE:
		return
	match phase:
		Phase.PREP:
			_next_round()
		Phase.SELECT:
			_play()
		Phase.RESULT:
			if not GameState.combat.finished:
				_next_round()


## Кнопка лишь ускоряет следующий шаг просмотра.
func _on_action() -> void:
	_anim_token += 1
	match phase:
		Phase.PREP:
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
	_layout(cs)
	_reveal_round_card()
	for note: String in cs.intent_notes:
		EventBus.toast.emit(note)
	_build_memories()
	_update_pips()
	_action_btn.text = "ДАЛЬШЕ ›"
	# навыки карт, чьё условие выполнено в этом раунде, срабатывают сами (docs/16 §9д)
	var pre := MemoryRules.fire(cs, "round", false)
	var token := _anim_token
	if not Array(pre["fired"]).is_empty():
		await _show_memories(pre["fired"])
		if token != _anim_token or not is_inside_tree():
			return
	_replay_later(1.6)
	_play_links(cs, cs.ledger(pre["effect"]), true)


## Полка навыков: карты кармашка и способности отряда с особым навыком — условие под картой.
func _build_memories() -> void:
	_clear_hand()
	var cs := GameState.combat
	var list := MemoryRules.listing(cs)
	if list.is_empty():
		_hand_box.add_child(UITheme.label("У отряда нет карт с особыми навыками — положите Воспоминания в кармашек.", "serif_italic", 18, Palette.TEXT_DIM))
		return
	var head := UITheme.label("НАВЫКИ КАРТ\nсрабатывают сами", "sans_bold", 14, Palette.GOLD)
	_hand_box.add_child(head)
	for m: Dictionary in list:
		var d: Dictionary = m["def"]
		var box := VBoxContainer.new()
		box.set_meta("memory", str(m["card"]))
		box.add_theme_constant_override("separation", 2)
		box.custom_minimum_size.x = 150
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		box.tooltip_text = "%s\nУсловие: %s\n%s" % [d.get("name", ""), d.get("cond", ""), d.get("text", "")]
		var cv := CardView.make(str(m["card"]), Vector2(70, 120), false)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.dimmed = bool(m["used"])
		box.add_child(cv)
		var n := UITheme.label(str(d.get("name", "")), "sans_bold", 13, Palette.TEXT_DIM if bool(m["used"]) else Palette.GOLD)
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(n)
		var c := UITheme.label("использован" if bool(m["used"]) else str(d.get("cond", "")), "sans", 11, Palette.TEXT_DIM)
		c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.custom_minimum_size.x = 150
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(c)
		_hand_box.add_child(box)


## Навык срабатывает: карта выходит из героя, встаёт рядом, загорается её условие и эффект — и карта возвращается.
func _show_memories(list: Array) -> void:
	for m: Dictionary in list:
		if not is_inside_tree() or not is_instance_valid(_hero_card):
			return
		var c := ContentDB.data
		var src_card := str(m["card"])
		var owner_card: Control = _hero_card
		var from := owner_card.get_global_rect()
		var csz := Vector2(170, 291)
		var card := CardView.make(src_card, csz, false)
		card.hover_lift = false
		card.smoke_on_hover = false
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.top_level = true
		card.z_index = 60
		card.pivot_offset = csz / 2
		card.global_position = from.get_center() - csz / 2
		card.scale = Vector2(0.3, 0.3)
		card.modulate.a = 0.0
		card.highlight = true
		add_child(card)
		var target := Vector2(from.end.x + 30, from.position.y + from.size.y / 2 - csz.y / 2)
		if target.x + csz.x + 420 > get_viewport_rect().size.x:
			target.x = from.position.x - 30 - csz.x - 420
		# тёмная плашка под картой и надписью — поверх того, что стоит рядом с героем
		var bg := Panel.new()
		bg.top_level = true
		bg.z_index = 59
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.05, 0.07, 0.95), Palette.GOLD.darkened(0.15), 1, 10, 0))
		bg.global_position = target - Vector2(16, 16)
		bg.size = Vector2(csz.x + 18 + 400 + 36, csz.y + 32)
		bg.modulate.a = 0.0
		add_child(bg)
		var info := VBoxContainer.new()
		info.top_level = true
		info.z_index = 60
		info.add_theme_constant_override("separation", 6)
		info.custom_minimum_size = Vector2(400, 0)
		info.global_position = target + Vector2(csz.x + 18, 40)
		info.modulate.a = 0.0
		var title := UITheme.label("✦ " + str(m.get("name", "")), "title_bold", 28, Palette.GOLD)
		info.add_child(title)
		var who := UITheme.label(c.card_name(src_card) + ("" if str(m.get("owner", "")) == GameState.combat.hero else " · " + c.card_name(str(m["owner"]))), "sans", 15, Palette.TEXT_DIM)
		info.add_child(who)
		var cond := UITheme.label("Условие: " + str(m.get("cond", "")), "sans_bold", 17, Palette.TEXT)
		cond.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cond.custom_minimum_size.x = 400
		info.add_child(cond)
		var eff := UITheme.label("→ " + str(m.get("text", "")), "serif_italic", 19, Palette.SILVER)
		eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		eff.custom_minimum_size.x = 400
		info.add_child(eff)
		add_child(info)
		AudioManager.play("open", -4.0, 1.25)
		var shelf := _memory_node(src_card)
		if shelf != _hero_card and is_instance_valid(shelf):
			var st := create_tween()
			st.tween_property(shelf, "modulate", Color(1.6, 1.4, 0.8), 0.2)
			st.tween_property(shelf, "modulate", Color.WHITE, 0.6)
		var t1 := create_tween().set_parallel()
		t1.tween_property(card, "global_position", target, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t1.tween_property(card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t1.tween_property(card, "modulate:a", 1.0, 0.2)
		t1.tween_property(info, "modulate:a", 1.0, 0.3).set_delay(0.2)
		t1.tween_property(bg, "modulate:a", 1.0, 0.25)
		await t1.finished
		# условие загорается золотом
		var glow := create_tween()
		glow.tween_property(cond, "modulate", Color(1.8, 1.5, 0.7), 0.25)
		glow.tween_property(cond, "modulate", Color(1.2, 1.1, 0.85), 0.4)
		var spark := Vfx.embers_burst(Rect2(target, csz))
		add_child(spark)
		spark.emitting = true
		Vfx.autofree(spark)
		await get_tree().create_timer(0.35 if Vfx.reduced() else 1.35).timeout
		if not is_instance_valid(card):
			return
		# карта возвращается в героя
		var back := owner_card.get_global_rect().get_center() - csz / 2 if is_instance_valid(owner_card) else target
		var t2 := create_tween().set_parallel()
		t2.tween_property(card, "global_position", back, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		t2.tween_property(card, "scale", Vector2(0.3, 0.3), 0.3)
		t2.tween_property(card, "modulate:a", 0.0, 0.3)
		t2.tween_property(info, "modulate:a", 0.0, 0.25)
		t2.tween_property(bg, "modulate:a", 0.0, 0.25)
		await t2.finished
		card.queue_free()
		info.queue_free()
		bg.queue_free()
		if is_instance_valid(_hero_card):
			_hero_card.shudder()


func _clear_hand() -> void:
	for c in _hand_box.get_children():
		c.queue_free()


## Главный эффект — «набор силы»: числа обеих сторон растут с нуля шаг за шагом в порядке расчёта
## (база → теги → симбиозы → конфликты → поле → раунд → состояния → навыки карт → намерение → характеристика).
## У каждого шага — подпись у числа; связи бьют лучами от тега к тегу в момент своего шага.
## При повторном показе (from_base = false) досчитывается только разница. Щелчок по полю — сразу к итогу.
func _play_links(cs: CombatSession, led: Dictionary, from_base: bool) -> void:
	_anim_token += 1
	var token := _anim_token
	var prev := _last_led
	_last_led = led
	_show_ledger(cs, led, true)
	if Vfx.reduced():
		_finish_anim(led)
		return
	if not from_base and not prev.is_empty():
		await _play_diff(led, prev, token)
		return
	_scale.reset()
	_scale.building = true
	await get_tree().create_timer(0.3).timeout
	var timeline := _timeline(cs, led)
	var step_time := clampf(4.5 / maxf(1.0, timeline.size()), 0.34, 0.55)
	var li := 0
	for entry: Dictionary in timeline:
		if token != _anim_token or not is_inside_tree():
			return
		# лучи связей этого шага — одновременно
		var fired: Array = []
		var dur := 0.0
		for l: Dictionary in entry["links"]:
			var f := _fire_link(l, li)
			li += 1
			dur = maxf(dur, float(f["dur"]))
			fired.append(f)
		if dur > 0.0:
			AudioManager.play("tick", -14.0, 1.2 + li * 0.04)
			await get_tree().create_timer(dur).timeout
			if token != _anim_token or not is_inside_tree():
				return
			for f: Dictionary in fired:
				_land_link(f)
		var st: Dictionary = entry["step"]
		if st.is_empty():
			continue
		if st.get("kind", "") == "tags":
			var col := Palette.SILVER if entry["side"] == "hero" else Palette.STAT_DOWN
			for t: Variant in st.get("tags", []):
				var chip := _tag_node(str(t), [entry["side"]])
				if chip is TagChip:
					(chip as TagChip).flash(col)
		_scale.step(entry["side"], float(st["value"]), _step_caption(st), _step_color(st, entry["side"]), step_time * 0.85)
		AudioManager.play("tick", -12.0, 0.8 if entry["side"] == "enemy" else 1.0)
		await get_tree().create_timer(step_time).timeout
	if token == _anim_token and is_inside_tree():
		_finish_anim(led)


## Итог без анимации: числа и шанс на месте, намерение отмечено.
func _finish_anim(led: Dictionary) -> void:
	_scale.building = false
	_scale.set_values(float(led["hero"]), float(led["enemy"]), int(led["chance"]), 0.25)
	_mark_intent(led)


## Щелчок по полю во время набора силы — сразу к итогу.
func _skip_anim() -> void:
	if not _scale.building or _last_led.is_empty():
		return
	_anim_token += 1
	_finish_anim(_last_led)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_skip_anim()


## Смена приёма: новые связи бьют лучами, числа доезжают до новых значений, у чисел — что изменилось.
func _play_diff(led: Dictionary, prev: Dictionary, token: int) -> void:
	_scale.building = true
	var old_ids := _link_ids(prev)
	var fired: Array = []
	var dur := 0.0
	var i := 0
	for l: Dictionary in led["links"]:
		if not old_ids.has(str(l["id"])):
			var f := _fire_link(l, i)
			i += 1
			dur = maxf(dur, float(f["dur"]))
			fired.append(f)
	if dur > 0.0:
		await get_tree().create_timer(dur).timeout
		if token != _anim_token or not is_inside_tree():
			return
		for f: Dictionary in fired:
			_land_link(f)
	for side: String in ["hero", "enemy"]:
		var key := side + "_steps"
		var cap := _diff_caption(prev[key], led[key])
		_scale.step(side, float(led[side]), cap, Palette.TEXT, 0.6)
	await get_tree().create_timer(0.65).timeout
	if token == _anim_token and is_inside_tree():
		_finish_anim(led)


## Очередь шагов обеих сторон со связями, привязанными к своему шагу.
func _timeline(cs: CombatSession, led: Dictionary) -> Array:
	var by_key := {}
	for l: Dictionary in led["links"]:
		var k := "%s:%s" % [l["side"], _link_stage(cs, l)]
		if not by_key.has(k):
			by_key[k] = []
		by_key[k].append(l)
	var out: Array = []
	for stage: String in STAGES:
		for side: String in ["hero", "enemy"]:
			var k := "%s:%s" % [side, stage]
			var steps: Array = led[side + "_steps"]
			var had := false
			for st: Dictionary in steps:
				if st.get("kind", "") == stage:
					out.append({"side": side, "step": st, "links": by_key.get(k, []) if not had else []})
					had = true
			if not had and by_key.has(k):
				out.append({"side": side, "step": {}, "links": by_key[k]})
	return out


func _link_stage(cs: CombatSession, l: Dictionary) -> String:
	var id := str(l["id"])
	if id.begins_with("env:"):
		return "field" if id.begins_with("env:%s>" % cs.field.get("id", "")) else "round_no"
	if bool(l.get("intent", false)):
		return "intent"
	if id.begins_with("tac:"):
		return "conflict"
	return "synergy" if l["type"] == "synergy" else "conflict"


func _step_caption(st: Dictionary) -> String:
	if not st.has("pct"):
		return "%s  %d" % [st["label"], int(round(float(st["value"])))]
	var p := float(st["pct"])
	if absf(p) < 0.001:
		return str(st["label"])
	return "%s  %+d%%" % [st["label"], int(round(p * 100))]


## Цвет подписи с точки зрения героя: рост врага — красный, его ослабление — зелёный.
func _step_color(st: Dictionary, side: String) -> Color:
	if not st.has("pct"):
		return Palette.TEXT
	var p := float(st["pct"]) * (1.0 if side == "hero" else -1.0)
	return Palette.STAT_UP if p > 0.0 else (Palette.STAT_DOWN if p < 0.0 else Palette.TEXT_DIM)


## Подпись разницы: шаги, которых не было в прошлом расчёте (или с другим процентом).
func _diff_caption(old_steps: Array, new_steps: Array) -> String:
	var old_keys: Array = []
	for st: Dictionary in old_steps:
		old_keys.append("%s|%d" % [st["label"], int(round(float(st.get("pct", 0.0)) * 100))])
	var parts: Array = []
	for st: Dictionary in new_steps:
		if st.get("kind", "") == "base":
			continue
		if not old_keys.has("%s|%d" % [st["label"], int(round(float(st.get("pct", 0.0)) * 100))]):
			parts.append(_step_caption(st))
	return "  ·  ".join(parts.slice(0, 2))


## Запускает лучи одной связи; возвращает что нужно для попадания.
func _fire_link(l: Dictionary, i: int) -> Dictionary:
	var kind := "synergy" if l["type"] == "synergy" else "conflict"
	if str(l["id"]).begins_with("env:"):
		kind = "env"
	elif bool(l.get("intent", false)):
		kind = "intent"
	var col: Color = Beams.COLORS[kind]
	var dur := 0.0
	var hit: Array = []
	var land := Vector2()
	for seg: Array in _link_segments(l, kind):
		var na: Control = seg[0]
		var nb: Control = seg[1]
		if not is_instance_valid(na) or not is_instance_valid(nb):
			continue
		var a := _anchor_of(na)
		var b := _anchor_of(nb)
		if a.distance_to(b) < 30:
			b = a + Vector2(0, -120)
		dur = maxf(dur, _beams.fire(a, b, kind, i, _glass))
		if na is TagChip:
			(na as TagChip).flash(col)
		hit.append(nb)
		land = b
	return {"link": l, "kind": kind, "col": col, "dur": dur, "hit": hit, "land": land}


func _land_link(f: Dictionary) -> void:
	var l: Dictionary = f["link"]
	var col: Color = f["col"]
	for nb: Variant in f["hit"]:
		if is_instance_valid(nb) and nb is TagChip:
			(nb as TagChip).flash(col)
	var known: bool = ProfileService.is_known(str(l["id"])) or f["kind"] in ["env", "intent"]
	var v := float(l["value"])
	var txt := ("%+d%%" % int(round(v * 100))) if absf(v) > 0.001 else "✦"
	var label_name: String = str(l["name"]) if known else "???"
	if f["land"] != Vector2():
		Beams.popup(self, f["land"], "%s  %s" % [txt, label_name], col)


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
	_action_btn.disabled = true
	AudioManager.play("roll_shake", -4.0)
	var rec := cs.play_round()
	var led: Dictionary = rec["ledger"]
	_scale.building = false
	_scale.set_values(float(led["hero"]), float(led["enemy"]), int(led["chance"]), 0.2)
	var speed: float = SettingsService.get_value("roll_speed")
	_scale.play_roll(int(rec["roll"]), speed if speed > 0 else 0.05)
	await get_tree().create_timer(0.95 * maxf(speed, 0.1)).timeout
	AudioManager.play("roll", -6.0)
	var won: bool = rec["hero_won"]
	_clash(won)
	# реакции карт на проигранный раунд (отвести удар, Щит Эха)
	if not Array(rec.get("memories_lose", [])).is_empty():
		await _show_memories(rec["memories_lose"])
	_build_memories()
	_banner.text = ("РАУНД ВЫИГРАН" if won else "РАУНД ПРОИГРАН") + "  ·  шанс %d%% · выпало %d" % [int(rec["chance"]), int(rec["roll"])]
	_banner.add_theme_color_override("font_color", Palette.SILVER if won else Palette.STAT_DOWN)
	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.4)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.5)
	_show_ledger(cs, led, false)
	_update_pips()
	if rec.has("crisis"):
		var fx := CrisisFX.play(self, [rec["crisis"]])
		await fx.finished
		if is_instance_valid(_hero_card) and str(rec["crisis"].get("card", "")) == cs.hero:
			_hero_card.psy_override = str(rec["crisis"].get("state", ""))
			_hero_card.set_process(true)
	if cs.finished and is_instance_valid(_hero_card):
		_hero_card.psy_override = ""
	if is_instance_valid(_hero_card):
		_hero_card.queue_redraw()
	var fresh := ProfileService.discover(_link_ids(led))
	if not fresh.is_empty():
		await get_tree().create_timer(0.8).timeout
		await _reveal_links(fresh, led)
	_action_btn.disabled = false
	if cs.finished:
		_action_btn.text = "ЗАКРЫТЬ ›"
		var o := {"win": "ПОБЕДА", "loss": "ПОРАЖЕНИЕ", "death": "ГИБЕЛЬ"}
		_pips.text = "%s  %d : %d" % [o.get(cs.outcome, ""), cs.hero_wins, cs.enemy_wins]
	else:
		_action_btn.text = "СЛЕДУЮЩИЙ РАУНД ›"
		_replay_later(2.2)


func _clash(won: bool) -> void:
	var center := BOARD.position + Vector2(MID_X, SCALE_Y + 50)
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
				Vfx.blood_splash(self, e.get_global_rect().get_center(), e.size.x * 1.1)
	else:
		if not enemies.is_empty():
			var target: Control = enemies[0]
			var eb := target.position
			var tw2 := create_tween()
			tw2.tween_property(target, "position", eb + Vector2(0, 90), 0.12).set_ease(Tween.EASE_OUT)
			tw2.tween_property(target, "position", eb, 0.25)
		_hero_card.shudder()
		Vfx.blood_splash(self, _hero_card.get_global_rect().get_center(), _hero_card.size.x * 1.3)
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
	_finish()


func _finish() -> void:
	phase = Phase.DONE
	_anim_token += 1
	GameState.combat = null
	closed.emit()
	queue_free()


# --- отображение --------------------------------------------------------------------

func _update_pips() -> void:
	var cs := GameState.combat
	var marks := ""
	for r: Dictionary in cs.rounds_log:
		marks += "◆ " if r["hero_won"] else "✖ "
	_pips.text = "РАУНД %d  ·  %s  ·  %s" % [cs.round_no, marks if marks != "" else "—", cs.rounds_total_label()]


## Карта раунда разворачивается (содержимое уже заполнено в _layout).
func _reveal_round_card() -> void:
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


func _on_chip_hover(tag: String, on: bool) -> void:
	if on:
		_on_meta_hover("tag:" + tag)
	elif _hover_tag == tag:
		_on_meta_unhover(null)


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
