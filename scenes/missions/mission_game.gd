extends Control
## Экран режима миссий (docs/15): карта главы — миссии лежат картами у своих локаций; внизу — герои.
## Карта занимает всё окно: глава, день и фаза — надписями прямо на ней, меню — строкой в углу,
## ряд героев — почти прозрачный. Карту-план можно чуть сдвинуть, зажав кнопку мыши.

const TRAY_H := 290.0           # высота ряда героев от низа окна (ряд лежит поверх карты)
# раскладка старой панорамы (главы без карты-плана): точки мест из locations.pos
const PANO_LEFT := 250.0
const PANO_TOP := 72.0
const PANO_BOTTOM := 780.0
const DRAG_START := 6.0         # столько пикселей мышь проходит, прежде чем карта поедет

var _backdrop: MapBackdrop      # старый фон главы (панорама); у глав с картой-планом — null
var _life: MapLife
var _sleeper: SleeperMap        # «Карта Спящего» (docs/16 §11.6): план сверху, если у региона есть data/maps
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
var _tide: TideLayer
var _memory: MemoryChoice      # выбор Воспоминания (LootRules) — после отчёта миссии
var _tide_banner: Label
var _shown_tide := ""     # прилив, при котором построены метки (новые проходы — перестроить)
var _badge_timer := 0.0
var _day_label: Label           # фаза недели и завтрашний день (DayRules)
var _camp_label: Label          # где стоит лагерь и что там за ночь
var _end_btn: Button            # «Закончить день»
var _night: Control             # окно «Ночь» после конца дня
var _plan_label: Label          # дела на сегодня (DayPlanner): миссии рядом, шаги, дела лагеря
var _tasks_row: HBoxContainer   # дела лагеря: Разведка, Сбор, Дозор
var _travel: Control            # окно перехода к месту (щелчок по месту на карте)
var _picker: Control            # выбор героя для дела лагеря
var _pan_layer: Control         # метки и лавки — едут вместе с картой-планом
var _drag_from := Vector2.ZERO  # где зажали кнопку мыши
var _drag_pan := Vector2.ZERO   # сдвиг карты в этот момент
var _dragging := false
var _drag_armed := false
var _relayout_in := -1.0        # окно сменило размер: через сколько секунд переложить карту


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not GameState.is_missions():
		GameState.new_mission_run()
	_build_map()
	_build_top()
	_build_nav()
	_build_bottom()
	_build_toast()
	GameState.missions_changed.connect(_refresh)
	get_viewport().size_changed.connect(func() -> void: _relayout_in = 0.2)
	GameState.mission_events.connect(_on_events)
	EventBus.state_changed.connect(_refresh)
	EventBus.toast.connect(_show_toast)
	AudioManager.play_music()
	AudioManager.play_ambient()
	# сюжетное окно главы (вступление при новой игре, переход между главами) — до карты, один раз
	var story := StoryRules.pending(ContentDB.data, GameState.state)
	if not story.is_empty():
		GameState.story_open = true
		var sc := StoryScreen.play(self, story, str(ContentDB.data.regions.get(_region(), {}).get("arc_name", "")))
		sc.finished.connect(func() -> void:
			StoryRules.mark_seen(GameState.state, GameState.state.chapter)
			SaveService.save_state(GameState.state)
			GameState.story_open = false
			_refresh()
			_first_toast())
	_refresh()
	if story.is_empty():
		_first_toast()


func _first_toast() -> void:
	if GameState.state.completed_missions == 0 and GameState.state.squads.is_empty():
		_show_toast("Щёлкните по карте миссии, прочтите её и отправьте отряд — или перетащите героя прямо на карту.")


func _process(delta: float) -> void:
	if _relayout_in >= 0.0:
		_relayout_in -= delta
		if _relayout_in < 0.0:
			_relayout()
	if not _combat_open and not GameState.story_open:
		GameState.mission_tick(delta)
	_update_pins()
	_badge_timer -= delta
	if _badge_timer <= 0.0:
		_badge_timer = 0.5
		_update_badges()
		_update_sky()
		_update_tide()
	var quiet := _end == null and _window == null and _shop_window == null and not _combat_open and _memory == null and _night == null
	# Воспоминание-добыча: выбор 1 из 3, как только отчёт закрыт
	if quiet and not GameState.state.game_over and not LootRules.pending(GameState.state).is_empty():
		_memory = MemoryChoice.open(self, LootRules.pending(GameState.state))
		_memory.done.connect(func() -> void:
			_memory = null
			_refresh())
		move_child(_toast, get_child_count() - 1)
		GameState.tutorial("memory")
		return
	if GameState.state.game_over and quiet:
		_show_end()
	elif GameState.state.demo_complete and quiet:
		_show_chapter_end()


# --- построение ---------------------------------------------------------------

