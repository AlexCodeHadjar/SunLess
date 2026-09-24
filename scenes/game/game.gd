extends Control
## Игровой экран (docs/11 §4): фон региона, карты событий, левая колонка, верхняя полоса,
## нижняя панель коллекции и оверлеи.

const MAP_TOP := 72.0
const MAP_BOTTOM := 780.0
const LEFT_W := 250.0

var _backdrop: MapBackdrop
var _path: Control
var _markers: Control
var _map_drop: DropZone
var _top_labels := {}
var _pending_label: Label
var _tabs: HBoxContainer
var _cards_row: HBoxContainer
var _tab := "all"
var _tablet: EventTablet
var _result: ResultScreen
var _overlay_layer: Control
var _toast: Label
var _hint: Label
var _end: Control
var _fx_layer: Control
var _bubble: ThoughtBubble
var _last_lines := {}
var _commented_event := ""
var _pending_result: Dictionary = {}


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if GameState.state == null:
		GameState.new_run()
	_build_map()
	_build_left()
	_build_top()
	_build_bottom()
	_build_overlays()
	EventBus.state_changed.connect(_refresh)
	EventBus.toast.connect(_show_toast)
	EventBus.option_resolved.connect(_on_resolved)
	EventBus.draft_changed.connect(_on_draft_changed)
	AudioManager.play_music()
	AudioManager.play_ambient()
	_bubble = ThoughtBubble.new()
	add_child(_bubble)
	var idle := Timer.new()
	idle.wait_time = 38.0
	idle.autostart = true
	idle.timeout.connect(_on_idle)
	add_child(idle)
	EventBus.initiator_used.connect(_on_initiator_used)
	_refresh()
	if GameState.state.week == 1 and GameState.state.active_event_ids().is_empty():
		_think_later("new_run", "", 1.2)


# --- построение ---------------------------------------------------------------

func _build_map() -> void:
	_backdrop = MapBackdrop.new()
	_backdrop.region = GameState.state.region
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	_map_drop = DropZone.new()
	_map_drop.accepts = ["initiator"]
	_map_drop.show_frame = false
	_map_drop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_drop.offset_top = MAP_TOP
	_map_drop.anchor_bottom = 0
	_map_drop.offset_bottom = MAP_BOTTOM
	_map_drop.mouse_filter = Control.MOUSE_FILTER_PASS
	_map_drop.dropped.connect(func(card: String) -> void: GameState.use_initiator(card))
	add_child(_map_drop)
	_path = Control.new()
	_path.set_anchors_preset(Control.PRESET_FULL_RECT)
	_path.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_path.draw.connect(_draw_path)
	add_child(_path)
	# атмосфера: туман над долиной и искры от земли
	var area := Rect2(Vector2(LEFT_W - 200, MAP_TOP + 120), Vector2(1920 - LEFT_W + 400, MAP_BOTTOM - MAP_TOP - 120))
	add_child(Vfx.fog(area, 0.07))
	add_child(Vfx.ambient_embers(Rect2(Vector2(LEFT_W, MAP_TOP), Vector2(1920 - LEFT_W, MAP_BOTTOM - MAP_TOP))))
	_markers = Control.new()
	_markers.set_anchors_preset(Control.PRESET_FULL_RECT)
	_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_markers)
	_fx_layer = Control.new()
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)


## Точка «на земле» (узел пути); карта события стоит над ней.
func _map_point(p: Array) -> Vector2:
	var w := get_viewport_rect().size.x
	var x := LEFT_W + 60 + (w - LEFT_W - 200) * float(p[0])
	var top := MAP_TOP + 280.0
	var y := top + (MAP_BOTTOM - 26.0 - top) * float(p[1])
	return Vector2(x, y)


