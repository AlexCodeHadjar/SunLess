class_name FigureRules
extends RefCounted
## Фигура (docs/18, экспериментальная ветка gameplay/figure; решения владельца 02.10.2026): с Академии отряд —
## каменная фигура главного героя на карте-плане. Где фигура — там лагерь (state.party_at).
## День — одно действие: переставить фигуру на соседний участок, провести событие там, где она стоит, или переждать
## день; после действия наступает ночь (DayRules.end_day). Щелчок по событию на соседнем участке — фигура сразу
## перескакивает (день прошёл), утром событие открывается само (flags.figure_event).
## Бесплатно (день не кончается): лавка рядом, дела лагеря, кармашки, койки.
## Старое передвижение (шаги дня, марш-бросок, несколько выходов в день) — days.json "movement": "steps"
## или state.flags.movement = "steps" (тесты старых правил).


## Фигура в игре: глава с картой-планом, отряд стоит на ней, режим «figure».
static func on(content: Content, state: RunState) -> bool:
	if str(state.flags.get("movement", content.days.get("movement", "figure"))) != "figure":
		return false
	return DayRules.restricted(content, state)


## Соседние участки по тропам (все, включая те, куда сейчас нельзя).
static func neighbors(content: Content, state: RunState) -> Array:
	return MapRules.neighbors(content, state, state.party_at).filter(func(l: String) -> bool:
		return MapRules.present(content, state, l) and (content.locations.has(l) or content.shops.has(l)))


## Почему фигуру нельзя поставить на участок ("" — можно).
static func why_not(content: Content, state: RunState, lid: String) -> String:
	if state.game_over:
		return "Прохождение окончено"
	if not state.squads.is_empty():
		return "Сначала закончите событие"
	if jumped(state) != "":
		return "Фигура уже перескочила к событию — сегодня это событие"
	if lid == state.party_at:
		return "Фигура уже здесь"
	if not neighbors(content, state).has(lid):
		var d := TravelRules.distance(content, state, lid)
		return "Далеко: %d %s пути — только на соседний участок" % [d, _days(d)] if d > 1 else "Туда нет тропы"
	if TideRules.flooded(state, lid):
		return "Участок под водой — отлив через %s" % TideRules.left_text(state)
	if GateRules.blocked(state, lid):
		return "Забаррикадировано до конца тревоги"
	if TerrainRules.blocked(content, state, lid):
		return "Проход обрушен"
	var ew := TerrainRules.edge_why(content, state, state.party_at, lid)
	if ew != "":
		return ew
	return ZoneRules.why_not(content, state, lid)


## Участки, куда фигуру можно поставить сегодня.
static func targets(content: Content, state: RunState) -> Array:
	return neighbors(content, state).filter(func(l: String) -> bool: return why_not(content, state, l) == "")


## Сколько дней до события: 0 — здесь (или Натиск — он приходит к фигуре), 1 — на соседнем участке, дальше — путь,
## -1 — пути нет.
static func reach(content: Content, state: RunState, mid: String) -> int:
	var m: Dictionary = content.missions.get(mid, {})
	if str(m.get("type", "")) == "onslaught":
		return 0
	var lid := str(m.get("location", ""))
	if lid == state.party_at:
		return 0
	if targets(content, state).has(lid):
		return 1
	return TravelRules.distance(content, state, lid)


## Переставить фигуру на соседний участок: переход по правилам местности, затем ночь. {ok, error, entries}.
static func move(content: Content, state: RunState, lid: String) -> Dictionary:
	var why := why_not(content, state, lid)
	if why != "":
		return {"ok": false, "error": why, "entries": []}
	var out: Array = []
	var from := state.party_at
	TerrainRules.on_travel(content, state, [lid], from, out)   # хрупкий мост, опасный спуск, зона гнева
	TravelRules.visit(state, lid)
	state.party_at = lid
	state.clock += 1.0
	out.append({"kind": "move", "text": "Фигура перешла: %s → %s" % [_name(content, from), _name(content, lid)]})
	out.append_array(DayRules.end_day(content, state))
	return {"ok": true, "error": "", "entries": out}


## Щелчок по событию на соседнем участке (решение владельца 03.10): фигура сразу перескакивает, и событие идёт в тот
## же день — прыжок и событие вместе занимают один день. Ночь ещё не наступила; передумали (событие не начали) —
## день всё равно ушёл на переход: jump_cancel. {ok, error, entries}.
static func jump(content: Content, state: RunState, mid: String) -> Dictionary:
	var lid := str(content.missions.get(mid, {}).get("location", ""))
	var why := why_not(content, state, lid)
	if why != "":
		return {"ok": false, "error": why, "entries": []}
	var out: Array = []
	var from := state.party_at
	TerrainRules.on_travel(content, state, [lid], from, out)
	TravelRules.visit(state, lid)
	state.party_at = lid
	state.clock += 1.0
	state.flags["figure_jump"] = mid
	out.append({"kind": "move", "text": "Фигура перескочила к событию: %s → %s" % [_name(content, from), _name(content, lid)]})
	return {"ok": true, "error": "", "entries": out}


## Сегодня фигура уже перескочила к событию (его и надо проводить; "" — нет).
static func jumped(state: RunState) -> String:
	return str(state.flags.get("figure_jump", ""))


## После прыжка событие так и не начали — день ушёл на переход: ночь. Записи ночи ([] — прыжка не было).
static func jump_cancel(content: Content, state: RunState) -> Array:
	if jumped(state) == "" or not state.squads.is_empty() or state.flags.has("event_done"):
		return []
	state.flags.erase("figure_jump")
	return DayRules.end_day(content, state)


## Дело лагеря — тоже действие дня (решение владельца 03.10): сделано — ночь. {ok, error, entries}.
static func task(content: Content, state: RunState, task_id: String, cid: String) -> Dictionary:
	if jumped(state) != "":
		return {"ok": false, "error": "Фигура перескочила к событию — сегодня это событие", "entries": []}
	var r := DayPlanner.do_task(content, state, task_id, cid)
	if not r["ok"]:
		return {"ok": false, "error": str(r["error"]), "entries": []}
	var out: Array = Array(r["entries"]).duplicate()
	out.append_array(DayRules.end_day(content, state))
	return {"ok": true, "error": "", "entries": out}


## Событие закончилось — день тоже: ночь (записи для окна ночи). [] — если событие ещё не решено.
static func end_after_event(content: Content, state: RunState) -> Array:
	if not on(content, state) or not state.squads.is_empty() or state.game_over or state.demo_complete \
			or not state.flags.has("event_done"):
		return []
	state.flags.erase("figure_jump")
	return DayRules.end_day(content, state)


## Сроки событий в днях — длиннее: в день теперь одно действие (решение владельца 03.10, days.json figure_expires_mult).
static func expires_mult(content: Content, state: RunState) -> float:
	return float(content.days.get("figure_expires_mult", 2.0)) if on(content, state) else 1.0


static func _days(n: int) -> String:
	if n % 10 == 1 and n % 100 != 11:
		return "день"
	if n % 10 in [2, 3, 4] and not (n % 100 in [12, 13, 14]):
		return "дня"
	return "дней"


static func _name(content: Content, lid: String) -> String:
	return str(content.locations.get(lid, content.shops.get(lid, {})).get("name", lid))
