class_name CampRules
extends RefCounted
## Лагерь (docs/16 §9): койки и доска слухов. Герой на койке восстанавливает психику вдвое быстрее,
## а через HEAL_EVERY секунд герой на грани отходит от неё. Уход на миссию освобождает койку.
## Состояние — state.camp {beds: [cid], heal: {cid: накоплено секунд}}.

const BEDS := 2
const SPEED := 2.0
const HEAL_EVERY := 90.0


static func beds(state: RunState) -> Array:
	return Array(state.camp.get("beds", []))


static func in_bed(state: RunState, cid: String) -> bool:
	return beds(state).has(cid)


## Что койка вылечит: "edge" — герой на грани отойдёт от неё ("" — нечего).
static func next_heal(_content: Content, state: RunState, cid: String) -> String:
	return "edge" if EdgeRules.on_edge(state, cid) else ""


static func heal_left(state: RunState, cid: String) -> float:
	return maxf(0.0, HEAL_EVERY - float(state.camp.get("heal", {}).get(cid, 0.0)))


## Уложить героя. "" — успех, иначе причина.
static func put(content: Content, state: RunState, cid: String) -> String:
	if not TutorialRules.enabled(state, "camp"):
		return "Лагерь откроется в Академии"
	if not state.is_alive(cid) or not state.characters.has(cid):
		return "Некого укладывать"
	if MissionFlow.on_mission(state, cid):
		return "%s на миссии" % content.card_name(cid)
	var b := beds(state)
	if b.has(cid):
		return ""
	if b.size() >= BEDS:
		return "Все койки заняты"
	b.append(cid)
	state.camp["beds"] = b
	return ""


static func take(state: RunState, cid: String) -> void:
	var b := beds(state)
	b.erase(cid)
	state.camp["beds"] = b
	var h: Dictionary = state.camp.get("heal", {})
	h.erase(cid)
	state.camp["heal"] = h


## Часы лагеря: ускоренный отдых, спад паники, герой на грани отходит от неё.
static func tick(content: Content, state: RunState, dt: float) -> Array:
	var out: Array = []
	var h: Dictionary = state.camp.get("heal", {})
	for cid: String in beds(state):
		if not state.is_alive(cid) or MissionFlow.on_mission(state, cid):
			take(state, cid)
			continue
		var extra := dt * (SPEED - 1.0)
		var ch := state.character(cid)
		if int(ch.get("panic", 0)) > 0 and not GrowthRules.has(content, state, cid, "panic_no_decay"):
			PsycheRules.rest(state, cid, PsycheRules.DECAY * extra)
		var tid := next_heal(content, state, cid)
		if tid == "":
			h.erase(cid)
			continue
		h[cid] = float(h.get(cid, 0.0)) + dt
		if float(h[cid]) >= HEAL_EVERY:
			h[cid] = 0.0
			EdgeRules.recover(content, state, cid, "отлежался в лагере", out)
	state.camp["heal"] = h
	return out


## Доска слухов: намёки на миссии главы, которые ещё не открылись. [{mission, text, tag, place}]
static func rumors(content: Content, state: RunState, limit: int = 6) -> Array:
	var out: Array = []
	for mid: String in MissionFlow._sorted(content.missions):
		if out.size() >= limit:
			break
		if state.missions.has(mid) or MissionFlow.chapter_of(content, mid) != state.chapter:
			continue
		if not DeckRules.allowed(content, state, mid):   # не выпавшее в колоде — не слух
			continue
		var rs: Array = content.missions[mid].get("rumors", [])
		if rs.is_empty():
			continue
		var loc: Dictionary = content.locations.get(str(content.missions[mid].get("location", "")), {})
		out.append({"mission": mid, "text": str(rs[0].get("text", "")), "tag": str(rs[0].get("tag", "")), "place": str(loc.get("name", ""))})
	return out