func _build_map() -> void:
	var cfg := MapRules.config(ContentDB.data, GameState.state.chapter)
	if not cfg.is_empty():
		_sleeper = SleeperMap.make(cfg, Rect2(Vector2.ZERO, _screen()))
		add_child(_sleeper)
		_sleeper.panned.connect(func(off: Vector2) -> void:
			if _pan_layer != null:
				_pan_layer.position = off)
	else:
		_backdrop = MapBackdrop.new()
		_backdrop.region = _region()
		_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_backdrop)
		_life = MapLife.new()
		_life.size = Vector2(1920, 790)
		add_child(_life)
	var tray_top := _screen().y - TRAY_H
	_fog = Vfx.fog(Rect2(Vector2(-200, 160), Vector2(_screen().x + 400, tray_top - 160)), 0.07)
	add_child(_fog)
	_embers = Vfx.ambient_embers(Rect2(Vector2(0, 0), Vector2(_screen().x, tray_top)))
	add_child(_embers)
	_update_sky()
	_tide = TideLayer.new()
	add_child(_tide)
	_pan_layer = Control.new()
	_pan_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pan_layer.size = _screen()
	add_child(_pan_layer)
	_pins_layer = Control.new()
	_pins_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pins_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pan_layer.add_child(_pins_layer)
	var c := ContentDB.data
	for sid: String in ShopRules.shops_of(c, GameState.state):
		var icon := ShopIcon.new()
		icon.shop_id = sid
		icon.title = str(c.shops[sid].get("name", sid))
		icon.pressed.connect(_open_shop)
		_pan_layer.add_child(icon)
		icon.position = _shop_point(sid) - Vector2(110, 42)
		_shops[sid] = icon
	# лагерь — в середину видимой части карты
	if _sleeper != null:
		_sleeper.focus(_sleeper.center(c, GameState.state, GameState.state.party_at), Vector2(_screen().x / 2.0, (_screen().y - TRAY_H) * 0.5))
		_pan_layer.position = _sleeper.pan


## Настоящий размер окна в единицах интерфейса: при растяжении «expand» он шире или выше 1920×1080.
func _screen() -> Vector2:
	return get_viewport_rect().size


## Окно сменило размер (F11, другое соотношение сторон): карта-план, метки и лавки — под новое окно.
func _relayout() -> void:
	if _sleeper == null:
		return
	_sleeper.relayout(Rect2(Vector2.ZERO, _screen()))
	_pan_layer.size = _screen()
	for sid: String in _shops:
		(_shops[sid] as Control).position = _shop_point(sid) - Vector2(110, 42)
	_rebuild_markers()
	_update_pins()


func _region() -> String:
	var c := ContentDB.data
	for lid: String in c.locations:
		if str(c.locations[lid].get("chapter", "")) == GameState.state.chapter:
			return str(c.locations[lid].get("region", "mountain_pass"))
	return "mountain_pass"


## Где на экране стоит место: на карте-плане — его посадочное пятно, на панораме — точка из locations.
func _place_point(lid: String) -> Vector2:
	if _sleeper != null:
		return _sleeper.foot(ContentDB.data, GameState.state, lid)
	return _map_point(TideRules.pos(ContentDB.data, GameState.state, lid))


func _shop_point(sid: String) -> Vector2:
	if _sleeper != null and _sleeper.cfg.get("places", {}).has(sid):
		# над плитой алтаря, чтобы не спорить с метками соседних площадок
		return _sleeper.center(ContentDB.data, GameState.state, sid) - Vector2(0, MapRules.size_of(ContentDB.data, GameState.state, sid) * _sleeper.rect.size.x * 0.22)
	return _map_point(ContentDB.data.shops[sid].get("pos", [0.5, 0.5]))


func _map_point(p: Array) -> Vector2:
	var w := 1920.0
	var x := PANO_LEFT + 60 + (w - PANO_LEFT - 200) * float(p[0])
	var top := PANO_TOP + 280.0   # карты миссий стоят над точкой места — не залезать под надписи сверху
	var y := top + (PANO_BOTTOM - 80.0 - top) * float(p[1])
	return Vector2(x, y)


## Глава, осколки, день и фаза — надписями прямо на карте, без плашек.
func _build_top() -> void:
	var v := VBoxContainer.new()
	v.position = Vector2(34, 16)
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	_top_labels["chapter"] = _on_map_label(UITheme.label("", "title", 34, Palette.TEXT))
	v.add_child(_top_labels["chapter"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	_top_labels["squads"] = _on_map_label(UITheme.label("", "sans_bold", 20, Palette.SILVER))
	row.add_child(_top_labels["squads"])
	_top_labels["shards"] = _on_map_label(UITheme.label("", "sans_bold", 20, Palette.COINS))
	_top_labels["shards"].tooltip_text = "Осколки душ: добыча с убитых тварей. Тратятся в магазине на карты усилений и персонажей."
	_top_labels["shards"].mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(_top_labels["shards"])


## Надпись поверх карты: тёмная обводка вместо плашки.
func _on_map_label(l: Label) -> Label:
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	return l


## Меню — строкой в правом верхнем углу, без плашек.
func _build_nav() -> void:
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 4)
	nav.anchor_left = 1.0
	nav.anchor_right = 1.0
	nav.offset_left = -760
	nav.offset_right = -24
	nav.offset_top = 14
	nav.alignment = BoxContainer.ALIGNMENT_END
	nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(nav)
	for item: Array in [["✚ ЛАГЕРЬ", "camp"], ["✎ ЖУРНАЛ", "journal"], ["⚙ НАСТРОЙКИ", "settings"], ["⟵ МЕНЮ", "menu"]]:
		if item[1] == "camp" and not TutorialRules.enabled(GameState.state, "camp"):
			continue
		var b := Button.new()
		b.text = item[0]
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", UITheme.font("caps"))
		b.add_theme_font_size_override("font_size", 19)
		b.add_theme_color_override("font_color", Palette.TEXT_DIM)
		b.add_theme_color_override("font_hover_color", Palette.TEXT)
		b.add_theme_color_override("font_pressed_color", Palette.TEXT)
		b.add_theme_constant_override("outline_size", 7)
		b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		var empty := StyleBoxEmpty.new()
		empty.content_margin_left = 10
		empty.content_margin_right = 10
		for st: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			b.add_theme_stylebox_override(st, empty)
		b.pressed.connect(_on_nav.bind(item[1]))
		nav.add_child(b)
		HintTargets.put("nav_" + str(item[1]), [b])
	HintTargets.put("nav", [nav])


## Карту-план можно чуть сдвинуть, зажав кнопку мыши на свободном месте карты.
func _gui_input(event: InputEvent) -> void:
	if _sleeper == null:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
		var mb := event as InputEventMouseButton
		_drag_armed = mb.pressed
		if mb.pressed:
			_drag_from = mb.position
			_drag_pan = _sleeper.pan
		elif _dragging:
			_dragging = false
			mouse_default_cursor_shape = Control.CURSOR_ARROW
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_on_map_click(mb.position)
		accept_event()
	elif event is InputEventMouseMotion and _drag_armed:
		var d := (event as InputEventMouseMotion).position - _drag_from
		if not _dragging and d.length() >= DRAG_START:
			_dragging = true
			mouse_default_cursor_shape = Control.CURSOR_DRAG
		if _dragging:
			_sleeper.set_pan(_drag_pan + d)
			accept_event()


func _build_bottom() -> void:
	# ряд героев лежит поверх карты и почти прозрачен: снизу чуть темнее, чтобы читались надписи
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.025, 0.035, 0.0))
	grad.set_color(1, Color(0.02, 0.025, 0.035, 0.45))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.anchor_top = 1.0
	shade.anchor_bottom = 1.0
	shade.anchor_right = 1.0
	shade.offset_top = -(TRAY_H + 60)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.anchor_right = 1.0
	panel.offset_top = -TRAY_H
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	_build_day_panel()
	var head := _on_map_label(UITheme.label("   ГЕРОИ И УСИЛЕНИЯ · героя — на карту миссии · усиление — на героя (в кармашек) · правый щелчок — планшет карты", "sans", 15, Palette.TEXT_DIM))
	head.add_theme_constant_override("outline_size", 6)
	head.custom_minimum_size.y = 28
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(margin)
	_heroes_row = HBoxContainer.new()
	_heroes_row.add_theme_constant_override("separation", 14)
	_heroes_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_heroes_row)