func _draw_path() -> void:
	var c := ContentDB.data
	var s := GameState.state
	var pts: Array[Vector2] = []
	var ids: Array = []
	var cur := "E01"
	while cur != "" and c.events.has(cur):
		pts.append(_map_point(c.events[cur].get("map_pos", [0.5, 0.5])))
		ids.append(cur)
		cur = str(c.events[cur].get("next", ""))
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var n := int(a.distance_to(b) / 14)
		for k in n:
			if k % 2 == 0:
				_path.draw_circle(a.lerp(b, float(k) / n), 1.6, Color(0.85, 0.82, 0.72, 0.35))
	for i in pts.size():
		var st: Dictionary = s.events.get(ids[i], {})
		var closed: bool = st.get("status", "") == "closed"
		var active: bool = st.get("status", "") == "active"
		_path.draw_circle(pts[i], 9, Color(0.06, 0.06, 0.08, 0.9))
		_path.draw_arc(pts[i], 9, 0, TAU, 24, Palette.GOLD if active else Palette.SILVER.darkened(0.4), 2.0)
		if closed:
			_path.draw_circle(pts[i], 4, Palette.SILVER)


func _build_left() -> void:
	var col := Control.new()
	col.position = Vector2.ZERO
	col.size = Vector2(LEFT_W, MAP_BOTTOM)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.04, 0.045, 0.06, 0.85))
	g.set_color(1, Color(0.04, 0.045, 0.06, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.size = Vector2(LEFT_W, MAP_BOTTOM)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(shade)
	var logo := UITheme.label("SunLess", "title", 58, Palette.TEXT)
	logo.position = Vector2(34, 14)
	col.add_child(logo)
	var sub := UITheme.label("И  ТЕНИ  ПОМНЯТ", "sans", 12, Palette.TEXT_DIM)
	sub.position = Vector2(46, 86)
	col.add_child(sub)
	var nav := VBoxContainer.new()
	nav.position = Vector2(22, 150)
	nav.add_theme_constant_override("separation", 6)
	col.add_child(nav)
	for item: Array in [["✦  КАРТА", "map"], ["▣  КАРТЫ", "cards"], ["❧  ЖУРНАЛ", "journal"], ["⚙  НАСТРОЙКИ", "settings"], ["⟵  В МЕНЮ", "menu"]]:
		var b := Button.new()
		b.text = item[0]
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(200, 44)
		b.add_theme_font_override("font", UITheme.font("caps"))
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_color_override("font_color", Palette.TEXT if item[1] == "map" else Palette.TEXT_DIM)
		b.pressed.connect(_on_nav.bind(item[1]))
		nav.add_child(b)


func _build_top() -> void:
	var bar := PanelContainer.new()
	var st := UITheme.box(Color(0.03, 0.035, 0.05, 0.88), Palette.LINE, 0, 0, 0)
	st.border_width_bottom = 1
	bar.add_theme_stylebox_override("panel", st)
	bar.position = Vector2(LEFT_W, 0)
	bar.anchor_right = 1.0
	bar.offset_left = LEFT_W
	bar.offset_bottom = MAP_TOP
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	bar.add_child(row)
	var pad := Control.new()
	pad.custom_minimum_size.x = 8
	row.add_child(pad)
	for key: String in ["region", "week", "mana", "coins"]:
		var l := UITheme.label("", "title" if key == "region" else "sans", 22 if key == "region" else 19, Palette.TEXT)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		_top_labels[key] = l
		var sep := ColorRect.new()
		sep.color = Palette.LINE
		sep.custom_minimum_size = Vector2(1, 30)
		sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sep)
	_top_labels["mana"].add_theme_color_override("font_color", Palette.MANA)
	_top_labels["mana"].tooltip_text = "Мана: Прозрение 1, Концентрация 3, Оберег 4, Медитация 5"
	_top_labels["mana"].mouse_filter = Control.MOUSE_FILTER_STOP
	_top_labels["coins"].add_theme_color_override("font_color", Palette.COINS)
	_top_labels["coins"].tooltip_text = "Осколки душ: добыча с убитых тварей; лечение, покупки, ремонт у кузнеца"
	_top_labels["coins"].mouse_filter = Control.MOUSE_FILTER_STOP
	_pending_label = UITheme.label("", "serif_italic", 18, Palette.GOLD)
	_pending_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pending_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_pending_label)
	_hint = UITheme.label("", "serif_italic", 18, Palette.SILVER)
	_hint.position = Vector2(LEFT_W + 40, MAP_TOP + 14)
	add_child(_hint)


