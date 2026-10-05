class_name QuestRules
extends RefCounted
## Задания (просьба владельца 03.10, docs/20): справа на экране карты — что сейчас двигает сюжет главы и побочные
## линии, где это и как туда добраться. Ничего не меняет в игре — только собирает из состояния понятный список.
## Записи: {id, kind: story | side | threat, group (имя линии), title, line (что делать), place, place_name, steps, left}.
##   story  — открытые сюжетные события главы (и то, где сейчас стоит отряд); нет открытых — «Сюжет ждёт» с причиной
##            (Врата, районы, обязательные события);
##   side   — побочные линии: цепочки и группы колоды (deck.json: units с name/missions), события с продолжением (next),
##            события, которые закрывают Врата или районы (on_complete threat/zone), — то, что ведёт второстепенный сюжет;
##   threat — угрозы карты (GateRules: прорывы, Врата, волны) — их не бросают.
## Цель главы — data/quests.json → goals (tools/gen_quests.py).

const MAX_SIDE := 4
const MAX_THREAT := 2


## Цель главы одной строкой ("" — нет).
static func goal(content: Content, state: RunState) -> String:
	return str(content.quests.get("goals", {}).get(state.chapter, ""))


## Список заданий: сюжет первым, затем угрозы и побочные линии (ближние и срочные выше).
static func list(content: Content, state: RunState) -> Array:
	var c := content
	var s := state
	var mids: Array = []
	for mid: String in MissionFlow.open_missions(s):
		if MissionFlow.chapter_of(c, mid) == s.chapter:
			mids.append(mid)
	var busy := {}
	for sq: Dictionary in s.squads:
		busy[str(sq["mission"])] = true
		if not mids.has(sq["mission"]):
			mids.append(sq["mission"])
	var ra := FigureRules.reach_all(c, s, mids) if FigureRules.on(c, s) else {}
	var groups := _groups(c, s.chapter)
	var threats := GateRules.mission_ids(c, s)
	var story: Array = []
	var side: Array = []
	var threat: Array = []
	var boss: Array = []
	var left_of := {}
	for w: Dictionary in WanderRules.active(c, s):
		left_of[str(w["mid"])] = int(w["left"])
	for mid: String in mids:
		var m: Dictionary = c.missions.get(mid, {})
		var typ := str(m.get("type", ""))
		var e := entry(c, s, mid, ra, busy.has(mid))
		if typ == "story":
			e["kind"] = "story"
			story.append(e)
		elif m.has("trial"):
			e["kind"] = "story"
			e["group"] = "Испытание души"
			story.append(e)
		elif m.has("wander"):
			e["kind"] = "boss"
			e["group"] = "Бродячий босс"
			e["title"] = str(m.get("title", mid)).trim_prefix("Бродячий босс: ")
			if left_of.has(mid) and not busy.has(mid):
				var lf := int(left_of[mid])
				e["line"] = str(e["line"]) + " · уйдёт %s" % ("этой ночью" if lf <= 1 else "через %d %s" % [lf, UITheme.plural(lf, ["день", "дня", "дней"])])
			boss.append(e)
		elif threats.has(mid):
			e["kind"] = "threat"
			threat.append(e)
		elif typ in ["side", "onslaught"] and (groups.has(mid) or _moves_plot(m) or typ == "onslaught"):
			e["kind"] = "side"
			e["group"] = str(groups.get(mid, "Натиск Кошмара" if typ == "onslaught" else ""))
			side.append(e)
	if story.is_empty():
		var w := _story_wait(c, s)
		if w != "":
			story.append({"id": "wait", "kind": "story", "group": "", "title": "Сюжет ждёт", "line": w, "place": "",
				"place_name": "", "steps": -1, "left": -1})
	var near := func(a: Dictionary, b: Dictionary) -> bool:
		var la := int(a["left"]) if int(a["left"]) >= 0 else 99
		var lb := int(b["left"]) if int(b["left"]) >= 0 else 99
		var sa := int(a["steps"]) if int(a["steps"]) >= 0 else 99
		var sb := int(b["steps"]) if int(b["steps"]) >= 0 else 99
		return [la, sa, str(a["id"])] < [lb, sb, str(b["id"])]
	threat.sort_custom(near)
	side.sort_custom(near)
	return story + threat.slice(0, MAX_THREAT) + boss + side.slice(0, MAX_SIDE)


