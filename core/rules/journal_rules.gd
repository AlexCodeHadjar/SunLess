class_name JournalRules
extends RefCounted
## Бестиарий и журнал слухов (docs/16 §9). state.journal = {bestiary: {eid: {fights, wins, tags: [], last}},
## rumors: {mid: [индексы подтверждённых слухов]}}.
## Враг попадает в бестиарий после боя; видны теги, сработавшие в бою, а победа раскрывает все.
## Слух подтверждается, когда его тег проявился на миссии: у врага, на поле, в сработавшей связи
## или у героя отряда, который довёл миссию до успеха.


static func bestiary(state: RunState) -> Dictionary:
	return state.journal.get("bestiary", {})


static func confirmed(state: RunState, mid: String, idx: int) -> bool:
	return Array(state.journal.get("rumors", {}).get(mid, [])).has(idx)


## Что проявилось на миссии: теги врагов и полей боёв, сработавших связей, известные теги миссии.
static func shown_tags(content: Content, m: Dictionary, report: Dictionary, heroes: Array, state: RunState) -> Array:
	var out: Array = []
	var add := func(t: String) -> void:
		if t != "" and not out.has(t):
			out.append(t)
	for t: String in m.get("known_tags", []):
		add.call(t)
	for t: String in m.get("context", []):
		add.call(t)
	for cb: Dictionary in report.get("combats", []):
		var spec: Dictionary = cb.get("setup", {}).get("spec", {})
		for eid: String in spec.get("enemies", []):
			for t: String in content.enemies.get(eid, {}).get("tags", []):
				add.call(t)
		for t: String in content.fields.get(str(spec.get("field", "")), {}).get("tags", []):
			add.call(t)
		for r: Dictionary in cb.get("rounds", []):
			for l: Dictionary in r.get("ledger", {}).get("links", []):
				for t: String in l.get("tags", []):
					add.call(t)
	if report.get("outcome", "") in ["success", "partial"]:
		for cid: String in heroes:
			for t: String in MissionFlow.hero_tags(content, state, cid):
				add.call(t)
	return out


## После миссии: бестиарий и подтверждение слухов. Возвращает записи отчёта.
static func after_mission(content: Content, state: RunState, m: Dictionary, report: Dictionary, heroes: Array) -> Array:
	var entries: Array = []
	if Array(report.get("stages", [])).is_empty():
		return entries
	var best: Dictionary = state.journal.get("bestiary", {})
	for cb: Dictionary in report.get("combats", []):
		var won := str(cb.get("outcome", "")) == "win"
		var spec: Dictionary = cb.get("setup", {}).get("spec", {})
		var fired := {}
		for r: Dictionary in cb.get("rounds", []):
			for l: Dictionary in r.get("ledger", {}).get("links", []):
				for t: String in l.get("tags", []):
					fired[t] = true
		for eid: String in spec.get("enemies", []):
			var rec: Dictionary = best.get(eid, {"fights": 0, "wins": 0, "tags": []})
			if int(rec["fights"]) == 0:
				entries.append({"kind": "info", "card": eid, "text": "Бестиарий: %s" % content.card_name(eid)})
			rec["fights"] = int(rec["fights"]) + 1
			rec["wins"] = int(rec["wins"]) + (1 if won else 0)
			var seen: Array = rec["tags"]
			for t: String in content.enemies.get(eid, {}).get("tags", []):
				if (won or fired.has(t)) and not seen.has(t):
					seen.append(t)
			rec["last"] = str(m.get("title", ""))
			best[eid] = rec
	state.journal["bestiary"] = best
	var mid := str(m.get("id", ""))
	var shown := shown_tags(content, m, report, heroes, state)
	var rum: Dictionary = state.journal.get("rumors", {})
	var got: Array = rum.get(mid, [])
	var rs: Array = m.get("rumors", [])
	var fresh := 0
	for i in rs.size():
		if not got.has(i) and shown.has(str(rs[i].get("tag", ""))):
			got.append(i)
			fresh += 1
	if fresh > 0:
		# одной строкой — без нагромождения в отчёте; подробности в журнале
		entries.append({"kind": "info", "text": "Подтвердилось слухов: %d — в журнале" % fresh})
	if not got.is_empty():
		rum[mid] = got
	state.journal["rumors"] = rum
	return entries
