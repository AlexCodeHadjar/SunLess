class_name MissionMarker
extends Control
## Миссия на карте главы — карта (docs/15 §15). Пока отряда нет — просто карта: щелчок открывает брифинг,
## героя можно бросить прямо на неё. Отряд отправлен — над картой кольцо таймера с секундами;
## отряд прибыл — кольцо горит и пульсирует «!». Кольцо появляется с отскоком, последние секунды
## отстукивают тихим тиком, прибытие — вспышка искр.

signal pressed(mission_id: String)
signal hero_dropped(mission_id: String, card_id: String)

const RING_R := 30.0
const ICON_SIZE := Vector2(220.0, 128.0)   # ромб-событие: ромб, название, метка
const LOAD_TIME := 0.55                     # круг загрузки при наведении, потом рядом — карта события

var mission_id := ""
var progress := -1.0      # 0..1 — отряд в пути; -1 — отряда нет
var remaining := 0.0      # секунд до прибытия
var arrived := false
var fork_wait := false    # отряд стоит на развилке и ждёт решения игрока
var card: CardView
var zoom_on_hover := false  # на карте-плане метка мелкая: при наведении растёт, чтобы прочесть
var diamond := false        # событие ромбом (эксперимент 03.10): ромб и название; наведение — круг загрузки, затем карта
var _ring: Control
var _t := 0.0
var _hover := false
var _card_hover := false
var _load := 0.0
var _detail := false
var _close_in := 0.0
var _grow := 0.0
var _panel: PanelContainer   # подробная карточка ромба: карта события и сведения рядом
var _info_col: VBoxContainer
var _badge_label: Label
var _story := false        # сюжетный ромб пульсирует — его перерисовывать каждый кадр
var _was_anim := false     # прошлый кадр ромб двигался: дорисовать конечное положение
var _mods: Array = []      # модификаторы события: значки полукругом над ромбом (просьба владельца 03.10)
var _shine := 0.0          # задание показало это событие (docs/20): кольца расходятся от ромба


## Событие ромбом: как лавка — ромб и название; при наведении ромб растёт, вокруг рисуется круг, и рядом — карта.
static func make_icon(mid: String) -> MissionMarker:
	var m := MissionMarker.new()
	m.mission_id = mid
	m.diamond = true
	m.custom_minimum_size = ICON_SIZE
	m.size = ICON_SIZE
	return m


static func make(mid: String, card_size: Vector2) -> MissionMarker:
	var m := MissionMarker.new()
	m.mission_id = mid
	m.custom_minimum_size = card_size
	m.size = card_size
	return m


func _ready() -> void:
	if diamond:
		_ready_icon()
		return
	mouse_filter = Control.MOUSE_FILTER_PASS
	card = CardView.make(mission_id, size, false)
	card.sway = true
	card.highlight = str(ContentDB.data.missions.get(mission_id, {}).get("type", "")) == "story"
	card.clicked.connect(func(_id: String) -> void:
		AudioManager.play("open", -6.0)
		pressed.emit(mission_id))
	# правый щелчок по миссии — тоже брифинг (планшета у миссий нет)
	card.inspect_requested.connect(func(_id: String) -> void: pressed.emit(mission_id))
	card.set_drag_forwarding(Callable(), _can_drop, _drop)
	add_child(card)
	if zoom_on_hover:
		card.mouse_entered.connect(func() -> void: _zoom(true))
		card.mouse_exited.connect(func() -> void: _zoom(false))
	_add_mods()
	_ring = Control.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ring.draw.connect(_draw_ring)
	add_child(_ring)