## День и лагерь (docs/16 §12): фаза недели, стоянка, «Закончить день».
func _build_day_panel() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	# у правого нижнего края окна при любом соотношении сторон
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -490
	box.offset_right = -30
	box.offset_top = -20
	box.offset_bottom = -20
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN   # растёт вверх от нижнего края
	box.custom_minimum_size = Vector2(460, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_day_label = _on_map_label(UITheme.label("", "title", 21, Palette.TEXT))
	_day_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_day_label.custom_minimum_size.x = 460
	box.add_child(_day_label)
	_camp_label = _on_map_label(UITheme.label("", "sans", 16, Palette.SILVER))
	_camp_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_camp_label.custom_minimum_size.x = 460
	box.add_child(_camp_label)
	_plan_label = _on_map_label(UITheme.label("", "sans_bold", 16, Palette.TEXT))
	_plan_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plan_label.custom_minimum_size.x = 460
	box.add_child(_plan_label)
	HintTargets.put("day_plan", [_plan_label])
	_tasks_row = HBoxContainer.new()
	_tasks_row.add_theme_constant_override("separation", 8)
	box.add_child(_tasks_row)
	for task: String in DayPlanner.TASKS:
		var def := DayPlanner.task_def(ContentDB.data, task)
		if def.is_empty():
			continue
		var tb := Button.new()
		tb.name = task
		tb.text = str(def.get("name", task))
		tb.tooltip_text = str(def.get("text", "")) + "\nИсполнитель тратит выход (усталость, как за миссию). Каждое дело — раз в день."
		tb.custom_minimum_size = Vector2(148, 38)
		tb.add_theme_font_size_override("font_size", 17)
		tb.pressed.connect(_pick_task_hero.bind(task))
		_tasks_row.add_child(tb)
	HintTargets.put("tasks", [_tasks_row])
	_end_btn = Button.new()
	_end_btn.text = "ЗАКОНЧИТЬ ДЕНЬ ›"
	_end_btn.custom_minimum_size = Vector2(460, 64)
	_end_btn.add_theme_font_override("font", UITheme.font("caps"))
	_end_btn.add_theme_font_size_override("font_size", 24)
	_end_btn.tooltip_text = "Ночь в лагере: отдых, лечение на койках, починка; ночью может прийти беда. Утром — новый день недели."
	_end_btn.pressed.connect(_on_end_day)
	box.add_child(_end_btn)
	HintTargets.put("end_day", [_end_btn])


## Щелчок по карте без перетаскивания: по месту — окно перехода (docs/17 §2).
func _on_map_click(at: Vector2) -> void:
	var c := ContentDB.data
	var s := GameState.state
	if not DayRules.restricted(c, s):
		return
	var kn := MapRules.known(c, s)
	var best := ""
	var bd := INF
	for lid: String in MapRules.config(c, s.chapter).get("places", {}):
		if not kn.has(lid) or not c.locations.has(lid):
			continue
		var p := _sleeper.center(c, s, lid) + _sleeper.pan
		var r := MapRules.size_of(c, s, lid) * _sleeper.rect.size.x * 0.34
		var d := p.distance_to(at)
		if d < r and d < bd:
			bd = d
			best = lid
	if best != "":
		_show_travel(best)
	elif is_instance_valid(_travel):
		_close_travel()


func _close_travel() -> void:
	if is_instance_valid(_travel):
		_travel.queue_free()
	_travel = null


## Окно перехода: путь, цена, какой там лагерь; «Идти».
func _show_travel(lid: String) -> void:
	_close_travel()
	var c := ContentDB.data
	var s := GameState.state
	var loc: Dictionary = c.locations.get(lid, {})
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.04, 0.045, 0.06, 0.94), Palette.LINE, 1, 10, 16))
	panel.custom_minimum_size = Vector2(380, 0)
	add_child(panel)
	_travel = panel
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := UITheme.label(str(loc.get("name", lid)), "title", 26, Palette.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var x := Button.new()
	x.text = "✕"
	x.flat = true
	x.pressed.connect(_close_travel)
	head.add_child(x)
	var why := TravelRules.why_not(c, s, lid)
	var lines: Array = []
	if lid == s.party_at:
		lines.append(["Здесь стоит лагерь.", Palette.SILVER])
	elif why != "":
		lines.append([why, Palette.REQ_MISS])
	else:
		var path := TravelRules.route(c, s, s.party_at, lid)
		var names: Array = path.map(func(p: String) -> String: return str(c.locations.get(p, c.shops.get(p, {})).get("name", p)))
		lines.append(["Путь: %s" % " → ".join(names), Palette.TEXT])
		var cost := TravelRules.march_cost(c, s, path.size())
		lines.append(["%d %s · %s" % [path.size(), UITheme.plural(path.size(), ["переход", "перехода", "переходов"]),
			("без усталости" if cost == 0 else "марш-бросок: психика %d всем" % cost)], Palette.STAT_UP if cost == 0 else Palette.REQ_MISS])
	var cp := DayRules.camp_at(c, lid)
	var cl := CampWindow._camp_line(cp).strip_edges().trim_suffix(".")
	lines.append(["Лагерь здесь: ночью психика +%d · коек %d%s" % [int(cp.get("rest", 20)), int(cp.get("beds", 0)), (" · " + cl.to_lower()) if cl != "" else ""], Palette.SILVER])
	lines.append(["Высота: %s" % {"low": "низина — тонет в каждый прилив", "mid": "средняя — может уйти под воду", "high": "высота — вода не доходит"}.get(TideRules.height(c, lid), "—"), Palette.TEXT_DIM])
	if TideRules.threatened(s, lid):
		lines.append(["≈ Сюда придёт вода", Palette.REQ_MISS])
	for ln: Array in lines:
		var l := UITheme.label(str(ln[0]), "sans", 17, ln[1])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 350
		v.add_child(l)
	if lid != s.party_at:
		var go := Button.new()
		go.text = "ИДТИ ›"
		go.disabled = why != ""
		go.custom_minimum_size = Vector2(0, 48)
		go.add_theme_font_override("font", UITheme.font("caps"))
		go.add_theme_font_size_override("font_size", 21)
		go.pressed.connect(func() -> void:
			_close_travel()
			var err := GameState.move_party(lid)
			if err != "":
				_show_toast(err)
			else:
				AudioManager.play("place"))
		v.add_child(go)
	# у места, но в пределах окна
	var at := _place_point(lid) + (_sleeper.pan if _sleeper != null else Vector2.ZERO) + Vector2(40, -60)
	var scr := _screen()
	panel.reset_size()
	at.x = clampf(at.x, 16.0, scr.x - 400.0)
	at.y = clampf(at.y, 120.0, scr.y - TRAY_H - panel.get_combined_minimum_size().y - 10.0)
	panel.position = at
	GameState.tutorial("travel")


## Дело лагеря: выбрать, кто из свободных героев за него возьмётся.
func _pick_task_hero(task: String) -> void:
	if is_instance_valid(_picker):
		_picker.queue_free()
	var c := ContentDB.data
	var s := GameState.state
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.04, 0.045, 0.06, 0.96), Palette.LINE, 1, 10, 16))
	add_child(panel)
	_picker = panel
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var def := DayPlanner.task_def(c, task)
	v.add_child(UITheme.label(str(def.get("name", task)), "title", 26, Palette.TEXT))
	var t := UITheme.label(str(def.get("text", "")), "sans", 16, Palette.SILVER)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 380
	v.add_child(t)
	for cid: String in MissionFlow.heroes(c, s):
		var why := DayPlanner.can_task(c, s, task, cid)
		var b := Button.new()
		var loss := DayRules.fatigue_cost(c, s, cid)
		b.text = "%s · психика %d%s" % [c.card_name(cid), PsycheRules.psyche(s, cid), (" · усталость %d" % loss) if loss < 0 else ""]
		if why != "":
			b.text += " · " + why
		b.disabled = why != ""
		b.custom_minimum_size = Vector2(380, 40)
		b.pressed.connect(func() -> void:
			panel.queue_free()
			var err := GameState.do_task(task, cid)
			if err != "":
				_show_toast(err))
		v.add_child(b)
	var cancel := Button.new()
	cancel.text = "Отмена"
	cancel.pressed.connect(panel.queue_free)
	v.add_child(cancel)
	panel.reset_size()
	var scr := _screen()
	panel.position = Vector2(scr.x - 470, scr.y - TRAY_H - panel.get_combined_minimum_size().y - 20)
	GameState.tutorial("tasks")


