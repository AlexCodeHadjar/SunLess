class_name MissionWindow
extends Control
## Окно миссии (docs/15): брифинг и сбор отряда → прибытие и выбор действия → отчёт.

signal closed
signal watch_combat(setup: Dictionary)

const PANEL := Rect2(250, 70, 1420, 900)
const WORD_COLORS := {
	"Безнадёжно": "#9A2A33", "Очень опасно": "#C0414C", "Опасно": "#D08A48", "Неясно": "#A8ADB4",
	"Хорошие шансы": "#6FB27A", "Уверенно": "#D6BC57", "Без риска": "#A8ADB4",
}
const RISK_COLORS := {"без потерь": "#6FB27A", "могут быть раны": "#D08A48", "кто-то может не вернуться": "#C0414C"}
const OUTCOME := {
	"ok": ["успех", "#6FB27A"], "partial": ["частично", "#D08A48"], "fail": ["провал", "#C0414C"],
}

var mode := ""              # brief | arrival | report
var mission_id := ""
var squad_id := 0
var report: Dictionary = {}
var picked: Array = []      # герои, выбранные в отряд на брифинге
var _body: VBoxContainer
var _title: Label
var _forecast_box: VBoxContainer
var _slots: HBoxContainer
var _go: Button
var _footer: HBoxContainer     # закреплённый низ окна: прогноз и главная кнопка


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and mode != "report":
			close())
	add_child(dim)
	var panel := PanelContainer.new()
	panel.position = PANEL.position
	panel.size = PANEL.size
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.055, 0.06, 0.08, 0.98), Palette.LINE, 1, 6, 0))
	add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)
	var head := HBoxContainer.new()
	_title = UITheme.label("", "title_bold", 40, Palette.TEXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var x := Button.new()
	x.text = "✕"
	x.flat = true
	x.add_theme_font_size_override("font_size", 26)
	x.pressed.connect(close)
	head.add_child(x)
	v.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 16)
	scroll.add_child(_body)
	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 24)
	v.add_child(_footer)
	# кармашек поменяли в планшете героя — прогноз пересчитывается
	EventBus.state_changed.connect(func() -> void:
		if mode == "brief" and is_instance_valid(_forecast_box):
			_refresh_squad())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and mode != "report":
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	if mode == "report":
		_discover_links()
	closed.emit()
	queue_free()


func _content() -> Content:
	return ContentDB.data


func _clear() -> void:
	for c in _body.get_children():
		c.queue_free()
	for c in _footer.get_children():
		c.queue_free()


# --- брифинг и отряд -------------------------------------------------------------------

## with_hero — герой, которого бросили прямо на карту миссии: он встаёт в отряд первым.
func show_brief(mid: String, with_hero: String = "") -> void:
	mode = "brief"
	mission_id = mid
	picked = []
	# обязательные герои миссии — первыми, затем брошенный на карту
	for need: String in _content().missions[mid].get("requires_heroes", []):
		if MissionFlow.busy_reason(_content(), GameState.state, need) == "":
			picked.append(need)
	if with_hero != "" and not picked.has(with_hero) and MissionFlow.busy_reason(_content(), GameState.state, with_hero) == "" 			and not MissionFlow.excluded(_content(), mid, with_hero) and picked.size() < int(_content().missions[mid].get("squad", {}).get("max", 1)):
		picked.append(with_hero)
	var c := _content()
	var m: Dictionary = c.missions[mid]
	_clear()
	_title.text = ("★ " if str(m.get("type", "")) == "story" else "") + str(m.get("title", mid))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 26)
	_body.add_child(top)
	top.add_child(_art(m, Vector2(250, 390)))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	top.add_child(col)
	col.add_child(_caption("Что происходит"))
	col.add_child(_para(str(m.get("briefing", "")), "serif", 20, Palette.TEXT))
	if not Array(m.get("rumors", [])).is_empty():
		col.add_child(_caption("Что говорят"))
		col.add_child(_rumors(m))
	col.add_child(_intel(m))
	col.add_child(_caption("Вероятные теги врага и места"))
	col.add_child(_tags_flow(m.get("known_tags", []), Array(m.get("hidden_tags", [])).size()))

	_body.add_child(_caption("Отряд · перетащите героя в место или щёлкните по нему"))
	_slots = HBoxContainer.new()
	_slots.add_theme_constant_override("separation", 14)
	_body.add_child(_slots)
	_forecast_box = VBoxContainer.new()
	_forecast_box.add_theme_constant_override("separation", 4)
	_forecast_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.add_child(_forecast_box)
	_go = Button.new()
	_go.text = "ВЫСТУПИТЬ ›"
	_go.custom_minimum_size = Vector2(340, 70)
	_go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_go.add_theme_font_override("font", UITheme.font("caps"))
	_go.add_theme_font_size_override("font_size", 30)
	_go.pressed.connect(_launch)
	_footer.add_child(_go)
	# по умолчанию — первые свободные герои (сколько нужно минимум)
	for cid: String in MissionFlow.free_heroes(c, GameState.state):
		if picked.size() >= int(m.get("squad", {}).get("min", 1)):
			break
		if not picked.has(cid) and not MissionFlow.excluded(c, mid, cid):
			picked.append(cid)
	_refresh_squad()


