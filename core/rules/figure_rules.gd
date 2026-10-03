class_name FigureRules
extends RefCounted
## Фигура (docs/18, экспериментальная ветка gameplay/figure; решения владельца 02.10.2026): с Академии отряд —
## каменная фигура главного героя на карте-плане. Где фигура — там лагерь (state.party_at).
## День — две половины (решение владельца 03.10, вместо прыжка): шаг фигуры на соседний участок, событие там, где
## она стоит, дело лагеря или ожидание — по полдня, в любом сочетании. Две половины прошли — ночь у фигуры
## (DayRules.end_day). Событие на соседнем участке: шаг (полдня) + событие (полдня) — один день.
## Бесплатно: лавка рядом, кармашки, койки.
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


## Сколько шагов фигуры (по полдня) до события: 0 — здесь (или Натиск — он приходит к фигуре), 1 — на соседнем
## участке, дальше — путь, -1 — пути нет.
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


## reach для многих событий разом (экран, планировщик, бот): соседи фигуры и обход графа — один раз. {событие: шагов}.
static func reach_all(content: Content, state: RunState, mids: Array) -> Dictionary:
	var tg := targets(content, state)
	var dist := TravelRules.distances(content, state, state.party_at)
	var out := {}
	for mid: String in mids:
		var m: Dictionary = content.missions.get(mid, {})
		var lid := str(m.get("location", ""))
		if str(m.get("type", "")) == "onslaught" or lid == state.party_at:
			out[mid] = 0
		elif tg.has(lid):
			out[mid] = 1
		else:
			out[mid] = int(dist.get(lid, -1))
	return out


## Переставить фигуру на соседний участок: переход по правилам местности — полдня. {ok, error, entries}.
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
	out.append_array(spend(content, state))
	return {"ok": true, "error": "", "entries": out}


## Половина дня: 0 — утро (впереди целый день), 1 — после полудня (осталось полдня, потом ночь).
static func half(state: RunState) -> int:
	return int(state.flags.get("figure_half", 0))


## Действие заняло полдня: утром — наступает полдень; после полудня — ночь у фигуры. Записи (полдень или ночь).
static func spend(content: Content, state: RunState) -> Array:
	if half(state) == 0:
		state.flags["figure_half"] = 1
		state.flags.erase("event_done")
		return [{"kind": "half", "text": "Полдень · день %d — осталось полдня" % state.day}]
	return DayRules.end_day(content, state)   # снимает и figure_half


## Записи действия закончились ночью (а не полднем).
static func is_night(entries: Array) -> bool:
	return entries.any(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "night")


## «Переждать полдня» (решение владельца 03.10): утром — до полудня, после полудня — до ночи. {ok, error, entries}.
static func wait(content: Content, state: RunState) -> Dictionary:
	var why := DayRules.can_end(state)
	if why != "":
		return {"ok": false, "error": why, "entries": []}
	return {"ok": true, "error": "", "entries": spend(content, state)}


## Дело лагеря — полдня (решение владельца 03.10). {ok, error, entries}.
static func task(content: Content, state: RunState, task_id: String, cid: String) -> Dictionary:
	var r := DayPlanner.do_task(content, state, task_id, cid)
	if not r["ok"]:
		return {"ok": false, "error": str(r["error"]), "entries": []}
	var out: Array = Array(r["entries"]).duplicate()
	out.append_array(spend(content, state))
	return {"ok": true, "error": "", "entries": out}


## Событие закончилось — прошло полдня: полдень или ночь (записи). [] — если событие ещё не решено.
static func end_after_event(content: Content, state: RunState) -> Array:
	if not on(content, state) or not state.squads.is_empty() or state.game_over or state.demo_complete \
			or not state.flags.has("event_done"):
		return []
	return spend(content, state)


## Сроки событий в днях — длиннее: за день два действия по полдня (решение владельца 03.10, days.json
## figure_expires_mult = 1.5).
static func expires_mult(content: Content, state: RunState) -> float:
	return float(content.days.get("figure_expires_mult", 1.5)) if on(content, state) else 1.0


static func _days(n: int) -> String:
	if n % 10 == 1 and n % 100 != 11:
		return "день"
	if n % 10 in [2, 3, 4] and not (n % 100 in [12, 13, 14]):
		return "дня"
	return "дней"


static func _name(content: Content, lid: String) -> String:
	return str(content.locations.get(lid, content.shops.get(lid, {})).get("name", lid))