func _ready_icon() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void:
		_hover = true
		AudioManager.play("hover", -16.0))
	mouse_exited.connect(func() -> void: _hover = false)
	# подробная карточка события — скрыта, пока круг загрузки не замкнётся
	var m: Dictionary = ContentDB.data.missions.get(mission_id, {})
	var typ := str(m.get("type", ""))
	_story = typ == "story"
	_mods = ModifierRules.of(ContentDB.data, GameState.state, mission_id)
	var tone: Color = Palette.GOLD if typ == "story" else (Color(1.0, 0.45, 0.4) if typ == "onslaught" else Palette.SILVER)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.035, 0.035, 0.05, 0.95), tone.darkened(0.35), 1, 10, 12))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_panel.visible = false
	_panel.modulate.a = 0.0
	_panel.z_index = 60
	_panel.mouse_entered.connect(func() -> void: _card_hover = true)
	_panel.mouse_exited.connect(func() -> void: _card_hover = false)
	_panel.gui_input.connect(_panel_input)
	_panel.set_drag_forwarding(Callable(), _can_drop, _drop)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)
	card = CardView.make(mission_id, CardView.SIZE_PANEL * 1.15, false)
	card.highlight = typ == "story"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size = card.size
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(card)
	_info_col = VBoxContainer.new()
	_info_col.custom_minimum_size = Vector2(250, 0)
	_info_col.add_theme_constant_override("separation", 6)
	_info_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_info_col)
	var title := UITheme.label(str(m.get("title", mission_id)), "title", 21, tone.lightened(0.2))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_col.add_child(title)
	var kinds := {"story": "Сюжет", "side": "Побочное", "random": "Встреча", "onslaught": "Натиск Кошмара"}
	_info_col.add_child(UITheme.label("%s · угроза %s" % [kinds.get(typ, "Событие"), "●".repeat(clampi(int(m.get("threat", 1)), 1, 5))],
		"sans_bold", 14, Palette.TEXT_DIM))
	_badge_label = UITheme.label("", "sans_bold", 14, Palette.GOLD)
	_info_col.add_child(_badge_label)
	_add_mods()
	var brief := UITheme.label(_short(str(m.get("briefing", "")), 230), "sans", 15, Palette.TEXT)
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_col.add_child(brief)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info_col.add_child(spacer)
	_info_col.add_child(UITheme.label("Щелчок — брифинг · героя — на ромб", "sans", 13, Palette.TEXT_DIM))
	for l in _info_col.get_children():
		(l as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		if l is Label:   # перенос строк — по ширине колонки, иначе карточка вытягивается в высоту
			(l as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			(l as Label).custom_minimum_size.x = 250.0
	add_child(_panel)
	_ring = Control.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ring.draw.connect(_draw_ring)
	add_child(_ring)


func _panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		AudioManager.play("open", -6.0)
		pressed.emit(mission_id)
		_panel.accept_event()


## Начало брифинга — до границы предложения или слова, не длиннее n знаков.
static func _short(text: String, n: int) -> String:
	if text.length() <= n:
		return text
	var cut := text.substr(0, n)
	var dot := cut.rfind(". ")
	if dot > n / 2:
		return cut.substr(0, dot + 1)
	return cut.substr(0, cut.rfind(" ")) + "…"


func _gui_input(event: InputEvent) -> void:
	if not diamond:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			AudioManager.play("open", -6.0)
			pressed.emit(mission_id)
			accept_event()


func _has_point(point: Vector2) -> bool:
	if not diamond:
		return Rect2(Vector2.ZERO, size).has_point(point)
	return body_rect().has_point(point) or _mod_at(point) >= 0


## Значки модификаторов над ромбом: центры по полукругу (середина — сверху).
func _mod_points() -> Array:
	var out: Array = []
	var n := _mods.size()
	if n == 0:
		return out
	var c := icon_center()
	var rr := _radius() + 27.0
	var step := deg_to_rad(36.0)
	for i in n:
		var a := -PI / 2.0 + (i - (n - 1) / 2.0) * step
		out.append(c + Vector2(cos(a), sin(a)) * rr)
	return out


## Над каким значком модификатора точка (-1 — ни над каким).
func _mod_at(point: Vector2) -> int:
	var pts := _mod_points()
	for i in pts.size():
		if (pts[i] as Vector2).distance_to(point) <= 13.0:
			return i
	return -1


## Подсказка над значком модификатора: название и что он делает.
func _get_tooltip(at_position: Vector2) -> String:
	if not diamond:
		return tooltip_text
	var i := _mod_at(at_position)
	if i < 0:
		return ""
	var d: Dictionary = _mods[i]
	return "%s — %s" % [d.get("name", ""), d.get("text", "")]


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	return diamond and _can_drop(at, data)


func _drop_data(at: Vector2, data: Variant) -> void:
	_drop(at, data)


## Задание показало это событие — вспышка (у ромба — кольца, у карты — свечение).
func flash() -> void:
	_shine = 1.0
	if not diamond:
		var tw := create_tween()
		tw.tween_property(self, "modulate", Color(1.6, 1.4, 0.9), 0.25)
		tw.tween_property(self, "modulate", Color.WHITE, 0.9)


## Центр ромба (в координатах метки) и его полуразмер.
func icon_center() -> Vector2:
	return Vector2(size.x / 2.0, _radius() + 10.0)


func _radius() -> float:
	var typ := str(ContentDB.data.missions.get(mission_id, {}).get("type", ""))
	return 30.0 if typ == "story" else (26.0 if typ in ["side", "onslaught"] else 22.0)


## Видимая часть метки (ромб и подпись) — чтобы фигура и другие метки её не закрывали.
func body_rect() -> Rect2:
	if not diamond:
		return Rect2(Vector2.ZERO, size)
	var r := _radius()
	var up := 34.0 if not _mods.is_empty() else 0.0   # значки модификаторов над ромбом — тоже видимая часть
	return Rect2(Vector2(size.x / 2.0 - 78.0, icon_center().y - r - 6.0 - up), Vector2(156.0, r * 2.0 + 62.0 + up))


## Видимая часть на экране — для подсказок-прожекторов и разрыва карты при удачном событии.
func body_global_rect() -> Rect2:
	var br := body_rect()
	var k := get_global_transform().get_scale()
	return Rect2(global_position + br.position * k, br.size * k)


func _show_detail(on: bool) -> void:
	_detail = on
	if on:
		_badge_label.text = card.badge
		_badge_label.visible = card.badge != ""
		_badge_label.add_theme_color_override("font_color", _badge_color(card.badge))
		_panel.reset_size()
		_place_card()
		_panel.visible = true
		AudioManager.play("fan", -12.0)
	var tw := create_tween()
	tw.tween_property(_panel, "modulate:a", 1.0 if on else 0.0, 0.0 if Vfx.reduced() else 0.18)
	if not on:
		tw.tween_callback(func() -> void: _panel.visible = false)


static func _badge_color(badge: String) -> Color:
	if badge.begins_with("↷"):
		return Palette.GOLD
	return Color(1.0, 0.55, 0.45) if badge.begins_with("⌛") or badge.begins_with("НАТИСК") else Palette.SILVER


## Подробная карточка — справа от ромба и его названия (у правого края экрана — слева), целиком в окне.
func _place_card() -> void:
	var vp := get_viewport_rect().size
	var c := icon_center()
	var gpos := global_position
	var k := get_global_transform().get_scale().x
	var ps := _panel.size
	var half := maxf(_radius() + 22.0, _title_w() / 2.0 + 14.0)
	var x := c.x + half
	if gpos.x + (x + ps.x) * k > vp.x - 16.0:
		x = c.x - half - ps.x
	var y := c.y - ps.y * 0.4
	var gy := gpos.y + y * k
	if gy < 16.0:
		y += (16.0 - gy) / k
	elif gy + ps.y * k > vp.y - 16.0:
		y -= (gy + ps.y * k - vp.y + 16.0) / k
	_panel.position = Vector2(x, y)


func _title_w() -> float:
	var typ := str(ContentDB.data.missions.get(mission_id, {}).get("type", ""))
	var fs := 16 if typ == "story" else 15
	var f := UITheme.font("sans_bold")
	var w := 0.0
	for line: String in _wrap(str(ContentDB.data.missions.get(mission_id, {}).get("title", mission_id)), f, fs, 138.0):
		w = maxf(w, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return w


## Модификаторы миссии (docs/16 §11.2) — значки над картой; подробности во всплывающей подсказке и брифинге.
func _add_mods() -> void:
	var mods := ModifierRules.of(ContentDB.data, GameState.state, mission_id)
	if mods.is_empty():
		return
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for d: Dictionary in mods:
		var tone: Color = Palette.MOD_TONE.get(str(d.get("tone", "mixed")), Palette.GOLD)
		var pill := PanelContainer.new()
		var st := UITheme.box(Color(0.04, 0.045, 0.06, 0.92), tone, 1, 10, 0)
		st.content_margin_left = 9
		st.content_margin_right = 9
		st.content_margin_top = 1
		st.content_margin_bottom = 2
		pill.add_theme_stylebox_override("panel", st)
		pill.tooltip_text = "%s — %s" % [d.get("name", ""), d.get("text", "")]
		pill.mouse_filter = Control.MOUSE_FILTER_STOP
		var l := UITheme.label("◆ " + str(d.get("name", "")), "sans_bold", 14, tone)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.add_child(l)
		col.add_child(pill)
	if diamond:   # у ромба значки — в подробной карточке, под типом события
		_info_col.add_child(col)
		return
	add_child(col)
	col.reset_size()
	# поверх верха карты: над ней в верхнем ряду места нет (панель и строка прилива)
	col.position = Vector2((size.x - col.size.x) / 2.0, 10.0)


func set_state(p: float, rem: float, arr: bool) -> void:
	var changed := arr != arrived or not is_equal_approx(p, progress) or int(ceil(rem)) != int(ceil(remaining))
	var was_busy := busy()
	var was_arrived := arrived
	var sec_before := int(ceil(remaining))
	progress = p
	remaining = rem
	arrived = arr
	if not was_busy and busy() and not arrived:
		_appear()
	elif busy() and not arrived and int(ceil(rem)) != sec_before and int(ceil(rem)) in [1, 2, 3]:
		AudioManager.play("tick", -14.0, 1.0 + 0.1 * (3 - int(ceil(rem))))
	if arrived and not was_arrived:
		_flash()
	if changed:
		card.dimmed = progress >= 0.0 and not arrived
		card.queue_redraw()
		_ring.queue_redraw()


## Кольцо таймера появляется над картой с отскоком.
func _appear() -> void:
	_ring.pivot_offset = Vector2(size.x / 2.0, size.y * 0.36)
	if Vfx.reduced():
		return
	_ring.scale = Vector2(0.2, 0.2)
	create_tween().tween_property(_ring, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Отряд прибыл: вспышка искр над картой и толчок кольца.
func _flash() -> void:
	_ring.pivot_offset = Vector2(size.x / 2.0, size.y * 0.36)
	if Vfx.reduced() or not is_inside_tree():
		return
	var fx := Vfx.burst(position + Vector2(size.x / 2.0, size.y * 0.36), true)
	get_parent().add_child(fx)
	Vfx.autofree(fx)
	_ring.scale = Vector2(1.35, 1.35)
	create_tween().tween_property(_ring, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _zoom(on: bool) -> void:
	pivot_offset = Vector2(size.x / 2.0, size.y)
	z_index = 20 if on else 0
	var k := 1.6 if on else 1.0
	if Vfx.reduced():
		scale = Vector2(k, k)
		return
	create_tween().tween_property(self, "scale", Vector2(k, k), 0.16).set_trans(Tween.TRANS_SINE)


func busy() -> bool:
	return arrived or progress >= 0.0


func _process(delta: float) -> void:
	_t += delta
	if arrived:
		_ring.queue_redraw()
	if not diamond:
		return
	# наведение: ромб растёт, круг загрузки рисуется вокруг и замыкается — открывается карта события
	_grow = move_toward(_grow, 1.0 if (_hover or _detail) else 0.0, delta * 7.0)
	if _hover:
		_load = minf(1.0, _load + delta / (0.0001 if Vfx.reduced() else LOAD_TIME))
		_close_in = 0.3
		if _load >= 1.0 and not _detail:
			_show_detail(true)
	elif _detail:
		if _card_hover:
			_close_in = 0.3
		else:
			_close_in -= delta
			if _close_in <= 0.0:
				_show_detail(false)
				_load = 0.0
	else:
		_load = maxf(0.0, _load - delta * 3.0)
	var z := 30 if (_hover or _detail) else 0
	if z_index != z:
		z_index = z
	# перерисовка — только пока ромб движется (наведение, круг, рост, отряд) или пульсирует сюжетный
	_shine = maxf(0.0, _shine - delta / 2.2)
	var anim := _hover or _detail or _load > 0.0 or (_grow > 0.0 and _grow < 1.0) or busy() or _story or _shine > 0.0
	if anim or _was_anim:
		queue_redraw()
	_was_anim = anim


func _draw() -> void:
	if not diamond:
		return
	var typ := str(ContentDB.data.missions.get(mission_id, {}).get("type", ""))
	var col: Color = Palette.GOLD if typ == "story" else (Color(1.0, 0.36, 0.3) if typ == "onslaught" else \
		(Color(0.84, 0.88, 0.97) if typ == "side" else Color(0.74, 0.7, 0.64)))
	var c := icon_center()
	var r := _radius() * (1.0 + 0.12 * _grow)
	# свечение под ромбом: сюжет и наведение — ярче
	var pulse := 0.5 + 0.5 * sin(_t * 2.4)
	for k in 3:
		draw_circle(c, r + 8.0 + k * 5.0, Color(col.r, col.g, col.b, (0.05 + 0.04 * _grow + (0.03 * pulse if typ == "story" else 0.0)) / (k + 1)))
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	draw_colored_polygon(pts, Color(0.06, 0.055, 0.09, 0.96))
	pts.append(pts[0])
	draw_polyline(pts, col.lightened(0.25 * _grow), 2.0 + _grow, true)
	# знак внутри: сюжет — звезда, побочное — ромбик, встреча — точка, Натиск — «!»
	if typ == "story":
		var star := PackedVector2Array()
		for i in 8:
			var a := TAU * i / 8.0 - PI / 2.0
			star.append(c + Vector2(cos(a), sin(a)) * (r * 0.5 if i % 2 == 0 else r * 0.18))
		draw_colored_polygon(star, col)
	elif typ == "onslaught":
		var bf := UITheme.font("title_bold")
		draw_string(bf, c + Vector2(-5, 11), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, col)
	elif typ == "side":
		var q := r * 0.34
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -q), c + Vector2(q, 0), c + Vector2(0, q), c + Vector2(-q, 0)]), col)
	else:
		draw_circle(c, r * 0.18, col)
	# задание показало событие: расходятся золотые кольца
	if _shine > 0.0:
		for k in 2:
			var f := fmod(1.0 - _shine + k * 0.5, 1.0)
			draw_arc(c, r + 8.0 + f * 46.0, 0.0, TAU, 48, Color(Palette.GOLD, (1.0 - f) * minf(1.0, _shine * 3.0)), 3.0, true)
	# круг загрузки: рисуется по часовой и замыкается — тогда открывается карта
	if _load > 0.0 and not busy():
		var lr := r + 12.0
		draw_arc(c, lr, 0.0, TAU, 64, Color(1, 1, 1, 0.12 * _grow), 3.0, true)
		var end := -PI / 2.0 + TAU * _load
		draw_arc(c, lr, -PI / 2.0, end, 64, Color(col.r, col.g, col.b, 0.95), 3.5, true)
		if _load < 1.0:   # огонёк на конце рисующейся линии
			var head := c + Vector2(cos(end), sin(end)) * lr
			draw_circle(head, 6.0, Color(col.r, col.g, col.b, 0.25))
			draw_circle(head, 3.0, Color(1, 1, 1, 0.95))
		if _load >= 1.0:
			draw_arc(c, lr + 4.0, 0.0, TAU, 64, Color(col.r, col.g, col.b, 0.35 * pulse), 2.0, true)
	_draw_mods()
	# название и метка (переход, срок) — под ромбом
	var title := str(ContentDB.data.missions.get(mission_id, {}).get("title", mission_id))
	var f := UITheme.font("sans_bold")
	var fs := 16 if typ == "story" else 15
	var lines := _wrap(title, f, fs, 138.0)
	var y := c.y + _radius() + 22.0 + (18.0 if busy() else 0.0)   # под кольцом отряда — его подпись
	for line: String in lines:
		var w := f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := Vector2(size.x / 2.0 - w / 2.0, y)
		draw_string_outline(f, p, line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.95))
		draw_string(f, p, line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE.lerp(col, 0.25) if _grow < 0.5 else Color.WHITE)
		y += fs + 3.0
	var badge := card.badge if card != null else ""
	if badge != "":
		var bf2 := UITheme.font("sans_bold")
		var bw := bf2.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var bp := Vector2(size.x / 2.0 - bw / 2.0, y + 2.0)
		var bc := _badge_color(badge)
		draw_string_outline(bf2, bp, badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 5, Color(0, 0, 0, 0.9))
		draw_string(bf2, bp, badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, bc)


