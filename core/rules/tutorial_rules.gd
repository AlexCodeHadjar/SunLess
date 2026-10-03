class_name TutorialRules
extends RefCounted
## Обучение (docs/16 §1, Ф12): Первый Кошмар учит базовому циклу, Академия — новым механикам.
## 1) Механики открываются по главам (UNLOCK): в Кошмаре их нет вовсе, с Академии — работают.
## 2) Подсказки (data/tutorial.json {id, event, title, text}) — при первом событии, один раз за прохождение;
##    показанные — в state.flags["tut_seen"]. Выключаются в настройках («Подсказки обучения»).

const CHAPTERS := ["nightmare", "academy", "shore", "tree", "dark_city", "city"]
## механика -> глава, с которой она работает
const UNLOCK := {"trust": "academy", "bonds": "academy", "panic": "academy", "growth": "academy", "camp": "academy"}


## Работает ли механика в текущей главе (неизвестная глава — всё открыто).
static func enabled(state: RunState, mechanic: String) -> bool:
	var need := CHAPTERS.find(str(UNLOCK.get(mechanic, "")))
	var cur := CHAPTERS.find(state.chapter)
	return need < 0 or cur < 0 or cur >= need


static func seen(state: RunState, hint_id: String) -> bool:
	return Array(state.flags.get("tut_seen", [])).has(hint_id)


## Подсказка к событию (ещё не показанная) или {}. Помечает её показанной.
static func take(content: Content, state: RunState, event: String) -> Dictionary:
	for hid: String in MissionFlow._sorted(content.tutorial):
		var h: Dictionary = content.tutorial[hid]
		if str(h.get("event", "")) != event or seen(state, hid):
			continue
		var need := str(h.get("chapter", ""))
		if need != "" and CHAPTERS.find(state.chapter) < CHAPTERS.find(need):
			continue
		var list: Array = state.flags.get("tut_seen", [])
		list.append(hid)
		state.flags["tut_seen"] = list
		return h
	return {}


## Общие подсказки (без главы), которые игрок точно видел ещё в Кошмаре: базовый цикл миссии.
const BASE_EVENTS := ["map", "brief", "launch", "arrival", "report", "edge", "shop", "fork", "cost", "expires", "exclusive", "journal"]


## Начало главы из режима разработчика: бот проходит игру без экрана и подсказок не видит, поэтому в поздней главе
## всплывало обучение с самого начала. Здесь отмечается показанным всё, что игрок увидел бы раньше: подсказки прошлых
## глав, общие подсказки базового цикла (с Академии) и все общие (с Берега, после обеих обучающих глав).
## Подсказки текущей главы остаются. Возвращает, сколько отмечено.
static func skip_before(content: Content, state: RunState) -> int:
	var cur := CHAPTERS.find(state.chapter)
	if cur <= 0:
		return 0
	var list: Array = state.flags.get("tut_seen", [])
	var n := 0
	for hid: String in content.tutorial:
		var h: Dictionary = content.tutorial[hid]
		var ch := str(h.get("chapter", ""))
		var old := false
		if ch == "":
			old = cur >= CHAPTERS.find("shore") or BASE_EVENTS.has(str(h.get("event", "")))
		else:
			old = CHAPTERS.find(ch) >= 0 and CHAPTERS.find(ch) < cur
		if old and not list.has(hid):
			list.append(hid)
			n += 1
	state.flags["tut_seen"] = list
	return n


## События, которые можно понять по состоянию (проверяются при обновлении карты).
## Глава 4 (TerrainRules, ZoneRules, MoverRules): подсказка — когда механика впервые видна игроку на карте.
static func _terrain_events(content: Content, state: RunState) -> Array:
	var out: Array = []
	var cfg := MapRules.config(content, state.chapter)
	if cfg.is_empty():
		return out
	var kn := MapRules.known(content, state)
	for mid: String in MoverRules.movers(state):
		if MoverRules.active(state, mid):
			match str(MoverRules.cfg(content, state).get(mid, {}).get("target", "")):
				"camp":
					out.append("mover")
				"noise":
					out.append("hunters")
	var zc := ZoneRules.cfg(content, state)
	for zid: String in zc:
		var z: Dictionary = zc[zid]
		if ZoneRules.radius(content, state, zid) < 0 or not kn.has(str(z.get("center", ""))):
			continue
		if bool(z.get("charm", false)):
			out.append("zone_charm")
		elif int(z.get("pass_psyche", 0)) != 0:
			out.append("zone_wrath")
		elif int(z.get("grow", 0)) > 0:
			out.append("territory")
	# следы событий на карте и места событий Берега (MapEventRules, комплект событий)
	if not MapEventRules.decals(content, state).is_empty():
		out.append("traces")
	if state.chapter == "shore" and MapRules.emerged(state).keys().any(func(l: String) -> bool:
			return str(content.locations.get(l, {}).get("socket_group", "")) != ""):
		out.append("event_place")
	var storm := str(cfg.get("path_sets", {}).get("storm_phase", ""))
	if storm != "" and str(DayRules.phase(content, state).get("id", "")) == storm:
		out.append("ash_storm")
	for lid: String in cfg.get("fragile", {}):
		if kn.has(lid):
			out.append("fragile")
	for pr: Array in cfg.get("water_paths", []):
		if kn.has(str(pr[0])) or kn.has(str(pr[1])):
			out.append("water")
			break
	for lid: String in kn:
		if int(DayRules.camp_at(content, lid).get("tribute", 0)) > 0:
			out.append("tribute")
			break
	if not cfg.get("rubble", {}).is_empty() and (not Dictionary(state.flags.get("rubble", {})).is_empty() \
			or str(DayRules.phase(content, state).get("id", "")) == str(cfg.get("rubble_phase", "storm"))):
		out.append("rubble")
	return out


