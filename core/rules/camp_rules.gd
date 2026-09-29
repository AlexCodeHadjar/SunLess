class_name CampRules
extends RefCounted
## Лагерь (docs/16 §9, §12): лагерь стоит там, где остановился отряд (DayRules). Койки — у места стоянки
## (camp.beds): герой на койке сегодня не ходит на миссии, а ночью отлёживается — снимает грань и отдыхает
## лучше (DayRules.end_day). Ещё здесь доска слухов. Состояние — state.camp {beds: [cid]}.


static func beds(state: RunState) -> Array:
	return Array(state.camp.get("beds", []))


static func in_bed(state: RunState, cid: String) -> bool:
	return beds(state).has(cid)


## Что койка вылечит ночью: "edge" — герой на грани отойдёт от неё ("" — нечего).
static func next_heal(_content: Content, state: RunState, cid: String) -> String:
	return "edge" if EdgeRules.on_edge(state, cid) else ""


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
	var n := int(DayRules.camp(content, state).get("beds", 2))
	if n <= 0:
		return "Здесь негде лечь: у стоянки нет укрытия"
	if b.size() >= n:
		return "Все койки заняты"
	b.append(cid)
	state.camp["beds"] = b
	return ""


static func take(state: RunState, cid: String) -> void:
	var b := beds(state)
	b.erase(cid)
	state.camp["beds"] = b


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