func _build_bottom() -> void:
	var panel := PanelContainer.new()
	var st := UITheme.box(Color(0.055, 0.06, 0.08, 0.95), Palette.LINE, 0, 0, 0)
	st.border_width_top = 1
	panel.add_theme_stylebox_override("panel", st)
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.anchor_right = 1.0
	panel.offset_top = -(1080 - MAP_BOTTOM)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	_tabs = HBoxContainer.new()
	_tabs.custom_minimum_size.y = 44
	_tabs.add_theme_constant_override("separation", 4)
	v.add_child(_tabs)
	var pad := Control.new()
	pad.custom_minimum_size.x = 40
	_tabs.add_child(pad)
	for t: Array in [["ВСЕ", "all"], ["ПЕРСОНАЖИ", "character"], ["УСИЛЕНИЯ", "enhancement"], ["ИНИЦИАТОРЫ", "initiator"]]:
		var b := Button.new()
		b.text = t[0]
		b.toggle_mode = true
		b.button_pressed = t[1] == _tab
		b.custom_minimum_size = Vector2(170, 42)
		b.add_theme_font_override("font", UITheme.font("caps"))
		b.add_theme_font_size_override("font_size", 18)
		b.set_meta("tab", t[1])
		b.pressed.connect(_on_tab.bind(t[1]))
		_tabs.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 250
	scroll.follow_focus = true
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 48)
	scroll.add_child(margin)
	_cards_row = HBoxContainer.new()
	_cards_row.add_theme_constant_override("separation", 14)
	margin.add_child(_cards_row)


func _build_overlays() -> void:
	_overlay_layer = Control.new()
	_overlay_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay_layer)
	_tablet = EventTablet.new()
	_tablet.visible = false
	_tablet.resolve_requested.connect(_on_resolve_requested)
	_tablet.closed.connect(_on_tablet_closed)
	add_child(_tablet)
	# нижняя панель должна оставаться доступной для перетаскивания: поднимаем её над планшетом
	_result = ResultScreen.new()
	_result.visible = false
	_result.continued.connect(_on_result_continue)
	add_child(_result)
	_toast = UITheme.label("", "sans_bold", 18, Palette.TEXT)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_left = -400
	_toast.offset_right = 400
	_toast.offset_top = 736
	_toast.modulate.a = 0.0
	add_child(_toast)


# --- обновление ---------------------------------------------------------------

func _refresh() -> void:
	var s := GameState.state
	if s == null:
		return
	var c := ContentDB.data
	var reg: Dictionary = c.regions.get(s.region, {})
	_top_labels["region"].text = str(reg.get("name", s.region))
	_top_labels["week"].text = "Неделя %d" % s.week
	_top_labels["mana"].text = "◈ %d" % int(s.resources.get("mana", 0))
	_top_labels["coins"].text = "✧ %d" % int(s.resources.get("shards", 0))
	_pending_label.text = "⋯ Надвигается следующая глава" if not s.pending_story.is_empty() else ""
	_rebuild_markers()
	_rebuild_cards()
	_path.queue_redraw()
	_update_hint()
	# нижняя панель поверх затемнения планшета, чтобы карты можно было тащить в кармашек
	var bottom: Control = _cards_row.get_parent().get_parent().get_parent().get_parent()
	if _tablet.visible:
		move_child(bottom, _tablet.get_index())
	else:
		move_child(bottom, _overlay_layer.get_index())
	if (s.game_over or s.demo_complete) and not _result.visible:
		_show_end()