func _update_day() -> void:
	var c := ContentDB.data
	var s := GameState.state
	var ph := DayRules.phase(c, s)
	var nx := DayRules.tomorrow(c, s)
	var more := int(ph["left"]) - 1
	var tail := ("ещё %d %s" % [more, UITheme.plural(more, ["день", "дня", "дней"])]) if more > 0 else "последний день"
	_day_label.text = "День %d · %s — %s · завтра: %s" % [s.day, ph["name"], tail, nx["name"]]
	_day_label.tooltip_text = str(ph["hint"])
	_day_label.mouse_filter = Control.MOUSE_FILTER_STOP
	HintTargets.put("day_label", [_day_label])
	var cp := DayRules.camp(c, s)
	var where := str(c.locations.get(s.party_at, {}).get("name", "—"))
	var warn := ""
	if TideRules.threatened(s, s.party_at):
		warn = " · ≈ СЮДА ПРИДЁТ ВОДА"
	var line := CampWindow._camp_line(cp).strip_edges().trim_suffix(".")
	_camp_label.text = "Лагерь: %s · ночью психика +%d · коек %d%s%s" % [where, int(cp.get("rest", 20)), int(cp.get("beds", 0)),
		(" · " + line.to_lower()) if line != "" else "", warn]
	_camp_label.add_theme_color_override("font_color", Palette.REQ_MISS if warn != "" else Palette.SILVER)
	_end_btn.disabled = DayRules.can_end(s) != ""
	# дела на сегодня (DayPlanner, docs/17 §4)
	var map_day := DayRules.restricted(c, s)
	_plan_label.visible = map_day
	_tasks_row.visible = map_day
	if not map_day:
		return
	var opt := DayPlanner.options(c, s)
	var today: Array = opt["today"]
	var left := DayPlanner.tasks_left(c, s)
	var steps := TravelRules.steps_left(c, s)
	var parts: Array = ["Сегодня: миссий рядом %d" % today.size(), "переходов без усталости %d из %d" % [steps, TravelRules.free_steps(c)]]
	if not (opt["cut"] as Array).is_empty():
		parts.append("за водой %d" % (opt["cut"] as Array).size())
	var free := MissionFlow.free_heroes(c, s)
	if free.is_empty() and s.squads.is_empty():
		_plan_label.text = "Все герои выдохлись — пора в лагерь: «Закончить день»"
	elif today.is_empty() and left.is_empty():
		_plan_label.text = "Рядом больше нечего делать — идите дальше или «Закончить день»"
	else:
		_plan_label.text = " · ".join(parts)
	var done: Array = s.flags.get("tasks_done", [])
	for tb in _tasks_row.get_children():
		var t := str(tb.name)
		(tb as Button).disabled = not left.has(t)
		(tb as Button).text = str(DayPlanner.task_def(c, t).get("name", t)) + (" ✓" if done.has(t) else "")