## Значки модификаторов полукругом над ромбом: кружок цвета характера (хороший, плохой, смешанный) и знак.
func _draw_mods() -> void:
	var pts := _mod_points()
	for i in pts.size():
		var d: Dictionary = _mods[i]
		var p: Vector2 = pts[i]
		var tone: Color = (Palette.MOD_TONE.get(str(d.get("tone", "mixed")), Palette.GOLD) as Color).lightened(0.3)
		draw_circle(p, 15.5, Color(tone.r, tone.g, tone.b, 0.18))   # мягкий свет вокруг
		draw_circle(p, 13.0, Color(0.015, 0.018, 0.03, 0.97))
		draw_arc(p, 13.0, 0.0, TAU, 32, tone, 2.4, true)
		_mod_glyph(str(d.get("id", "")), p, tone.lightened(0.15))


## Знак модификатора (рисуется, без картинок): туман — волны, вожак — капля крови, проклятие — знак, гнездо — яйца,
## панцирь — щит, засада — скрещённые клинки, вода — волна с каплей, гроза — молния, тайник — сундук, спешка — песочные
## часы, Врата — арка с рангом, темнота — чёрная луна, толпа — головы.
func _mod_glyph(id: String, p: Vector2, col: Color) -> void:
	match id:
		"fog":
			for k in 3:
				var y := -4.0 + k * 4.0
				var pts := PackedVector2Array()
				for i in 9:
					pts.append(p + Vector2(-7.0 + i * 1.75, y + sin(i * 0.9 + k) * 1.2))
				draw_polyline(pts, col, 2.0, true)
		"wounded":
			var drop := PackedVector2Array()
			for i in 17:
				var a := TAU * i / 16.0
				var q := Vector2(cos(a) * 4.5, sin(a) * 4.5)
				if q.y < 0.0:
					q.y *= 1.8
				drop.append(p + Vector2(0, 2) + q)
			draw_colored_polygon(drop, Color(0.85, 0.15, 0.15))
		"cursed":
			draw_arc(p, 5.5, 0.0, TAU, 20, col, 2.1, true)
			draw_line(p + Vector2(0, -8), p + Vector2(0, 8), col, 2.1, true)
			draw_line(p + Vector2(-6, 3), p + Vector2(6, 3), col, 2.1, true)
		"nest":
			for q: Vector2 in [Vector2(-4, 2), Vector2(4, 2), Vector2(0, -3)]:
				draw_circle(p + q, 3.2, col)
		"armored":
			var sh := PackedVector2Array([p + Vector2(-6, -6), p + Vector2(6, -6), p + Vector2(5, 2), p + Vector2(0, 7),
				p + Vector2(-5, 2), p + Vector2(-6, -6)])
			draw_polyline(sh, col, 2.2, true)
			draw_line(p + Vector2(0, -6), p + Vector2(0, 6), col, 1.8, true)
		"ambush":
			draw_line(p + Vector2(-6, -6), p + Vector2(6, 6), col, 2.4, true)
			draw_line(p + Vector2(6, -6), p + Vector2(-6, 6), col, 2.4, true)
			draw_line(p + Vector2(-7, 3), p + Vector2(-3, 7), col, 2.2, true)
			draw_line(p + Vector2(7, 3), p + Vector2(3, 7), col, 2.2, true)
		"tidepools":
			var wv := PackedVector2Array()
			for i in 9:
				wv.append(p + Vector2(-7.0 + i * 1.75, 3.0 + sin(i * 0.9) * 1.6))
			draw_polyline(wv, col, 2.2, true)
			draw_circle(p + Vector2(0, -3), 2.5, col)
		"thunder":
			draw_colored_polygon(PackedVector2Array([p + Vector2(1, -8), p + Vector2(-5, 1), p + Vector2(0, 1), p + Vector2(-2, 8),
				p + Vector2(5, -2), p + Vector2(0, -2)]), col)
		"cache":
			draw_rect(Rect2(p + Vector2(-6, -3), Vector2(12, 8)), col, false, 1.6)
			draw_line(p + Vector2(-6, -1), p + Vector2(6, -1), col, 2.0, true)
			draw_circle(p + Vector2(0, 1), 1.4, col)
		"hurry":
			draw_polyline(PackedVector2Array([p + Vector2(-5, -7), p + Vector2(5, -7), p + Vector2(-5, 7), p + Vector2(5, 7),
				p + Vector2(-5, -7)]), col, 2.1, true)
		"gate_rank2", "gate_rank3":
			draw_arc(p + Vector2(0, 2), 6.0, PI, TAU, 14, col, 2.2, true)
			draw_line(p + Vector2(-6, 2), p + Vector2(-6, 7), col, 2.2, true)
			draw_line(p + Vector2(6, 2), p + Vector2(6, 7), col, 2.2, true)
			var n := 3 if id == "gate_rank3" else 2
			for k in n:
				var x := (k - (n - 1) / 2.0) * 2.6
				draw_line(p + Vector2(x, 0), p + Vector2(x, 5), col, 1.8, true)
		"blackout":
			draw_circle(p, 6.5, Color(0, 0, 0))
			draw_arc(p, 6.5, 0.0, TAU, 20, col, 2.0, true)
			draw_circle(p + Vector2(3, -3), 1.0, col)
		"panic_crowd":
			for q: Vector2 in [Vector2(-5, 2), Vector2(0, -1), Vector2(5, 2)]:
				draw_circle(p + q, 2.6, col)
			draw_line(p + Vector2(0, -9), p + Vector2(0, -5.5), col, 2.0, true)
		_:
			var f := UITheme.font("sans_bold")
			var t := str(_mods.filter(func(d: Dictionary) -> bool: return str(d.get("id", "")) == id)[0].get("name", "?")).left(1) \
				if _mods.any(func(d: Dictionary) -> bool: return str(d.get("id", "")) == id) else "?"
			var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(f, p + Vector2(-w / 2.0, 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


static func _wrap(text: String, f: Font, fs: int, width: float) -> Array:
	var out: Array = []
	var cur := ""
	for w: String in text.split(" "):
		var t := (cur + " " + w).strip_edges()
		if f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width or cur == "":
			cur = t
		else:
			out.append(cur)
			cur = w
	if cur != "":
		out.append(cur)
	return out.slice(0, 2)


func _can_drop(_at: Vector2, data: Variant) -> bool:
	return not busy() and data is Dictionary and data.get("kind", "") == "character"


func _drop(_at: Vector2, data: Variant) -> void:
	hero_dropped.emit(mission_id, str(data["card"]))


func _draw_ring() -> void:
	if not busy():
		return
	var c := icon_center() if diamond else Vector2(size.x / 2.0, size.y * 0.36)
	if arrived:
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		_ring.draw_circle(c, RING_R + 12.0 + 4.0 * pulse, Color(Palette.GOLD, 0.2 + 0.14 * pulse))
	_ring.draw_circle(c, RING_R, Color(0.05, 0.055, 0.075, 0.92))
	_ring.draw_arc(c, RING_R, 0.0, TAU, 56, Color(1, 1, 1, 0.12), 6.0, true)
	var gold := Color("#E3C98E")
	var p := 1.0 if arrived else clampf(progress, 0.0, 1.0)
	_ring.draw_arc(c, RING_R, -PI / 2.0, -PI / 2.0 + TAU * p, 56, gold, 6.0, true)
	var center := ("?" if fork_wait else "!") if arrived else "%dс" % int(ceil(remaining))
	var f := UITheme.font("title_bold")
	var fs := 32 if center.length() <= 2 else 24
	var tw := f.get_string_size(center, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_ring.draw_string(f, c + Vector2(-tw / 2.0, fs * 0.34), center, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, gold if arrived else Palette.TEXT)
	var cap := ("ждёт решения" if fork_wait else "отряд прибыл") if arrived else "отряд в пути"
	var sf := UITheme.font("sans_bold")
	var cw := sf.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var cp := c + Vector2(-cw / 2.0, RING_R + 22.0)
	_ring.draw_string_outline(sf, cp, cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color(0, 0, 0, 0.9))
	_ring.draw_string(sf, cp, cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, gold if arrived else Palette.SILVER)
