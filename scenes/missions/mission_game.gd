extends Control
## Экран режима миссий (docs/15): карта главы — миссии лежат картами у своих локаций,
## над картой с отрядом — кольцо таймера; внизу — герои.
## Часы идут, пока открыт этот экран (таймеры только в игре).

const MAP_TOP := 72.0
const MAP_BOTTOM := 780.0
const LEFT_W := 250.0

var _backdrop: MapBackdrop
var _pins_layer: Control
var _markers := {}            # mission_id -> MissionMarker
var _shown_missions: Array = []
var _top_labels := {}
var _heroes_row: HBoxContainer
var _hero_cards := {}          # cid -> CardView
var _shown_collection: Array = []
var _window: MissionWindow
var _toast: Label
var _toast_tw: Tween
var _end: Control
var _combat_open := false
var _badge_timer := 0.0


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not GameState.is_missions():
		GameState.new_mission_run()
	_build_map()
	_build_left()
	_build_top()
	_build_bottom()
	_build_toast()
	GameState.missions_changed.connect(_refresh)
	GameState.mission_events.connect(_on_events)
	EventBus.state_changed.connect(_refresh)
	EventBus.toast.connect(_show_toast)
	AudioManager.play_music()
	AudioManager.play_ambient()
	_refresh()
	if GameState.state.completed_missions == 0 and GameState.state.squads.is_empty():
		_show_toast("Щёлкните по карте миссии, прочтите её и отправьте отряд — или перетащите героя прямо на карту.")


func _process(delta: float) -> void:
	if not _combat_open:
		GameState.mission_tick(delta)
	_update_pins()
	_badge_timer -= delta
	if _badge_timer <= 0.0:
		_badge_timer = 0.5
		_update_badges()
	if GameState.state.game_over and _end == null and _window == null and not _combat_open:
		_show_end()


# --- построение ---------------------------------------------------------------

func _build_map() -> void:
	_backdrop = MapBackdrop.new()
	_backdrop.region = _region()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	var life := MapLife.new()
	life.size = Vector2(1920, MAP_BOTTOM)
	add_child(life)
	var area := Rect2(Vector2(LEFT_W - 200, MAP_TOP + 120), Vector2(1920 - LEFT_W + 400, MAP_BOTTOM - MAP_TOP - 120))
	add_child(Vfx.fog(area, 0.07))
	add_child(Vfx.ambient_embers(Rect2(Vector2(LEFT_W, MAP_TOP), Vector2(1920 - LEFT_W, MAP_BOTTOM - MAP_TOP))))
	_pins_layer = Control.new()
	_pins_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pins_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pins_layer)


func _region() -> String:
	var c := ContentDB.data
	for lid: String in c.locations:
		if str(c.locations[lid].get("chapter", "")) == GameState.state.chapter:
			return str(c.locations[lid].get("region", "mountain_pass"))
	return "mountain_pass"


func _map_point(p: Array) -> Vector2:
	var w := 1920.0
	var x := LEFT_W + 60 + (w - LEFT_W - 200) * float(p[0])
	var top := MAP_TOP + 200.0
	var y := top + (MAP_BOTTOM - 80.0 - top) * float(p[1])
	return Vector2(x, y)


func _build_left() -> void:
	var col := Control.new()
	col.size = Vector2(LEFT_W, MAP_BOTTOM)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.045, 0.06, 0.55)
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
	for item: Array in [["✦  КАРТА", "map"], ["⚙  НАСТРОЙКИ", "settings"], ["⟵  В МЕНЮ", "menu"]]:
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
	for key: String in ["chapter", "shards", "squads"]:
		var l := UITheme.label("", "title" if key == "chapter" else "sans", 24 if key == "chapter" else 19, Palette.TEXT)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		_top_labels[key] = l
		var sep := ColorRect.new()
		sep.color = Palette.LINE
		sep.custom_minimum_size = Vector2(1, 30)
		sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sep)
	_top_labels["shards"].add_theme_color_override("font_color", Palette.COINS)
	_top_labels["shards"].tooltip_text = "Осколки душ: добыча с убитых тварей. Скоро — магазин (раз в 7 миссий новый товар)."
	_top_labels["shards"].mouse_filter = Control.MOUSE_FILTER_STOP


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
	var head := UITheme.label("   ГЕРОИ И УСИЛЕНИЯ · перетащите героя на карту миссии · правый щелчок — планшет карты", "sans", 16, Palette.TEXT_DIM)
	head.custom_minimum_size.y = 34
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	scroll.add_child(margin)
	_heroes_row = HBoxContainer.new()
	_heroes_row.add_theme_constant_override("separation", 14)
	margin.add_child(_heroes_row)