func _on_end_day() -> void:
	if _night != null or _window != null:
		return
	var ev := GameState.end_day()
	if ev.is_empty():
		return
	AudioManager.play("bell", -6.0, 0.5)
	_show_night(ev)


## Окно ночи: что случилось в лагере, какая фаза пришла.
func _show_night(ev: Array) -> void:
	_night = Control.new()
	_night.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_night)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.012, 0.02, 0.0)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_night.add_child(shade)
	create_tween().tween_property(shade, "color:a", 0.9, 0.6 if not Vfx.reduced() else 0.0)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.04, 0.045, 0.06, 0.97), Palette.LINE, 1, 12, 26))
	panel.position = Vector2(560, 170)
	panel.custom_minimum_size = Vector2(800, 0)
	_night.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var ph := DayRules.phase(ContentDB.data, GameState.state)
	v.add_child(UITheme.label("Ночь прошла · утро дня %d" % GameState.state.day, "title", 32, Palette.TEXT))
	v.add_child(UITheme.label("%s · %s" % [ph["name"], ph["hint"]], "serif_italic", 19, Palette.SILVER))
	for e: Dictionary in ev:
		var t := str(e.get("text", ""))
		if t == "" or str(e.get("kind", "")) == "psyche":
			continue
		var col := Palette.TEXT
		match str(e.get("kind", "")):
			"night_ordeal":
				col = Palette.STAT_UP if bool(e.get("ok", false)) else Palette.REQ_MISS
			"edge", "death", "lost", "expired":
				col = Palette.REQ_MISS
			"phase", "tide_flood", "tide_warn", "tide_ebb", "emerge":
				col = Palette.SILVER
			"planner", "mission":
				col = Palette.GOLD
		var l := UITheme.label("• " + t, "sans", 18, col)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 740
		v.add_child(l)
	var b := Button.new()
	b.text = "УТРО ›"
	b.custom_minimum_size = Vector2(240, 56)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.add_theme_font_override("font", UITheme.font("caps"))
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(func() -> void:
		_night.queue_free()
		_night = null
		_refresh()
		# обучение: смена фазы недели, местные встречи
		if ev.any(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "phase"):
			GameState.tutorial("phase")
		if ev.any(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "planner"):
			GameState.tutorial("planner"))
	v.add_child(b)


func _build_toast() -> void:
	_toast = UITheme.label("", "sans_bold", 20, Palette.TEXT)
	# справа под строкой меню — не перекрывает окна миссий
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toast.anchor_left = 1.0
	_toast.anchor_right = 1.0
	_toast.offset_left = -960
	_toast.offset_right = -36
	_toast.offset_top = 62
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_toast.modulate.a = 0.0
	_toast.z_index = 50
	add_child(_toast)
	# прилив: строка с отсчётом под надписями главы
	_tide_banner = UITheme.label("", "sans_bold", 21, Color(0.72, 0.88, 1.0))
	_tide_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tide_banner.anchor_right = 1.0
	_tide_banner.offset_left = 0
	_tide_banner.offset_top = 104
	_tide_banner.offset_bottom = 138
	_tide_banner.add_theme_constant_override("outline_size", 8)
	_tide_banner.add_theme_color_override("font_outline_color", Color(0, 0.02, 0.05, 0.95))
	_tide_banner.mouse_filter = Control.MOUSE_FILTER_STOP
	_tide_banner.tooltip_text = "Прилив Забытого Берега считает выполненные миссии, не секунды. Низины уходят под воду всегда, средние места — как повезёт, высоты — никогда.