func _rebuild_markers() -> void:
	for ch in _markers.get_children():
		ch.queue_free()
	var c := ContentDB.data
	for eid: String in GameState.state.active_event_ids():
		var ev: Dictionary = c.events[eid]
		var story: bool = ev.get("type", "") in ["story", "reward"]
		var sz := CardView.SIZE_PANEL if story else CardView.SIZE_SIDE
		var card := CardView.make(eid, sz, false)
		var p := _map_point(ev.get("map_pos", [0.5, 0.5]))
		card.position = p - Vector2(sz.x / 2, sz.y + 16)
		card.highlight = story
		card.sway = true
		card.set_process(true)
		card.tooltip_text = " "
		card.clicked.connect(_open_event)
		_markers.add_child(card)
		if story and not SettingsService.get_value("reduce_motion") and GameState.state.events[eid].get("spawned_week", 0) == GameState.state.week:
			card.modulate.a = 0.0
			create_tween().tween_property(card, "modulate:a", 1.0, 0.6)


func _rebuild_cards() -> void:
	for ch in _cards_row.get_children():
		ch.queue_free()
	for b in _tabs.get_children():
		if b is Button:
			b.button_pressed = b.get_meta("tab") == _tab
	var c := ContentDB.data
	var s := GameState.state
	var groups := {"character": [], "enhancement": [], "initiator": []}
	for card: String in s.collection:
		var k := c.card_kind(card)
		if groups.has(k):
			groups[k].append(card)
	var first := true
	for k: String in ["character", "enhancement", "initiator"]:
		if _tab != "all" and _tab != k:
			continue
		if groups[k].is_empty():
			continue
		if not first:
			var sep := ColorRect.new()
			sep.color = Palette.LINE
			sep.custom_minimum_size = Vector2(1, 200)
			_cards_row.add_child(sep)
		first = false
		for card: String in groups[k]:
			var cv := CardView.make(card, CardView.SIZE_PANEL, true)
			var de := s.draft_event_of(card)
			if de != "":
				cv.badge = "Черновик: %s" % de
			if _tablet.visible and de == _tablet.event_id:
				cv.highlight = true
			cv.clicked.connect(_on_card_clicked)
			_cards_row.add_child(cv)
	if first:
		_cards_row.add_child(UITheme.label("Здесь пока пусто.", "sans", 18, Palette.TEXT_DIM))


func _update_hint() -> void:
	var s := GameState.state
	var text := ""
	if SettingsService.get_value("tutorial"):
		if s.owns("I01") and s.active_event_ids().is_empty():
			text = "Перетащите карту «Первый сон» из нижней панели на карту мира."
		elif s.week == 1 and s.is_event_active("E01") and not _tablet.visible:
			text = "Нажмите на карту события, чтобы открыть его."
		elif s.owns("I02") and s.week <= 6 and not _tablet.visible:
			text = "Инициатор создаёт одно событие и исчезает. «Привал» — одно гарантированное лечение."
	_hint.text = text


# --- действия ----------------------------------------------------------------

func _open_event(eid: String) -> void:
	_tablet.open(eid)
	_commented_event = ""
	_refresh()
	var ev: Dictionary = ContentDB.data.events.get(eid, {})
	if _has_thought("event_open", eid):
		_think_later("event_open", eid, 0.5)
	elif ev.get("type", "") in ["random", "side"]:
		_think_later("event_open_random", "", 0.5)


func _on_card_clicked(card: String) -> void:
	var c := ContentDB.data
	var k := c.card_kind(card)
	if _tablet.visible:
		if k == "character":
			GameState.set_executor(_tablet.event_id, card)
		elif k == "enhancement":
			var d := GameState.draft(_tablet.event_id)
			if Array(d.get("enhancements", [])).has(card):
				GameState.detach(_tablet.event_id, card)
			else:
				var err := GameState.attach(_tablet.event_id, card)
				if err != "":
					_show_toast(err)
		elif k == "initiator":
			_show_toast("Инициатор перетаскивают на карту мира")
		_refresh()
	elif k == "initiator":
		_show_toast("Перетащите инициатор на карту мира")