## Фигура (docs/18): подсказки о фигуре, событиях рядом и вдали, лагере у фигуры, ожидании.
static func _figure_events(content: Content, state: RunState) -> Array:
	var out: Array = ["figure"]
	var opt := DayPlanner.options(content, state)
	for mid: String in MissionFlow.open_missions(state):
		if MissionFlow.chapter_of(content, mid) == state.chapter and FigureRules.reach(content, state, mid) != 0:
			out.append("figure_far")
			break
	if (opt["today"] as Array).is_empty():
		out.append("figure_wait")
	if state.day >= 2:
		out.append("figure_camp")
	if (opt["today"] as Array).size() < DayPlanner.min_options(content) and not DayPlanner.tasks_left(content, state).is_empty():
		out.append("tasks")
	return out


static func state_events(content: Content, state: RunState) -> Array:
	var out: Array = []
	if state.chapter == "academy":
		out.append("academy_start")
	for cid: String in MissionFlow.heroes(content, state):
		var ch := state.character(cid)
		if bool(ch.get("edge", false)):
			out.append("edge")
		if PsycheRules.psyche(state, cid) <= 60:
			out.append("panic")
		for tag: String in ch.get("tag_xp", {}):
			if GrowthRules.xp(state, cid, tag) >= GrowthRules.VETERAN:
				out.append("growth")
	if not state.trust.is_empty() and enabled(state, "trust"):
		out.append("trust")
	if not JournalRules.bestiary(state).is_empty():
		out.append("journal")
	for mid: String in MissionFlow.open_missions(state):
		var m: Dictionary = content.missions.get(mid, {})
		if m.has("expires") and str(m.get("type", "")) != "onslaught":
			out.append("expires")
		if not Array(m.get("exclusive", [])).is_empty():
			out.append("exclusive")
		if not Dictionary(m.get("boss", {})).is_empty():
			out.append("boss")
		if str(m.get("type", "")) == "onslaught":
			out.append("onslaught")
	# прорывы Академии / Врата (GateRules)
	if GateRules.active(content, state):
		for pid: String in GateRules.points(state):
			match GateRules.stage(state, pid):
				"signal":
					out.append(GateRules._ev(content, state, "signal"))
				"open":
					out.append(GateRules._ev(content, state, "open"))
				"scar":
					out.append("scar")
		if not GateRules.swarms(state).is_empty():
			out.append(GateRules._ev(content, state, "swarm"))
		for lid: String in GateRules.sites(state):
			if GateRules.site_state(state, lid) == "repair":
				out.append("repair")
		if GateRules.panic(state) >= 25:
			out.append("panic")
	out.append_array(_terrain_events(content, state))
	# дни, переходы, лагерь-стоянка (docs/16 §12, docs/17)
	out.append("day")
	if FigureRules.on(content, state):
		out.append_array(_figure_events(content, state))
	elif DayRules.restricted(content, state):
		out.append("travel")
		out.append("camp_place")
		if not MapRules.emerged(state).is_empty():
			out.append("emerge")
		var opt := DayPlanner.options(content, state)
		if not (opt["march"] as Array).is_empty() or not (opt["today"] as Array).is_empty() and (opt["today"] as Array).any(func(m: String) -> bool: return TravelRules.distance(content, state, str(content.missions.get(m, {}).get("location", ""))) > 0):
			out.append("far")
		if (opt["today"] as Array).size() < DayPlanner.min_options(content) and not DayPlanner.tasks_left(content, state).is_empty():
			out.append("tasks")
	for cid2: String in ([] if FigureRules.on(content, state) else MissionFlow.heroes(content, state)):
		if DayRules.sorties(state, cid2) >= 1:
			out.append("fatigue")
			break
	var sky := Atmosphere.sky(content, state)
	if sky in ["eclipse", "blood_moon"]:
		out.append("sky_" + sky)
	if enabled(state, "camp") and out.has("edge"):
		out.append("camp")
	return out
