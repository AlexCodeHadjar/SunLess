extends Control
## Экран режима миссий (docs/15): карта главы — миссии лежат картами у своих локаций,
## над картой с отрядом — кольцо таймера; внизу — герои.
## Часы идут, пока открыт этот экран (таймеры только в игре).

const MAP_TOP := 72.0
const MAP_BOTTOM := 780.0
const LEFT_W := 250.0

var _backdrop: MapBackdrop
var _life: MapLife
var _fog: CPUParticles2D
var _embers: CPUParticles2D
var _sky := ""                # небо над картой (Atmosphere): night | day | eclipse | blood_moon
var _pins_layer: Control
var _markers := {}            # mission_id -> MissionMarker
var _shown_missions: Array = []
var _shops := {}              # shop_id -> ShopIcon
var _shop_window: ShopWindow
var _top_labels := {}
var _heroes_row: HBoxContainer
var _hero_cards := {}          # cid -> CardView
var _enh_cards := {}           # card -> CardView (метка — чей кармашек)
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
		_update_sky()
	var quiet := _end == null and _window == null and _shop_window == null and not _combat_open
	if GameState.state.game_over and quiet:
		_show_end()
	elif GameState.state.demo_complete and quiet:
		_show_chapter_end()


# --- построение ---------------------------------------------------------------

func _build_map() -> void:
	_backdrop = MapBackdrop.new()
	_backdrop.region = _region()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	_life = MapLife.new()
	_life.size = Vector2(1920, MAP_BOTTOM)
	add_child(_life)
	var area := Rect2(Vector2(LEFT_W - 200, MAP_TOP + 120), Vector2(1920 - LEFT_W + 400, MAP_BOTTOM - MAP_TOP - 120))
	_fog = Vfx.fog(area, 0.07)
	add_child(_fog)
	_embers = Vfx.ambient_embers(Rect2(Vector2(LEFT_W, MAP_TOP), Vector2(1920 - LEFT_W, MAP_BOTTOM - MAP_TOP)))
	add_child(_embers)
	_update_sky()
	_pins_layer = Control.new()
	_pins_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pins_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pins_layer)
	var c := ContentDB.data
	for sid: String in ShopRules.shops_of(c, GameState.state):
		var icon := ShopIcon.new()
		icon.shop_id = sid
		icon.title = str(c.shops[sid].get("name", sid))
		icon.pressed.connect(_open_shop)
		add_child(icon)
		icon.position = _map_point(c.shops[sid].get("pos", [0.5, 0.5])) - Vector2(110, 42)
		_shops[sid] = icon


func _region() -> String:
	var c := ContentDB.data
	for lid: String in c.locations:
		if str(c.locations[lid].get("chapter", "")) == GameState.state.chapter:
			return str(c.locations[lid].get("region", "mountain_pass"))
	return "mountain_pass"


func _map_point(p: Array) -> Vector2:
	var w := 1920.0
	var x := LEFT_W + 60 + (w - LEFT_W - 200) * float(p[0])
	var top := MAP_TOP + 280.0   # карты миссий стоят над точкой места — не залезать под верхнюю панель
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
	for item: Array in [["✦  КАРТА", "map"], ["✚  ЛАГЕРЬ", "camp"], ["✎  ЖУРНАЛ", "journal"], ["⚙  НАСТРОЙКИ", "settings"], ["⟵  В МЕНЮ", "menu"]]:
		if item[1] == "camp" and not TutorialRules.enabled(GameState.state, "camp"):
			continue
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
	_top_labels["shards"].tooltip_text = "Осколки душ: добыча с убитых тварей. Тратятся в магазине на карты усилений и персонажей."
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
	var head := UITheme.label("   ГЕРОИ И УСИЛЕНИЯ · героя — на карту миссии · усиление — на героя (в кармашек) · правый щелчок — планшет карты", "sans", 16, Palette.TEXT_DIM)
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
	add_child(HintPopup.new())


# --- обновление ---------------------------------------------------------------

func _refresh() -> void:
	var s := GameState.state
	var c := ContentDB.data
	# обучение (Ф12): подсказки по первому появлению механики
	GameState.tutorial("map")
	for ev: String in TutorialRules.state_events(c, s):
		GameState.tutorial(ev)
	_top_labels["chapter"].text = str(c.regions.get(_region(), {}).get("arc_name", "Глава"))
	var shards := int(s.resources.get("shards", 0))
	_top_labels["shards"].text = "✧ %d %s душ" % [shards, UITheme.plural(shards, ["осколок", "осколка", "осколков"])]
	var travelling := s.squads.filter(func(sq: Dictionary) -> bool: return sq["phase"] == "travel").size()
	var arrived := s.squads.size() - travelling
	_top_labels["squads"].text = "Отрядов в пути: %d%s" % [travelling, (" · прибыли: %d" % arrived) if arrived > 0 else ""]
	if s.collection != _shown_collection:
		_rebuild_cards()
	_update_badges()
	if _map_missions() != _shown_missions:
		_rebuild_markers()
	_update_pins()