func _on_tab(tab: String) -> void:
	_tab = tab
	_rebuild_cards()


func _on_resolve_requested(eid: String, oid: String) -> void:
	if str(ContentDB.data.option(eid, oid).get("check", "")) == "combat":
		var why := GameState.can_resolve(eid, oid)
		if why != "":
			_show_toast(why)
			return
		_tablet.visible = false
		_bubble.hide()
		var cs := CombatScreen.new()
		add_child(cs)
		cs.open(eid, oid)
		cs.closed.connect(_on_combat_closed.bind(eid))
		_think_later("combat_start", "", 1.0)
		return
	var r := GameState.resolve(eid, oid)
	if not r["ok"]:
		_show_toast(r["reason"])


func _on_resolved(result: Dictionary) -> void:
	_tablet.visible = false
	_bubble.hide()
	_pending_result = result
	var eid: String = result["event_id"]
	var marker: CardView = null
	for m in _markers.get_children():
		if m is CardView and (m as CardView).card_id == eid and not m.is_queued_for_deletion():
			marker = m
	if marker:
		# карту уносим из слоя маркеров, чтобы перестройка карты её не удалила
		marker.reparent(_fx_layer)
		move_child(_fx_layer, get_child_count() - 1)
		if not GameState.state.is_event_active(eid):
			marker.burn(1.3)
			await get_tree().create_timer(1.35).timeout
		else:
			marker.shudder()
			AudioManager.play("fail", -10.0, 0.8)
			await get_tree().create_timer(0.45).timeout
			marker.queue_free()
	_result.show_result(result)
	move_child(_result, get_child_count() - 1)


func _on_combat_closed(eid: String) -> void:
	# если бой отменён на подготовке — вернуть планшет
	if GameState.state.is_event_active(eid) and not _result.visible and _pending_result.get("event_id", "") != eid:
		_tablet.open(eid)


func _on_tablet_closed() -> void:
	_bubble.hide()
	_refresh()


func _on_result_continue() -> void:
	_refresh()
	var r := _pending_result
	if r.is_empty() or GameState.state.game_over:
		return
	var trigger := ""
	var broke := false
	for w: Dictionary in r.get("wear", []):
		if w["broken"]:
			broke = true
	var traumas: int = Array(GameState.state.character("P01").get("traumas", [])).size()
	if traumas >= 2 and not Array(r.get("traumas", [])).is_empty():
		trigger = "death_risk"
	elif broke:
		trigger = "item_broken"
	elif not Array(r.get("traumas", [])).is_empty():
		trigger = "trauma"
	elif r["success"] and r.get("progressed", false):
		trigger = "success_story"
	elif r["success"]:
		trigger = "success"
	else:
		trigger = "failure"
	for e: Dictionary in r.get("entries", []):
		if e.get("kind", "") == "card" and ContentDB.data.card_kind(str(e.get("card", ""))) == "character":
			trigger = "companion_joined"
	_think_later(trigger, "", 0.5)


func _on_draft_changed(eid: String) -> void:
	_rebuild_cards()
	if not _tablet.visible or eid != _tablet.event_id or _commented_event == eid:
		return
	var executor: String = GameState.draft(eid).get("character", "")
	if executor == "":
		return
	_commented_event = eid
	if executor != "P01":
		_think_later("executor_placed", "", 0.3, executor)
		return
	var best_story := -1
	var all_high := true
	for info: Dictionary in GameState.preview(eid):
		if info["done"] or not Array(info["blockers"]).is_empty():
			continue
		if bool(info["option"].get("story", false)):
			best_story = int(info["chance"])
		if int(info["chance"]) < 90:
			all_high = false
	if best_story >= 0 and best_story < 45:
		_think_later("chance_low", "", 2.5)
	elif all_high:
		_think_later("chance_high", "", 2.5)