func _refresh_squad() -> void:
	var c := _content()
	var s := GameState.state
	var m: Dictionary = c.missions[mission_id]
	for ch in _slots.get_children():
		ch.queue_free()
	var mx := int(m.get("squad", {}).get("max", 1))
	for i in mx:
		if i < picked.size():
			var cid: String = picked[i]
			var cv := CardView.make(cid, Vector2(118, 202), false)
			cv.highlight = true
			cv.tooltip_text = "Щёлкните, чтобы убрать из отряда · правый щелчок — кармашек"
			cv.inspect_requested.connect(func(id: String) -> void: CardInspector.open_for(self, id))
			cv.clicked.connect(func(card: String) -> void:
				picked.erase(card)
				AudioManager.play("place", -6.0)
				_refresh_squad())
			_slots.add_child(cv)
		else:
			var dz := DropZone.new()
			dz.accepts = ["character"]
			dz.hint = "место в отряде" if i < int(m.get("squad", {}).get("min", 1)) else "ещё место\n(необязательно)"
			dz.custom_minimum_size = Vector2(118, 202)
			dz.dropped.connect(_add_hero)
			_slots.add_child(dz)
	var gap := Control.new()
	gap.custom_minimum_size.x = 30
	_slots.add_child(gap)
	var bench := VBoxContainer.new()
	bench.add_theme_constant_override("separation", 6)
	bench.add_child(UITheme.label("Свободные герои", "sans", 16, Palette.TEXT_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bench.add_child(row)
	for cid: String in MissionFlow.heroes(c, s):
		if picked.has(cid):
			continue
		var why := MissionFlow.busy_reason(c, s, cid)
		if why == "" and MissionFlow.excluded(c, mission_id, cid):
			why = "не может"
		var cv := CardView.make(cid, Vector2(96, 164), false)
		cv.dimmed = why != ""
		cv.badge = why
		cv.clicked.connect(_add_hero)
		cv.inspect_requested.connect(func(id: String) -> void: CardInspector.open_for(self, id))
		row.add_child(cv)
	if row.get_child_count() == 0:
		row.add_child(UITheme.label("Все герои в отряде", "serif_italic", 17, Palette.TEXT_DIM))
	_slots.add_child(bench)
	_refresh_forecast()


func _add_hero(cid: String) -> void:
	var c := _content()
	var m: Dictionary = c.missions[mission_id]
	var why := MissionFlow.busy_reason(c, GameState.state, cid)
	if why == "" and MissionFlow.excluded(c, mission_id, cid):
		why = "не может идти на эту миссию"
	if why != "":
		EventBus.toast.emit("%s: %s" % [c.card_name(cid), why])
		return
	if picked.has(cid):
		return
	if picked.size() >= int(m.get("squad", {}).get("max", 1)):
		EventBus.toast.emit("Мест в отряде больше нет")
		return
	picked.append(cid)
	AudioManager.play("place")
	_refresh_squad()


func _refresh_forecast() -> void:
	for ch in _forecast_box.get_children():
		ch.queue_free()
	var err := MissionFlow.can_launch(_content(), GameState.state, mission_id, picked)
	_go.disabled = err != ""
	_go.tooltip_text = err
	if picked.is_empty():
		_forecast_box.add_child(UITheme.label("Добавьте героя в отряд — появится прогноз.", "serif_italic", 19, Palette.TEXT_DIM))
		return
	var f := MissionForecast.mission_forecast(_content(), GameState.state, mission_id, picked)
	if str(f.get("word", "")) == "":
		_forecast_box.add_child(UITheme.label("Этому отряду здесь нечего делать.", "serif_italic", 19, Palette.STAT_DOWN))
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	_forecast_box.add_child(row)
	row.add_child(UITheme.label("Прогноз:", "caps", 26, Palette.SILVER))
	if bool(f["blurred"]):
		row.add_child(UITheme.label(str(f["word_low"]), "title_bold", 34, Color(WORD_COLORS.get(f["word_low"], "#A8ADB4"))))
		row.add_child(UITheme.label("—", "title", 30, Palette.TEXT_DIM))
	row.add_child(UITheme.label(str(f["word"]), "title_bold", 34, Color(WORD_COLORS.get(f["word"], "#A8ADB4"))))
	var risk := UITheme.label("· риск для отряда: %s" % f["risk_word"], "sans_bold", 19, Color(RISK_COLORS.get(f["risk_word"], "#A8ADB4")))
	risk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(risk)
	var best := MissionFlow.action(_content(), mission_id, str(f.get("action", "")))
	var note := "По лучшему из действий, что будут доступны этому отряду: «%s». На месте у каждого действия будет свой прогноз." % best.get("label", "")
	if bool(f["blurred"]):
		note += " Часть тегов скрыта (???) — прогноз размыт; разведчик с «Выслеживанием» или «Тенью» прояснит картину."
	var nl := UITheme.label(note, "sans", 16, Palette.TEXT_DIM)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.custom_minimum_size.x = 900
	_forecast_box.add_child(nl)
	var why := _reasons(f.get("links", []))
	if why != "":
		_forecast_box.add_child(_rich(why, 17))


func _launch() -> void:
	var err := GameState.launch_squad(mission_id, picked)
	if err != "":
		EventBus.toast.emit(err)
		return
	AudioManager.play("shuffle")
	EventBus.toast.emit("Отряд выступил: %s" % _content().missions[mission_id].get("title", ""))
	close()


# --- прибытие ---------------------------------------------------------------------------

func show_arrival(sid: int) -> void:
	mode = "arrival"
	squad_id = sid
	var c := _content()
	var s := GameState.state
	var sq := MissionFlow.squad(s, sid)
	if sq.is_empty():
		close()
		return
	mission_id = sq["mission"]
	var m: Dictionary = c.missions[mission_id]
	_clear()
	_title.text = "Отряд прибыл · " + str(m.get("title", ""))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 26)
	_body.add_child(top)
	top.add_child(_art(m, Vector2(210, 330)))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	top.add_child(col)
	col.add_child(_caption("Что увидели"))
	col.add_child(_para(str(m.get("arrival", "")), "serif", 20, Palette.TEXT))
	col.add_child(_caption("Теги раскрылись"))
	col.add_child(_tags_flow(Array(m.get("known_tags", [])) + Array(m.get("hidden_tags", [])), 0))
	var team := HBoxContainer.new()
	team.add_theme_constant_override("separation", 8)
	for cid: String in sq["heroes"]:
		team.add_child(CardView.make(cid, Vector2(84, 144), false))
	col.add_child(_caption("Отряд"))
	col.add_child(team)
	_body.add_child(_caption("Что делает отряд"))
	for entry: Dictionary in MissionFlow.actions_for(c, s, mission_id, sq["heroes"]):
		_body.add_child(_action_button(entry, sq))


func _action_button(entry: Dictionary, sq: Dictionary) -> Control:
	var a: Dictionary = entry["action"]
	var ok: bool = entry["available"]
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 84)
	b.disabled = not ok
	b.add_theme_stylebox_override("normal", UITheme.box(Color(0.08, 0.085, 0.11), Palette.LINE, 1, 6, 0))
	b.add_theme_stylebox_override("hover", UITheme.box(Color(0.11, 0.1, 0.09), Palette.GOLD, 1, 6, 0))
	b.add_theme_stylebox_override("disabled", UITheme.box(Color(0.06, 0.06, 0.075), Palette.LINE, 1, 6, 0))
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 20
	row.offset_right = -20
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	b.add_child(row)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var need: Array = a.get("requires_any", [])
	var head := ("✦ %s · " % " / ".join(need) if not need.is_empty() else "") + str(a.get("label", ""))
	col.add_child(_ignore(UITheme.label(head + ("  ★" if bool(a.get("story", false)) else ""), "title_bold", 26, Palette.TEXT if ok else Palette.TEXT_DIM)))
	col.add_child(_ignore(UITheme.label(str(a.get("text", "")) if ok else str(entry["reason"]), "sans", 16, Palette.TEXT_DIM)))
	if ok:
		var f := MissionForecast.action_forecast(_content(), GameState.state, mission_id, a, sq["heroes"], true)
		var w := UITheme.label(str(f["word"]), "title_bold", 26, Color(WORD_COLORS.get(f["word"], "#A8ADB4")))
		w.tooltip_text = "Риск для отряда: %s" % f["risk_word"]
		row.add_child(_ignore(w))
		b.pressed.connect(_choose.bind(str(a.get("id", ""))))
	return b