## Небо над картой: день и ночь по часам, кровавая луна и затмение — по сюжету (Atmosphere).
## Смена неба красит и живую карту: туман, искры, облака и стаи.
func _update_sky() -> void:
	var next := Atmosphere.sky(ContentDB.data, GameState.state)
	if next == _sky:
		return
	var first := _sky == ""
	_sky = next
	if not _backdrop.has_sky_art():
		# нарисованный фон (Академия): день и ночь — временем суток
		_backdrop.set_tod(float(Atmosphere.TOD[next]), not first)
		_life.set_tod(float(Atmosphere.TOD[next]), not first)
		return
	_backdrop.set_sky(next, not first)
	_life.set_tod(float(Atmosphere.TOD[next]), not first)
	var tint := {"night": Color(1, 1, 1), "day": Color(1.1, 1.1, 1.15), "eclipse": Color(0.55, 0.58, 0.7),
		"blood_moon": Color(1.25, 0.45, 0.4)}
	var fog_tint := {"night": Color(1, 1, 1), "day": Color(1.2, 1.2, 1.25), "eclipse": Color(0.5, 0.52, 0.6),
		"blood_moon": Color(1.1, 0.6, 0.6)}
	if first or Vfx.reduced():
		_embers.modulate = tint[next]
		_fog.modulate = fog_tint[next]
	else:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_embers, "modulate", tint[next], MapBackdrop.FADE_SEC)
		tw.tween_property(_fog, "modulate", fog_tint[next], MapBackdrop.FADE_SEC)
	if not first and Atmosphere.OMENS.has(next):
		AudioManager.play("bell", -8.0, 0.55)
		_show_toast(str(Atmosphere.OMENS[next]))


func _rebuild_cards() -> void:
	var s := GameState.state
	var c := ContentDB.data
	_shown_collection = s.collection.duplicate()
	for ch in _heroes_row.get_children():
		ch.queue_free()
	_hero_cards.clear()
	_enh_cards.clear()
	var enh: Array = []
	for card: String in s.collection:
		var kind := c.card_kind(card)
		if kind == "character" and s.is_alive(card):
			var cv := CardView.make(card, CardView.SIZE_PANEL, true)
			cv.inspect_requested.connect(func(id: String) -> void: CardInspector.open_for(self, id))
			cv.clicked.connect(func(id: String) -> void: CardInspector.open_for(self, id))
			# усиление, брошенное на героя, ложится в его кармашек
			cv.set_drag_forwarding(Callable(cv, "_get_drag_data"),
				func(_at: Vector2, data: Variant) -> bool: return data is Dictionary and data.get("kind", "") == "enhancement",
				_on_pocket_drop.bind(card))
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
			var cv := CardView.make(card, CardView.SIZE_PANEL * 0.9, true)
			cv.inspect_requested.connect(func(id: String) -> void: CardInspector.open_for(self, id))
			cv.clicked.connect(func(id: String) -> void: CardInspector.open_for(self, id))
			_heroes_row.add_child(cv)
			_enh_cards[card] = cv


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
	for card: String in _enh_cards:
		var ev: CardView = _enh_cards[card]
		if not is_instance_valid(ev):
			continue
		var owner := MissionFlow.pocket_owner(s, card)
		var eb := ("у героя: %s" % c.card_name(owner)) if owner != "" else "не в кармашке"
		if ev.badge != eb:
			ev.badge = eb
			ev.draggable = owner == "" or not MissionFlow.on_mission(s, owner)
			ev.queue_redraw()


## Миссии, которые лежат на карте: открытые и те, к которым идёт или уже пришёл отряд.
func _map_missions() -> Array:
	var s := GameState.state
	var c := ContentDB.data
	var out: Array = MissionFlow.open_missions(s).filter(func(mid: String) -> bool: return MissionFlow.chapter_of(c, mid) == s.chapter)
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
		mk.fork_wait = false
		for sq: Dictionary in s.squads:
			if sq["mission"] != mid:
				continue
			if sq["phase"] == "arrived" or sq["phase"] == "fork":
				arrived = true
				mk.fork_wait = sq["phase"] == "fork"
			else:
				var total := maxf(0.1, float(sq["arrive_at"]) - float(sq["launched_at"]))
				progress = clampf((s.clock - float(sq["launched_at"])) / total, 0.0, 1.0)
				remaining = maxf(0.0, float(sq["arrive_at"]) - s.clock)
		mk.set_state(progress, remaining, arrived)
		# устаревающая миссия: срок — меткой на карте
		var left := MissionFlow.expires_in(ContentDB.data, s, mid)
		var badge := ("⌛ %d с" % int(ceil(left))) if left >= 0.0 and progress < 0.0 and not arrived else ""
		if badge != "" and str(ContentDB.data.missions.get(mid, {}).get("type", "")) == "onslaught":
			badge = "НАТИСК · " + badge
		if mk.card.badge != badge:
			mk.card.badge = badge
			mk.card.queue_redraw()
	for sid: String in _shops:
		var icon: ShopIcon = _shops[sid]
		icon.set_state(ShopRules.has_news(ContentDB.data, s, sid), ShopRules.missions_to_refresh(ContentDB.data, s, sid))