Отряд, которого застанет вода, бежит (проверка Хитрости): провал — один герой падает на грань смерти.
Незавершённые побочные и случайные миссии в затопленных местах смывает. После отлива лабиринт другой: новые проходы и новые встречи."
	_tide_banner.visible = false
	add_child(_tide_banner)
	add_child(HintPopup.new())
	HintTargets.resolver = _hint_target


## Цели подсказок, которые вычисляются на лету (HintTargets.resolver): метки миссий, карты героев, луна.
func _hint_target(name: String) -> Rect2:
	var c := ContentDB.data
	var s := GameState.state
	if s == null:
		return Rect2()
	# цель на карте под открытым окном не подсвечиваем — подсказка подождёт у края
	for n in get_children():
		if (n is MissionWindow or n is ShopWindow or n is CampWindow or n is JournalWindow or n is CardInspector or n is CombatScreen) 				and (n as CanvasItem).visible:
			return Rect2()
	if name == "tide_banner":
		return _tide_banner.get_global_rect() if _tide_banner.visible else Rect2()
	if name == "sky_moon":
		if _backdrop == null:
			return Rect2()
		var br := _backdrop.get_global_rect()
		return Rect2(br.position + br.size * MapBackdrop.MOON_AT - Vector2(46, 46), Vector2(92, 92))
	if name.begins_with("marker_"):
		for mid: String in _markers:
			var m: Dictionary = c.missions.get(mid, {})
			var ok := false
			match name:
				"marker_any":
					ok = true
				"marker_squad":
					ok = s.squads.any(func(q: Dictionary) -> bool: return q["mission"] == mid)
				"marker_expires":
					ok = m.has("expires") and str(m.get("type", "")) != "onslaught"
				"marker_exclusive":
					ok = not Array(m.get("exclusive", [])).is_empty()
				"marker_boss":
					ok = not Dictionary(m.get("boss", {})).is_empty()
				"marker_onslaught":
					ok = str(m.get("type", "")) == "onslaught"
				"marker_far":
					ok = TravelRules.distance(c, s, str(m.get("location", ""))) > 0 and str(m.get("type", "")) != "onslaught"
			var mk: Control = _markers[mid]
			if ok and is_instance_valid(mk) and mk.is_visible_in_tree():
				return mk.get_global_rect()
		return Rect2()
	if name.begins_with("hero_"):
		for cv in _heroes_row.get_children():
			if not (cv is CardView):
				continue
			var cid := str((cv as CardView).card_id)
			if not s.characters.has(cid):
				continue
			var ch := s.character(cid)
			var ok2 := false
			match name:
				"hero_edge":
					ok2 = bool(ch.get("edge", false))
				"hero_rest":
					ok2 = float(s.rest_until.get(cid, 0.0)) > s.clock
				"hero_panic":
					ok2 = PsycheRules.psyche(s, cid) <= 60
				"hero_growth":
					ok2 = Dictionary(ch.get("tag_xp", {})).keys().any(func(t: String) -> bool: return GrowthRules.xp(s, cid, t) >= GrowthRules.VETERAN)
				"hero_trust":
					ok2 = s.trust.keys().any(func(k: String) -> bool: return k.split("|").has(cid))
			if ok2:
				return (cv as Control).get_global_rect()
	return Rect2()


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
	var ph := DayRules.phase(c, s)
	_top_labels["squads"].text = "День %d · неделя %d · %s" % [s.day, int(ph["week"]), ph["name"]]
	_update_day()
	if _tray_cards() != _shown_collection:
		_rebuild_cards()
	_update_badges()
	if _map_missions() != _shown_missions or _tide_key() != _shown_tide:
		_rebuild_markers()
	_update_pins()
	_update_tide()


## Прилив: вода под местами, строка с отсчётом (TideRules).
func _update_tide() -> void:
	var s := GameState.state
	var c := ContentDB.data
	var ph := TideRules.phase(s)
	if _sleeper != null:
		_sleeper.sync(c, s, Atmosphere.sky(c, s))
	var spots: Array = TideRules.places(s).map(func(l: String) -> Vector2: return _place_point(l))
	var left := TideRules.left(s)
	var urgency := 0.0
	if ph == "warn":
		urgency = 1.0 if left <= 1 else 0.45
	var titles: Array = TideRules.places(s).map(func(l: String) -> String: return str(c.locations.get(l, {}).get("name", l)))
	# у места, где ещё лежит карта миссии, подпись уже есть — вода подписывает только опустевшие
	var shown := {}
	for mid: String in _markers:
		shown[str(c.missions.get(mid, {}).get("location", ""))] = true
	var captions: Array = []
	for i in titles.size():
		captions.append("" if shown.has(TideRules.places(s)[i]) else titles[i])
	# на карте-плане вода и кольца рисуются самой картой
	_tide.visible = _sleeper == null
	_tide.show_tide(ph, spots, urgency, captions)
	var names := ", ".join(titles)
	match ph:
		"warn":
			_tide_banner.text = "≈ Прилив через %s — под воду уйдут: %s" % [TideRules.left_text(s), names]
		"flood":
			_tide_banner.text = "≈ Под водой: %s · отлив через %s" % [names, TideRules.left_text(s)]
		_:
			_tide_banner.text = ""
	_tide_banner.visible = ph != ""