func _build_toast() -> void:
	_toast = UITheme.label("", "sans_bold", 20, Palette.TEXT)
	# справа в верхней панели — не перекрывает ни карту, ни окна миссий
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toast.anchor_left = 1.0
	_toast.anchor_right = 1.0
	_toast.offset_left = -960
	_toast.offset_right = -36
	_toast.offset_top = 22
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_toast.modulate.a = 0.0
	_toast.z_index = 50
	add_child(_toast)


# --- обновление ---------------------------------------------------------------

func _refresh() -> void:
	var s := GameState.state
	var c := ContentDB.data
	_top_labels["chapter"].text = str(c.regions.get(_region(), {}).get("arc_name", "Глава"))
	_top_labels["shards"].text = "✧ %d осколков душ" % int(s.resources.get("shards", 0))
	var travelling := s.squads.filter(func(sq: Dictionary) -> bool: return sq["phase"] == "travel").size()
	var arrived := s.squads.size() - travelling
	_top_labels["squads"].text = "Отрядов в пути: %d%s" % [travelling, (" · прибыли: %d" % arrived) if arrived > 0 else ""]
	if s.collection != _shown_collection:
		_rebuild_cards()
	_update_badges()
	if _map_missions() != _shown_missions:
		_rebuild_markers()
	_update_pins()


func _rebuild_cards() -> void:
	var s := GameState.state
	var c := ContentDB.data
	_shown_collection = s.collection.duplicate()
	for ch in _heroes_row.get_children():
		ch.queue_free()
	_hero_cards.clear()
	var enh: Array = []
	for card: String in s.collection:
		var kind := c.card_kind(card)
		if kind == "character" and s.is_alive(card):
			var cv := CardView.make(card, CardView.SIZE_PANEL, true)
			cv.inspect_requested.connect(func(id: String) -> void: CardInspector.open_for(self, id))
			cv.clicked.connect(func(id: String) -> void: CardInspector.open_for(self, id))
			_heroes_row.add_child(cv)
			_hero_cards[card] = cv
		elif kind == "enhancement":
			enh.append(card)
	if not enh.is_empty():
		var sep := ColorRect.new()
		sep.color = Palette.LINE
		sep.custom_minimum_size = Vector2(1, 200)
		_heroes_row.add_child(sep)
		for card: String in enh:
			var cv := CardView.make(card, CardView.SIZE_PANEL * 0.9, false)
			cv.inspect_requested.connect(func(id: String) -> void: CardInspector.open_for(self, id))
			cv.clicked.connect(func(id: String) -> void: CardInspector.open_for(self, id))
			_heroes_row.add_child(cv)


func _update_badges() -> void:
	var s := GameState.state
	var c := ContentDB.data
	for cid: String in _hero_cards:
		var cv: CardView = _hero_cards[cid]
		if not is_instance_valid(cv):
			continue
		var why := MissionFlow.busy_reason(c, s, cid)
		var b := why if why != "" else "свободен"
		if cv.badge != b:
			cv.badge = b
			cv.draggable = why == ""
			cv.queue_redraw()


## Миссии, которые лежат на карте: открытые и те, к которым идёт или уже пришёл отряд.
func _map_missions() -> Array:
	var s := GameState.state
	var out: Array = MissionFlow.open_missions(s)
	for sq: Dictionary in s.squads:
		if not out.has(sq["mission"]):
			out.append(sq["mission"])
	out.sort()
	return out


func _rebuild_markers() -> void:
	var c := ContentDB.data
	_shown_missions = _map_missions()
	for ch in _pins_layer.get_children():
		ch.queue_free()
	_markers.clear()
	var by_loc := {}
	for mid: String in _shown_missions:
		var lid := str(c.missions[mid].get("location", ""))
		if not by_loc.has(lid):
			by_loc[lid] = []
		by_loc[lid].append(mid)
	for lid: String in by_loc:
		var loc: Dictionary = c.locations.get(lid, {})
		var foot := _map_point(loc.get("pos", [0.5, 0.5]))
		var here: Array = by_loc[lid]
		# сюжетные — крупнее и первыми; несколько миссий одной локации лежат веером
		here.sort_custom(func(a: String, b: String) -> bool:
			var sa := str(c.missions[a].get("type", "")) == "story"
			var sb := str(c.missions[b].get("type", "")) == "story"
			return sa and not sb if sa != sb else a < b)
		var sizes: Array = []
		var total_w := 0.0
		for mid: String in here:
			var sz := CardView.SIZE_PANEL * (1.1 if str(c.missions[mid].get("type", "")) == "story" else 0.95)
			sizes.append(sz)
			total_w += sz.x + 14.0
		var x := foot.x - (total_w - 14.0) / 2.0
		for i in here.size():
			var mid: String = here[i]
			var sz: Vector2 = sizes[i]
			var mk := MissionMarker.make(mid, sz)
			mk.position = Vector2(x, foot.y - sz.y)
			mk.pressed.connect(_open_mission)
			mk.hero_dropped.connect(_on_hero_dropped)
			_pins_layer.add_child(mk)
			_markers[mid] = mk
			x += sz.x + 14.0
		var name := UITheme.label(str(loc.get("name", lid)), "title", 20, Palette.SILVER)
		name.add_theme_constant_override("outline_size", 6)
		name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.size = Vector2(maxf(total_w, 260.0), 28)
		name.position = Vector2(foot.x - name.size.x / 2.0, foot.y + 6.0)
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pins_layer.add_child(name)