func _choose(action_id: String) -> void:
	var r := GameState.resolve_squad(squad_id, action_id)
	if r.has("error"):
		EventBus.toast.emit(str(r["error"]))
		return
	AudioManager.play("roll", -4.0)
	show_report(r)


# --- отчёт -----------------------------------------------------------------------------

func show_report(rep: Dictionary) -> void:
	mode = "report"
	report = rep
	var c := _content()
	var m: Dictionary = c.missions.get(rep["mission"], {})
	_clear()
	var head: Array = {"success": ["Миссия выполнена", Palette.STAT_UP], "partial": ["Выполнено с потерями", Color("#D08A48")],
		"failure": ["Миссия провалена", Palette.STAT_DOWN], "retreat": ["Отряд отступил", Palette.SILVER]}.get(rep["outcome"], ["Отчёт", Palette.TEXT])
	_title.text = "%s · %s" % [head[0], m.get("title", "")]
	_title.add_theme_color_override("font_color", head[1])
	AudioManager.play("success" if rep["outcome"] == "success" else "fail", -4.0)
	var stages := HBoxContainer.new()
	stages.add_theme_constant_override("separation", 14)
	_body.add_child(stages)
	var ci := 0
	for st: Dictionary in rep["stages"]:
		stages.add_child(_stage_card(st, rep, ci))
		if st.has("combat"):
			ci += 1
	_body.add_child(_caption("Итог"))
	var res := VBoxContainer.new()
	res.add_theme_constant_override("separation", 4)
	_body.add_child(res)
	for e: Dictionary in rep["entries"]:
		var kind := str(e.get("kind", "info"))
		var col: Color = {"card": Palette.STAT_UP, "trauma": Palette.TRAUMA_BRIGHT, "death": Palette.TRAUMA_BRIGHT,
			"mission": Color("#E3C98E"), "story": Color("#E3C98E"), "resource": Palette.COINS, "broken": Palette.STAT_DOWN}.get(kind, Palette.SILVER)
		res.add_child(UITheme.label("• " + str(e.get("text", "")), "sans", 18, col))
	var rest: Dictionary = rep.get("rest", {})
	if not rest.is_empty():
		var parts: Array = []
		for cid: String in rest:
			parts.append("%s — %d с" % [c.card_name(cid), int(rest[cid])])
		res.add_child(UITheme.label("Отдых: " + ", ".join(parts), "sans", 18, Palette.REST))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.add_child(gap)
	var ok := Button.new()
	ok.text = "ПРОДОЛЖИТЬ ›"
	ok.custom_minimum_size = Vector2(340, 64)
	ok.add_theme_font_override("font", UITheme.font("caps"))
	ok.add_theme_font_size_override("font_size", 28)
	ok.pressed.connect(close)
	_footer.add_child(ok)