func _on_events(events: Array) -> void:
	for e: Dictionary in events:
		match str(e.get("kind", "")):
			"arrived":
				AudioManager.play("bell", -6.0, 1.2)
				_show_toast("%s — щёлкните по карте миссии" % e["text"])
			"rested", "expired":
				_show_toast(str(e["text"]))
			"onslaught":
				AudioManager.play("bell", -2.0, 0.7)
				_show_toast("%s — 60 с на ответ" % e["text"])
				GameState.tutorial("onslaught")
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
		if sq["phase"] == "arrived" or sq["phase"] == "fork":
			_open_window()
			_window.show_arrival(int(sq["id"]))
		else:
			_show_toast("Отряд ещё в пути: %d с" % int(ceil(float(sq["arrive_at"]) - GameState.state.clock)))
		return
	_open_window()
	_window.show_brief(mid)


func _on_pocket_drop(_at: Vector2, data: Variant, cid: String) -> void:
	var card := str(data["card"])
	if GameState.pocket_add(cid, card) == "":
		AudioManager.play("place")
		_show_toast("%s — в кармашке героя %s" % [ContentDB.data.card_name(card), ContentDB.data.card_name(cid)])
		_update_badges()


func _open_shop(sid: String) -> void:
	if is_instance_valid(_shop_window):
		_shop_window.queue_free()
	_shop_window = ShopWindow.open_for(self, sid)
	_shop_window.closed.connect(func() -> void:
		_shop_window = null
		_refresh())
	move_child(_toast, get_child_count() - 1)


## Героя бросили прямо на карту миссии — открываем брифинг, герой уже в отряде.
func _on_hero_dropped(mid: String, cid: String) -> void:
	for sq: Dictionary in GameState.state.squads:
		if sq["mission"] == mid:
			return
	_open_window()
	_window.show_brief(mid, cid)


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
		"journal":
			var jw := JournalWindow.new()
			add_child(jw)
			move_child(_toast, get_child_count() - 1)
		"camp":
			var cw := CampWindow.new()
			add_child(cw)
			cw.closed.connect(_refresh)
			move_child(_toast, get_child_count() - 1)
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


const CHAPTER_END := {
	"nightmare": "[Ты пробудился.] Всё, что было в горах, осталось в горах. Санни уносит с собой только себя — и тени, которые теперь идут за ним.",
	"academy": "Крышка капсулы закрывается. Сотни Спящих засыпают разом, и Царство Снов разбрасывает их кого куда. Где проснётся Санни — не знает никто.",
}


## Глава пройдена (миссия с end_chapter): дальше — следующая глава (next_chapter) или конец демо.
func _show_chapter_end() -> void:
	var s := GameState.state
	var c := ContentDB.data
	var next := str(s.flags.get("next_chapter", ""))
	_end = Control.new()
	_end.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_end)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.84)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end.add_child(dim)
	var v := VBoxContainer.new()
	v.position = Vector2(560, 300)
	v.custom_minimum_size.x = 800
	v.add_theme_constant_override("separation", 18)
	_end.add_child(v)
	var arc := str(c.regions.get(_region(), {}).get("arc_name", "Глава"))
	v.add_child(UITheme.label(("%s пройден" if s.chapter == "nightmare" else "%s: глава пройдена") % arc, "title_bold", 60, Palette.GOLD))
	var t := UITheme.label(str(CHAPTER_END.get(s.chapter, "Глава окончена.")), "serif_italic", 24, Palette.SILVER)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 800
	v.add_child(t)
	var names: Array = MissionFlow.heroes(c, s).map(func(cid: String) -> String: return c.card_name(cid))
	var shards := int(s.resources.get("shards", 0))
	v.add_child(UITheme.label("Миссий выполнено: %d  ·  героев с вами: %s  ·  ✧ %d %s душ" % [s.completed_missions, ", ".join(names), shards, UITheme.plural(shards, ["осколок", "осколка", "осколков"])], "sans", 20, Palette.TEXT_DIM))
	if next == "":
		v.add_child(UITheme.label("Конец демоверсии. Царство Снов — впереди.", "sans_bold", 20, Palette.TEXT))
	var b := Button.new()
	b.custom_minimum_size = Vector2(360, 64)
	b.add_theme_font_override("font", UITheme.font("caps"))
	b.add_theme_font_size_override("font_size", 28)
	if next != "":
		var next_name := next
		for lid: String in c.locations:
			if str(c.locations[lid].get("chapter", "")) == next:
				next_name = str(c.regions.get(str(c.locations[lid].get("region", "")), {}).get("arc_name", next))
				break
		b.text = "ДАЛЬШЕ: %s ›" % next_name.to_upper()
		b.pressed.connect(func() -> void:
			GameState.next_chapter()
			get_tree().reload_current_scene())
	else:
		b.text = "НОВАЯ ИГРА"
		b.pressed.connect(func() -> void:
			GameState.new_mission_run()
			get_tree().reload_current_scene())
	v.add_child(b)
	var menu := Button.new()
	menu.text = "В МЕНЮ"
	menu.custom_minimum_size = Vector2(360, 56)
	menu.pressed.connect(_on_nav.bind("menu"))
	v.add_child(menu)


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