func _update_pins() -> void:
	var s := GameState.state
	for mid: String in _markers:
		var mk: MissionMarker = _markers[mid]
		var progress := -1.0
		var remaining := 0.0
		var arrived := false
		for sq: Dictionary in s.squads:
			if sq["mission"] != mid:
				continue
			if sq["phase"] == "arrived":
				arrived = true
			else:
				var total := maxf(0.1, float(sq["arrive_at"]) - float(sq["launched_at"]))
				progress = clampf((s.clock - float(sq["launched_at"])) / total, 0.0, 1.0)
				remaining = maxf(0.0, float(sq["arrive_at"]) - s.clock)
		mk.set_state(progress, remaining, arrived)


func _on_events(events: Array) -> void:
	for e: Dictionary in events:
		match str(e.get("kind", "")):
			"arrived":
				AudioManager.play("bell", -6.0, 1.2)
				_show_toast("%s — щёлкните по карте миссии" % e["text"])
			"rested":
				_show_toast(str(e["text"]))
			"mission":
				AudioManager.play("open", -8.0)
				_show_toast(str(e["text"]))
	_refresh()


# --- окна -----------------------------------------------------------------------

## Щелчок по карте миссии: нет отряда — брифинг; отряд прибыл — выбор действия; в пути — ждём.
func _open_mission(mid: String) -> void:
	for sq: Dictionary in GameState.state.squads:
		if sq["mission"] != mid:
			continue
		if sq["phase"] == "arrived":
			_open_window()
			_window.show_arrival(int(sq["id"]))
		else:
			_show_toast("Отряд ещё в пути: %d с" % int(ceil(float(sq["arrive_at"]) - GameState.state.clock)))
		return
	_open_window()
	_window.show_brief(mid)


## Героя бросили прямо на карту миссии — открываем брифинг, герой уже в отряде.
func _on_hero_dropped(mid: String, cid: String) -> void:
	_open_mission(mid)
	if _window and _window.mode == "brief":
		_window.call("_add_hero", cid)


func _open_window() -> void:
	if is_instance_valid(_window):
		_window.queue_free()
	_window = MissionWindow.new()
	_window.closed.connect(func() -> void:
		_window = null
		_refresh())
	_window.watch_combat.connect(_watch_combat)
	add_child(_window)
	move_child(_toast, get_child_count() - 1)


func _watch_combat(setup: Dictionary) -> void:
	_combat_open = true
	var cs := CombatScreen.new()
	add_child(cs)
	cs.open_replay(setup)
	cs.closed.connect(func() -> void: _combat_open = false)


func _on_nav(what: String) -> void:
	match what:
		"settings":
			_open_settings()
		"menu":
			SaveService.save_state(GameState.state)
			get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


func _open_settings() -> void:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			layer.queue_free())
	layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(560, 140)
	panel.size = Vector2(800, 760)
	layer.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(m)
	m.add_child(SettingsPanel.new())


func _show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tw:
		_toast_tw.kill()
	_toast_tw = create_tween()
	_toast.modulate.a = 1.0
	_toast_tw.tween_interval(3.0)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.8)


func _show_end() -> void:
	_end = Control.new()
	_end.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_end)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end.add_child(dim)
	var v := VBoxContainer.new()
	v.position = Vector2(560, 360)
	v.add_theme_constant_override("separation", 18)
	_end.add_child(v)
	v.add_child(UITheme.label("Героев не осталось", "title_bold", 64, Palette.TRAUMA_BRIGHT))
	v.add_child(UITheme.label("Тени помнят тех, кто ушёл. Прохождение окончено.", "serif_italic", 24, Palette.SILVER))
	var b := Button.new()
	b.text = "НОВАЯ ИГРА"
	b.custom_minimum_size = Vector2(360, 64)
	b.add_theme_font_override("font", UITheme.font("caps"))
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(func() -> void:
		GameState.new_mission_run()
		get_tree().reload_current_scene())
	v.add_child(b)
	var menu := Button.new()
	menu.text = "В МЕНЮ"
	menu.custom_minimum_size = Vector2(360, 56)
	menu.pressed.connect(_on_nav.bind("menu"))
	v.add_child(menu)