func _tide_key() -> String:
	var t: Dictionary = GameState.state.tide
	return "%s|%s|%s|%s|%s|%d" % [TideRules.phase(GameState.state), str(t.get("slot", {})), str(t.get("shift", {})), str(t.get("emerged", {})),
		GameState.state.party_at, GameState.state.day]


## Небо над картой: день и ночь по часам, кровавая луна и затмение — по сюжету (Atmosphere).
## Смена неба красит и живую карту: туман, искры, облака и стаи.
func _update_sky() -> void:
	var next := Atmosphere.sky(ContentDB.data, GameState.state)
	if next == _sky:
		return
	var first := _sky == ""
	_sky = next
	if _sleeper != null:
		_sleeper.sync(ContentDB.data, GameState.state, next)
	elif not _backdrop.has_sky_art():
		# нарисованный фон (Академия): день и ночь — временем суток
		_backdrop.set_tod(float(Atmosphere.TOD[next]), not first)
		_life.set_tod(float(Atmosphere.TOD[next]), not first)
		return
	if _backdrop != null:
		_backdrop.set_sky(next, not first)
		_life.set_tod(float(Atmosphere.TOD[next]), not first)
	var tint := {"night": Color(1, 1, 1), "day": Color(1.1, 1.1, 1.15), "eclipse": Color(0.55, 0.58, 0.7),
		"blood_moon": Color(1.25, 0.45, 0.4), "storm": Color(0.6, 0.65, 0.8)}
	var fog_tint := {"night": Color(1, 1, 1), "day": Color(1.2, 1.2, 1.25), "eclipse": Color(0.5, 0.52, 0.6),
		"blood_moon": Color(1.1, 0.6, 0.6), "storm": Color(0.85, 0.9, 1.05)}
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


## Карты нижнего ряда: живые герои и усиления вне кармашков (усиление в кармашке видно только в планшете героя).
func _tray_cards() -> Array:
	var s := GameState.state
	var c := ContentDB.data
	return s.collection.filter(func(card: String) -> bool:
		var kind := c.card_kind(card)
		if kind == "enhancement":
			return MissionFlow.pocket_owner(s, card) == ""
		return kind == "character" and s.is_alive(card))


func _rebuild_cards() -> void:
	var s := GameState.state
	var c := ContentDB.data
	_shown_collection = _tray_cards()
	for ch in _heroes_row.get_children():
		ch.queue_free()
	_hero_cards.clear()
	_enh_cards.clear()
	var enh: Array = []
	for card: String in _shown_collection:
		var kind := c.card_kind(card)
		if kind == "character":
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
		var b := why   # свободного героя не подписываем — метка только у занятых («на миссии»)
		if cv.badge != b:
			cv.badge = b
			cv.draggable = why == ""
			cv.queue_redraw()
	for card: String in _enh_cards:
		var ev: CardView = _enh_cards[card]
		if not is_instance_valid(ev):
			continue
		var eb := ""   # в ряду только усиления вне кармашков — без подписи
		if ev.badge != eb:
			ev.badge = eb
			ev.draggable = true
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
	_shown_tide = _tide_key()
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
		var foot := _place_point(lid)
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
			if _sleeper != null:
				sz *= 0.78   # на карте-плане метки чуть мельче, чтобы не закрывать места; при наведении карта растёт
			sizes.append(sz)
			total_w += sz.x + 14.0
		var x := foot.x - (total_w - 14.0) / 2.0
		for i in here.size():
			var mid: String = here[i]
			var sz: Vector2 = sizes[i]
			var mk := MissionMarker.make(mid, sz)
			mk.zoom_on_hover = _sleeper != null
			mk.position = Vector2(x, foot.y - sz.y)
			mk.pressed.connect(_open_mission)
			mk.hero_dropped.connect(_on_hero_dropped)
			_pins_layer.add_child(mk)
			_markers[mid] = mk
			x += sz.x + 14.0
		if _sleeper != null:
			continue   # подписи мест рисует сама карта
		var name := UITheme.label(str(loc.get("name", lid)), "title", 20, Palette.SILVER)
		name.add_theme_constant_override("outline_size", 6)
		name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.size = Vector2(maxf(total_w, 260.0), 28)
		name.position = Vector2(foot.x - name.size.x / 2.0, foot.y + 6.0)
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pins_layer.add_child(name)
	_add_move_buttons()