func _stage_card(st: Dictionary, rep: Dictionary, combat_index: int) -> Control:
	var o: Array = OUTCOME.get(st["outcome"], ["", "#A8ADB4"])
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(430, 0)
	var box := UITheme.box(Color(0.075, 0.08, 0.1), Palette.LINE, 1, 6, 14)
	box.border_width_top = 4
	box.border_color = Color(o[1])
	p.add_theme_stylebox_override("panel", box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	v.add_child(UITheme.label(str(o[0]).to_upper(), "sans_bold", 15, Color(o[1])))
	v.add_child(UITheme.label(str(st.get("name", "")), "title_bold", 26, Palette.TEXT))
	if str(st.get("hero", "")) != "":
		v.add_child(UITheme.label("Действует: %s" % _content().card_name(str(st["hero"])), "sans", 16, Palette.TEXT_DIM))
	var t := _para(str(st.get("text", "")), "serif", 18, Palette.SILVER)
	t.custom_minimum_size.x = 400
	v.add_child(t)
	if st.has("combat") and combat_index < Array(rep.get("combats", [])).size():
		var cb: Dictionary = rep["combats"][combat_index]
		var w := Button.new()
		w.text = "Смотреть бой ›"
		w.pressed.connect(func() -> void: watch_combat.emit(cb["setup"]))
		v.add_child(w)
	return p


func _discover_links() -> void:
	for cb: Dictionary in report.get("combats", []):
		ProfileService.discover(cb.get("discovered", []))


# --- мелочи ------------------------------------------------------------------------------

func _squad_for(mid: String) -> Dictionary:
	for sq: Dictionary in GameState.state.squads:
		if sq["mission"] == mid:
			return sq
	return {}


func _art(m: Dictionary, sz: Vector2 = Vector2(300, 470)) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = sz
	var path := "res://art/cards/%s.webp" % str(m.get("from_event", ""))
	if ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.add_child(tr)
	else:
		var bd := MapBackdrop.new()
		bd.region = str(_content().locations.get(str(m.get("location", "")), {}).get("region", "mountain_pass"))
		bd.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.add_child(bd)
		bd.set_sky(Atmosphere.sky(_content(), GameState.state), false)
	return holder


func _intel(m: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 34)
	var enemies := {}
	for e: String in m.get("enemies", []):
		enemies[e] = int(enemies.get(e, 0)) + 1
	var names: Array = []
	for e: String in enemies:
		names.append(_content().card_name(e) + (" ×?" if int(enemies[e]) > 1 else ""))
	for pair: Array in [["Угроза", _dots(int(m.get("threat", 1)))], ["В пути", "~%d с" % int(m.get("duration", 8))],
			["Отряд", _squad_size(m)], ["Противники", ", ".join(names) if not names.is_empty() else "не видно"]]:
		var v := VBoxContainer.new()
		v.add_child(UITheme.label(str(pair[0]).to_upper(), "sans_bold", 13, Palette.TEXT_DIM))
		v.add_child(UITheme.label(str(pair[1]), "title_bold", 24, Color("#D08A48") if pair[0] == "Угроза" else Palette.TEXT))
		row.add_child(v)
	return row


func _tags_flow(tags: Array, hidden: int) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 6)
	for t: String in tags:
		var chip := TagChip.make(t, 18)
		chip.tooltip_text = str(_content().combat_tags.get(t, {}).get("text", ""))
		flow.add_child(chip)
	for i in hidden:
		flow.add_child(UITheme.label("???", "sans_bold", 18, Palette.TEXT_DIM))
	return flow


