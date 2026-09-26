class_name TutorialRules
extends RefCounted
## Обучение (docs/16 §1, Ф12): Первый Кошмар учит базовому циклу, Академия — новым механикам.
## 1) Механики открываются по главам (UNLOCK): в Кошмаре их нет вовсе, с Академии — работают.
## 2) Подсказки (data/tutorial.json {id, event, title, text}) — при первом событии, один раз за прохождение;
##    показанные — в state.flags["tut_seen"]. Выключаются в настройках («Подсказки обучения»).

const CHAPTERS := ["nightmare", "academy", "shore", "tree"]
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


## События, которые можно понять по состоянию (проверяются при обновлении карты).
static func state_events(content: Content, state: RunState) -> Array:
	var out: Array = []
	if state.chapter == "academy":
		out.append("academy_start")
	for cid: String in MissionFlow.heroes(content, state):
		var ch := state.character(cid)
		if not Array(ch.get("traumas", [])).is_empty():
			out.append("trauma")
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
	var sky := Atmosphere.sky(content, state)
	if sky in ["eclipse", "blood_moon"]:
		out.append("sky_" + sky)
	if enabled(state, "camp") and out.has("trauma"):
		out.append("camp")
	return out