func _on_initiator_used(eid: String) -> void:
	AudioManager.play("step")
	AudioManager.play("new_event", -6.0)
	_show_toast("Новое событие: " + ContentDB.data.events[eid]["title"])
	_think_later("initiator_used", "", 0.8)


func _on_idle() -> void:
	if _tablet.visible or _result.visible or _overlay_layer.get_child_count() > 0 or randf() < 0.4:
		return
	think("idle")


# --- мысли героя ------------------------------------------------------------------

func _has_thought(trigger: String, event_id: String) -> bool:
	for t: Dictionary in ContentDB.data.thoughts.values():
		if t.get("trigger", "") == trigger and str(t.get("event", "")) == event_id:
			return true
	return false


func _think_later(trigger: String, event_id: String, delay: float, who: String = "P01") -> void:
	await get_tree().create_timer(delay).timeout
	think(trigger, event_id, who)


## Показывает мысль персонажа над его картой (кармашек планшета или нижняя панель).
func think(trigger: String, event_id: String = "", who: String = "P01") -> void:
	if not SettingsService.get_value("thoughts") or GameState.state == null:
		return
	var candidates: Array = []
	for t: Dictionary in ContentDB.data.thoughts.values():
		if t.get("trigger", "") != trigger or t.get("who", "P01") != who:
			continue
		if event_id != "" and str(t.get("event", "")) != event_id:
			continue
		candidates.append(t)
	if candidates.is_empty():
		return
	var entry: Dictionary = candidates.pick_random()
	var lines: Array = entry.get("lines", [])
	if lines.is_empty():
		return
	var line: String = lines.pick_random()
	if lines.size() > 1 and _last_lines.get(entry["id"], "") == line:
		line = lines[(lines.find(line) + 1) % lines.size()]
	_last_lines[entry["id"]] = line
	var anchor := _hero_rect(who)
	if anchor.size == Vector2.ZERO:
		return
	move_child(_bubble, get_child_count() - 1)
	_bubble.say(line, anchor)


func _hero_rect(who: String) -> Rect2:
	for ch in get_children():
		if ch is CombatScreen and is_instance_valid(ch.get("_hero_card")):
			return (ch.get("_hero_card") as Control).get_global_rect()
	if _tablet.visible:
		return _tablet.pocket_rect()
	if _result.visible:
		return Rect2()
	for c in _cards_row.get_children():
		if c is CardView and (c as CardView).card_id == who:
			return (c as CardView).get_global_rect()
	return Rect2()


func _show_toast(text: String) -> void:
	_toast.text = text
	move_child(_toast, get_child_count() - 1)
	var tw := create_tween()
	_toast.modulate.a = 1.0
	tw.tween_interval(2.2)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_journal"):
		_on_nav("journal")
	elif event.is_action_pressed("ui_codex"):
		_on_nav("cards")


func _on_nav(what: String) -> void:
	match what:
		"map":
			_close_overlay()
		"cards":
			_open_overlay(_cards_overlay())
		"journal":
			_open_overlay(_journal_overlay())
		"settings":
			_open_overlay(SettingsPanel.new())
		"menu":
			get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


# --- оверлеи --------------------------------------------------------------------