func _rumors(m: Dictionary) -> Control:
	var lines: Array = []
	for r: Dictionary in m.get("rumors", []):
		var tag := str(r.get("tag", ""))
		var col := "#E3C98E"
		if _content().combat_tags.has(tag):
			col = str(TagText.CATEGORY_COLORS.get(TagText.category(tag), "#E3C98E"))
		var text := str(r.get("text", ""))
		var i := text.find("[")
		var j := text.find("]")
		if i >= 0 and j > i:
			text = text.substr(0, i) + "[color=%s][u]%s[/u][/color]" % [col, text.substr(i + 1, j - i - 1)] + text.substr(j + 1)
		lines.append("— [i]%s[/i]" % text)
	return _rich("\n".join(lines), 19)


func _reasons(links: Array) -> String:
	var known: Array = []
	var unknown := 0
	var seen := {}
	for l: Dictionary in links:
		var id := str(l.get("id", ""))
		if id == "" or seen.has(id) or not (str(l.get("type", "")) in ["synergy", "conflict"]):
			continue
		seen[id] = true
		if ProfileService.is_known(id):
			var good := str(l.get("side", "")) == "hero"
			known.append("[color=%s]%s %s[/color]" % ["#6FB27A" if good else "#C0414C", "＋" if good else "−", l.get("name", "")])
		else:
			unknown += 1
	var out := "   ".join(known)
	if unknown > 0:
		out += ("   " if out != "" else "") + "[color=#9A9CA6]и ещё неизвестных связей: %d[/color]" % unknown
	return out


func _dots(n: int) -> String:
	return "●".repeat(clampi(n, 0, 5)) + "○".repeat(5 - clampi(n, 0, 5))


func _squad_size(m: Dictionary) -> String:
	var sq: Dictionary = m.get("squad", {})
	var a := int(sq.get("min", 1))
	var b := int(sq.get("max", 1))
	return str(a) if a == b else "%d–%d" % [a, b]


func _caption(text: String) -> Label:
	return UITheme.label(text.to_upper(), "sans_bold", 14, Palette.TEXT_DIM)


func _para(text: String, kind: String, fs: int, color: Color) -> Label:
	var l := UITheme.label(text, kind, fs, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 600
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _rich(bb: String, fs: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_override("normal_font", UITheme.font("serif"))
	r.add_theme_font_override("italics_font", UITheme.font("serif_italic"))
	r.add_theme_font_size_override("normal_font_size", fs)
	r.add_theme_font_size_override("italics_font_size", fs)
	r.add_theme_color_override("default_color", Palette.SILVER)
	r.text = bb
	return r


func _ignore(c: Control) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func _sorted(d: Dictionary) -> Array:
	var k: Array = d.keys()
	k.sort()
	return k