## Одно задание: где событие и что сделать, чтобы его провести.
static func entry(content: Content, state: RunState, mid: String, ra: Dictionary = {}, on_site: bool = false) -> Dictionary:
	var m: Dictionary = content.missions.get(mid, {})
	var lid := MissionFlow.place_of(content, state, mid)
	var place := str(content.locations.get(lid, content.shops.get(lid, {})).get("name", lid))
	var fig := FigureRules.on(content, state)
	var steps := 0
	if str(m.get("type", "")) != "onslaught" and DayRules.restricted(content, state):
		steps = int(ra[mid]) if ra.has(mid) else (FigureRules.reach(content, state, mid) if fig else TravelRules.distance(content, state, lid))
	var line := ""
	if on_site:
		line = "Отряд на месте — выберите действие"
	elif str(m.get("type", "")) == "onslaught":
		line = "Натиск у лагеря — отбейте его"
	elif not DayRules.restricted(content, state):
		line = "Щёлкните по событию — брифинг и отряд"
	elif TideRules.mission_flooded(content, state, mid):
		line = "%s под водой — ждите отлива (%s)" % [place, TideRules.left_text(state)]
		steps = -1
	elif not MapRules.revealed(content, state, lid):
		line = "Место в тумане — разведайте окрестности"
	elif steps == 0:
		line = "Здесь, у фигуры — проведите событие" if fig else "Здесь, у лагеря — отправляйте отряд"
	elif steps < 0:
		line = "Путь к месту «%s» сейчас закрыт — ищите обход или ждите" % place
	elif fig:
		line = "%s — %s" % [place, "соседний участок, шаг фигуры (полдня)" if steps == 1 else
			"%d %s пути (≈ %s)" % [steps, UITheme.plural(steps, ["шаг", "шага", "шагов"]), _days_text(steps)]]
	else:
		line = "%s — %d %s" % [place, steps, UITheme.plural(steps, ["переход", "перехода", "переходов"])]
	var left := MissionFlow.expires_in(content, state, mid)
	if left >= 0 and not on_site:
		line += " · уйдёт %s" % ("этой ночью" if left <= 1 else "через %d %s" % [left, UITheme.plural(left, ["день", "дня", "дней"])])
	return {"id": mid, "kind": "", "group": "", "title": str(m.get("title", mid)), "line": line, "place": lid,
		"place_name": place, "steps": steps, "left": left}


## Шаги фигуры в днях: два шага — день.
static func _days_text(steps: int) -> String:
	var d := int(ceil(steps / 2.0))
	return "%d %s" % [d, UITheme.plural(d, ["день", "дня", "дней"])]


## Чего ждёт сюжет, когда открытых сюжетных событий нет: Врат, районов, обязательных событий ("" — ничего).
static func _story_wait(content: Content, state: RunState) -> String:
	var w := MissionFlow.story_wait(content, state)
	if w != "":
		return _cap(w.trim_prefix("Сюжет ждёт — "))
	for mid: String in MissionFlow._sorted(content.missions):
		var m: Dictionary = content.missions[mid]
		if str(m.get("type", "")) != "story" or MissionFlow.chapter_of(content, mid) != state.chapter or state.missions.has(mid):
			continue
		var need: Array = Array(m.get("unlock", {}).get("after_all", [])).filter(func(x: String) -> bool:
			return str(state.missions.get(x, {}).get("status", "")) != "done")
		if not need.is_empty():
			return "Сначала: " + ", ".join(need.map(func(x: String) -> String: return "«%s»" % content.missions.get(x, {}).get("title", x)))
	return ""


static func _cap(t: String) -> String:
	return t.left(1).to_upper() + t.substr(1)


## Миссия -> имя линии из колоды главы (цепочки и группы с именем).
static func _groups(content: Content, chapter: String) -> Dictionary:
	var key := "quest_groups:" + chapter
	if content.memo.has(key):
		return content.memo[key]
	var out := {}
	for grp: Dictionary in content.deck.get(chapter, []):
		for u: Variant in grp.get("units", []):
			if u is Dictionary and str((u as Dictionary).get("name", "")) != "":
				for mid: String in (u as Dictionary).get("missions", []):
					out[mid] = str(u["name"])
	content.memo[key] = out
	return out


## Событие двигает побочный сюжет: у него есть продолжение или оно закрывает Врата и районы.
static func _moves_plot(m: Dictionary) -> bool:
	if not Array(m.get("next", [])).is_empty():
		return true
	for cmd: Dictionary in m.get("on_complete", []):
		if str(cmd.get("cmd", "")) in ["threat", "zone"]:
			return true
	return false