func _close_overlay() -> void:
	for ch in _overlay_layer.get_children():
		ch.queue_free()
	_overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _open_overlay(content: Control) -> void:
	_close_overlay()
	_overlay_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	move_child(_overlay_layer, get_child_count() - 1)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	_overlay_layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(160, 100)
	panel.size = Vector2(1600, 880)
	_overlay_layer.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)
	var head := HBoxContainer.new()
	var title := UITheme.label(str(content.get_meta("title", "")), "caps", 28, Palette.SILVER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.add_theme_font_size_override("font_size", 24)
	close.pressed.connect(_close_overlay)
	head.add_child(close)
	v.add_child(head)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(content)


func _on_dim_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		_close_overlay()


func _cards_overlay() -> Control:
	var scroll := ScrollContainer.new()
	scroll.set_meta("title", "КАРТЫ")
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 24)
	scroll.add_child(grid)
	var c := ContentDB.data
	var s := GameState.state
	var cards: Array = []
	for card: String in s.collection:
		cards.append(card)
	for cid: String in s.characters:
		for t: String in s.characters[cid].get("traumas", []):
			cards.append(t)
	for card: String in cards:
		var cv := CardView.make(card, CardView.SIZE_ZOOM * 0.8, false)
		grid.add_child(cv)
	if cards.is_empty():
		grid.add_child(UITheme.label("Коллекция пуста.", "sans", 18, Palette.TEXT_DIM))
	return scroll


func _journal_overlay() -> Control:
	var scroll := ScrollContainer.new()
	scroll.set_meta("title", "ЖУРНАЛ")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	scroll.add_child(v)
	var c := ContentDB.data
	var log: Array = GameState.state.log.duplicate()
	log.reverse()
	for e: Dictionary in log:
		var text := ""
		if e.has("event"):
			var o := c.option(str(e["event"]), str(e["option"]))
			var roll := "без броска" if int(e.get("chance", 100)) >= 100 else "шанс %d%%, выпало %d" % [int(e["chance"]), int(e["roll"])]
			text = "Неделя %d · %s — «%s» · %s · %s · %s" % [int(e["week"]), c.events[e["event"]]["title"], o.get("label", ""), c.card_name(str(e["executor"])), roll, "успех" if e["success"] else "провал"]
		else:
			text = "Неделя %d · %s" % [int(e.get("week", 0)), str(e.get("text", ""))]
		var l := UITheme.label(text, "sans", 18, Palette.TEXT if e.get("success", true) else Palette.STAT_DOWN)
		v.add_child(l)
	return scroll


func _show_end() -> void:
	if _end:
		return
	var s := GameState.state
	_end = Control.new()
	_end.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end.add_child(dim)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	v.position = Vector2(560, 300)
	v.custom_minimum_size = Vector2(800, 0)
	_end.add_child(v)
	var dead := s.game_over
	var t := UITheme.label("ТЕНЬ УГАСЛА" if dead else "ПЕРВЫЙ КОШМАР ПРОЙДЕН", "title_bold", 60, Palette.STAT_DOWN if dead else Palette.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var info := "Санни погиб. Прохождение окончено." if dead else "[Заклинание Кошмара]: Ты прошёл испытание. Конец демоверсии."
	var il := UITheme.label(info, "serif_italic", 22, Palette.TEXT)
	il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(il)
	var stats := UITheme.label("Недель: %d · Событий разрешено: %d" % [s.week, _resolved_count()], "sans", 18, Palette.TEXT_DIM)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(stats)
	if dead and SaveService.has_save("before_turn"):
		var back := Button.new()
		back.text = "Вернуться к началу хода"
		back.custom_minimum_size = Vector2(0, 52)
		back.pressed.connect(_load_before_turn)
		v.add_child(back)
	var again := Button.new()
	again.text = "Новая игра"
	again.custom_minimum_size = Vector2(0, 52)
	again.pressed.connect(_new_game)
	v.add_child(again)
	var menu := Button.new()
	menu.text = "В главное меню"
	menu.custom_minimum_size = Vector2(0, 52)
	menu.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn"))
	v.add_child(menu)
	add_child(_end)


func _new_game() -> void:
	GameState.new_run()
	get_tree().reload_current_scene()


func _resolved_count() -> int:
	var n := 0
	for e: Dictionary in GameState.state.log:
		if e.has("event"):
			n += 1
	return n


func _load_before_turn() -> void:
	var r: Dictionary = SaveService.load_state(ContentDB.data, "before_turn")
	if r["ok"]:
		GameState.state = r["state"]
		SaveService.save_state(GameState.state)
		get_tree().reload_current_scene()