## Кнопки «Перейти» у соседних мест (карта-план): переход без миссии стоит психики всем.
func _add_move_buttons() -> void:
	var c := ContentDB.data
	var s := GameState.state
	if _sleeper == null or not DayRules.restricted(c, s):
		return
	for lid: String in MapRules.neighbors(c, s, s.party_at):
		if not TravelRules.can_stop(c, s, lid) or not MapRules.revealed(c, s, lid):
			continue
		var b := Button.new()
		b.text = "⇢ идти"
		b.tooltip_text = "Перейти сюда: лагерь переедет. Щелчок по любому месту на карте — тоже переход."
		b.add_theme_font_size_override("font_size", 15)
		b.custom_minimum_size = Vector2(96, 30)
		b.position = _place_point(lid) + Vector2(-48, 32)
		b.pressed.connect(_show_travel.bind(lid))
		_pins_layer.add_child(b)


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
			arrived = true   # пути нет: отряд сразу на месте
			mk.fork_wait = sq["phase"] == "fork"
		mk.set_state(progress, remaining, arrived)
		# устаревающая миссия: срок — меткой на карте
		var left := MissionFlow.expires_in(ContentDB.data, s, mid)
		var badge := ""
		if left >= 0 and not arrived:
			badge = "⌛ до ночи" if left <= 1 else "⌛ %d %s" % [left, UITheme.plural(left, ["день", "дня", "дней"])]
		if badge != "" and str(ContentDB.data.missions.get(mid, {}).get("type", "")) == "onslaught":
			badge = "НАТИСК · " + badge
		# прилив: место под водой — ждать отлива; вода идёт — успеет ли отряд
		var under := TideRules.mission_flooded(ContentDB.data, s, mid)
		var far := not arrived and not DayRules.mission_reachable(ContentDB.data, s, mid)
		var mloc := str(ContentDB.data.missions.get(mid, {}).get("location", ""))
		var steps := TravelRules.distance(ContentDB.data, s, mloc) if DayRules.restricted(ContentDB.data, s) and str(ContentDB.data.missions.get(mid, {}).get("type", "")) != "onslaught" else 0
		if under:
			badge = "ПОД ВОДОЙ"
		elif far:
			badge = "ЗА ВОДОЙ"
		elif steps > 0 and not arrived and badge == "":
			badge = "%d %s%s" % [steps, UITheme.plural(steps, ["ПЕРЕХОД", "ПЕРЕХОДА", "ПЕРЕХОДОВ"]),
				" · МАРШ" if TravelRules.march_steps(ContentDB.data, s, steps) > 0 else ""]
		elif not arrived and TideRules.threatened(s, str(ContentDB.data.missions.get(mid, {}).get("location", ""))):
			badge = "≈ ВОДА ЗАВТРА"
		var tint := Color(0.5, 0.64, 0.86, 0.8) if under else (Color(0.62, 0.62, 0.66, 0.85) if far else Color(1, 1, 1, 1))
		if mk.modulate != tint:
			mk.modulate = tint
		if mk.card.badge != badge:
			mk.card.badge = badge
			mk.card.queue_redraw()
	for sid: String in _shops:
		var icon: ShopIcon = _shops[sid]
		icon.set_state(ShopRules.has_news(ContentDB.data, s, sid), ShopRules.days_to_refresh(ContentDB.data, s, sid))


func _on_events(events: Array) -> void:
	for e: Dictionary in events:
		match str(e.get("kind", "")):
			"arrived":
				AudioManager.play("bell", -6.0, 1.2)
				_show_toast("%s — щёлкните по карте миссии" % e["text"])
			"rested", "expired", "move", "task", "planner":
				_show_toast(str(e["text"]))
			"onslaught":
				AudioManager.play("bell", -2.0, 0.7)
				_show_toast("%s — отбить, пока не истёк срок" % e["text"])
				GameState.tutorial("onslaught")
			"mission":
				AudioManager.play("open", -8.0)
				_show_toast(str(e["text"]))
			"tide_warn", "tide":
				AudioManager.play("bell", -4.0, 0.5)
				_show_toast(str(e["text"]))
				GameState.tutorial("tide")
			"tide_flood":
				AudioManager.play("bell", -2.0, 0.4)
				_show_toast(str(e["text"]))
			"tide_ebb":
				AudioManager.play("bell", -8.0, 0.8)
				_show_toast(str(e["text"]))
			"tide_caught":
				# вода застала отряд: окно его прибытия больше не нужно
				if is_instance_valid(_window) and _window.squad_id == int(e.get("squad", -1)) and _window.mode in ["arrival", "fork"]:
					_window.close()
				var hurt: Array = Array(e.get("entries", [])).filter(func(x: Dictionary) -> bool: return str(x.get("kind", "")) in ["edge", "death"]) 					.map(func(x: Dictionary) -> String: return str(x.get("text", "")))
				AudioManager.play("bell", -2.0, 0.45)
				_show_toast(str(e["text"]) + ((". " + hurt[0]) if not hurt.is_empty() else ""))
	_refresh()


# --- окна -----------------------------------------------------------------------

## Щелчок по карте миссии: нет отряда — брифинг; отряд прибыл — выбор действия; в пути — ждём.
func _open_mission(mid: String) -> void:
	for sq: Dictionary in GameState.state.squads:
		if sq["mission"] != mid:
			continue
		_open_window()
		_window.show_arrival(int(sq["id"]))
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
	if not DayRules.shop_near(ContentDB.data, GameState.state, sid):
		_show_toast("%s далеко: подойдите к соседнему с ним месту" % ContentDB.data.shops[sid].get("name", "Лавка"))
		return
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


## F5 (только в отладочной сборке) — точка сохранения разработчика; загрузка — в меню «Разработчик».
func _unhandled_key_input(event: InputEvent) -> void:
	if DevPanel.enabled() and event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F5:
		DevPanel.save_point(GameState.state)
		_show_toast("Точка сохранения разработчика записана (меню → Разработчик)")
		get_viewport().set_input_as_handled()


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
			# экран темнеет → сюжетное окно новой главы → карта проявляется
			b.disabled = true
			var black := ColorRect.new()
			black.color = Color(0, 0, 0, 0)
			black.set_anchors_preset(Control.PRESET_FULL_RECT)
			_end.add_child(black)
			var tw := create_tween()
			tw.tween_property(black, "color:a", 1.0, 0.8)
			tw.tween_callback(func() -> void:
				GameState.next_chapter()
				get_tree().reload_current_scene()))
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
