class_name DayPlanner
extends RefCounted
## Планировщик дня (docs/17 §4–§6, решения владельца 29.09.2026): у игрока всегда есть чем заняться.
## 1) Каждое утро (и в начале главы) — проверка «дела на сегодня»: миссии, до которых можно дойти сегодня
##    без марш-броска. Меньше min_options — поднимаются местные встречи (random.local у мест, затем
##    обычные встречи мест) в ближайших сухих местах, куда можно встать лагерем. Так не бывает дня, когда
##    нечего делать, кроме как ждать воды или фазы.
## 2) Дела лагеря — всегда доступны (каждое один раз в день): Разведка (открыть места в двух переходах и найти
##    встречу), Сбор (осколки; после отлива больше), Дозор (ночное нападение реже). Исполнитель тратит выход:
##    усталость как за миссию.
## 3) Режиссёр напряжения (docs/17 §18, по мотивам режиссёра Left 4 Dead): напряжение отряда 0..1 — психика,
##    грань смерти, Натиск, вода, кровавая луна. Вымотан (≥ CALM_FROM) — встречи спокойные (проверки), свеж
##    (< FIGHT_BELOW) — с боем, и Натиск приходит на день раньше; между — по чётности дня.

const TASKS := ["scout", "forage", "watch"]
const CALM_FROM := 0.5
const FIGHT_BELOW := 0.3


static func min_options(content: Content) -> int:
	return int(content.days.get("min_options", 2))


## Миссии главы по досягаемости: today — дойти сегодня без марш-броска (или уже на месте),
## march — дойти можно, но с марш-броском, cut — под водой или путь отрезан водой.
static func options(content: Content, state: RunState) -> Dictionary:
	var out := {"today": [], "march": [], "cut": []}
	var fig := FigureRules.on(content, state)
	var ra := FigureRules.reach_all(content, state, MissionFlow.open_missions(state)) if fig else {}
	for mid: String in MissionFlow.open_missions(state):
		if MissionFlow.chapter_of(content, mid) != state.chapter:
			continue
		var m: Dictionary = content.missions.get(mid, {})
		if m.has("wander"):
			continue   # бродячий босс — особое событие, не «дело на сегодня» (docs/22)
		if str(m.get("type", "")) == "onslaught":
			out["today"].append(mid)   # натиск приходит сам
			continue
		var lid := str(m.get("location", ""))
		if TideRules.flooded(state, lid):
			out["cut"].append(mid)
			continue
		if fig:   # фигура: сегодня — здесь и на соседних участках, дальше — путь
			var r := int(ra[mid])
			out["cut" if r < 0 else ("today" if r <= 1 else "march")].append(mid)
			continue
		var d := TravelRules.distance(content, state, lid)
		if d < 0:
			out["cut"].append(mid)
		elif TravelRules.march_steps(content, state, d) == 0:
			out["today"].append(mid)
		else:
			out["march"].append(mid)
	return out


## Сколько дел на сегодня: миссии без марш-броска + дела лагеря, которые ещё можно сделать.
static func count_today(content: Content, state: RunState) -> int:
	return (options(content, state)["today"] as Array).size() + tasks_left(content, state).size()


## Утренняя проверка: мало миссий в досягаемости — поднять местные встречи рядом. Возвращает события.
static func ensure(content: Content, state: RunState) -> Array:
	var out: Array = []
	if not DayRules.restricted(content, state):
		return out
	var need := min_options(content) - (options(content, state)["today"] as Array).size()
	if need <= 0:
		return out
	for lid: String in _candidates(content, state, 1 if FigureRules.on(content, state) else TravelRules.free_steps(content)):
		if need <= 0:
			break
		var ev := spawn_local(content, state, lid)
		if not ev.is_empty():
			out.append_array(ev)
			need -= 1
	if not out.is_empty():
		out.push_front({"kind": "planner", "text": "Рядом с лагерем неспокойно — появились местные встречи"})
	# свежий отряд: Натиск не заставит себя ждать
	var nd := OnslaughtRules.next_day(state)
	if tension(content, state) < FIGHT_BELOW and nd > state.day + 1 and int(state.flags.get("onslaught_nudged", 0)) != nd:
		state.flags["onslaught_day"] = nd - 1
		state.flags["onslaught_nudged"] = nd - 1   # каждый Натиск — не больше чем на день раньше
	return out


## Напряжение отряда 0..1: низкая психика, герои на грани, Натиск, вода, кровавая луна.
static func tension(content: Content, state: RunState) -> float:
	var heroes := MissionFlow.heroes(content, state)
	if heroes.is_empty():
		return 0.0
	var psy := 0.0
	var edge := 0
	for cid: String in heroes:
		psy += PsycheRules.psyche(state, cid)
		if EdgeRules.on_edge(state, cid):
			edge += 1
	var t := (1.0 - psy / heroes.size() / 100.0) * 0.5 + float(edge) / heroes.size() * 0.3
	if MissionFlow.open_missions(state).any(func(m: String) -> bool: return str(content.missions.get(m, {}).get("type", "")) == "onslaught"):
		t += 0.1
	if TideRules.phase(state) != "":
		t += 0.1
	if str(DayRules.phase(content, state).get("id", "")) == "blood_moon":
		t += 0.1
	return clampf(t, 0.0, 1.0)


## Какие встречи режиссёр ставит первыми: calm — вымотанному отряду, fight — свежему.
static func preferred_kind(content: Content, state: RunState) -> String:
	var t := tension(content, state)
	if t >= CALM_FROM:
		return "calm"
	if t < FIGHT_BELOW:
		return "fight"
	return "calm" if state.day % 2 == 0 else "fight"


## Места для встречи: сухие, где можно встать лагерем, без открытой миссии; ближние — первыми.
static func _candidates(content: Content, state: RunState, max_steps: int) -> Array:
	var busy := {}
	for mid: String in MissionFlow.open_missions(state):
		busy[str(content.missions.get(mid, {}).get("location", ""))] = true
	var list: Array = []
	for lid: String in MapRules.config(content, state.chapter).get("places", {}):
		if busy.has(lid) or not TravelRules.can_stop(content, state, lid):
			continue
		var d := TravelRules.distance(content, state, lid)
		if d < 0 or d > max_steps:
			continue
		list.append([d, lid])
	list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and str(a[1]) < str(b[1])))
	return list.map(func(x: Array) -> String: return str(x[1]))


## Поднять встречу в месте: сначала местная (random.local), потом обычная встреча места. [] — нечего поднять.
static func spawn_local(content: Content, state: RunState, lid: String) -> Array:
	var rnd: Dictionary = content.locations.get(lid, {}).get("random", {})
	# местные встречи — нужного режиссёру вида первыми, потом обычные встречи места
	var want := preferred_kind(content, state)
	var local: Array = Array(rnd.get("local", [])).duplicate()
	local.sort_custom(func(a: String, b: String) -> bool:
		var ka := str(content.missions.get(a, {}).get("local_kind", "")) == want
		var kb := str(content.missions.get(b, {}).get("local_kind", "")) == want
		return ka and not kb if ka != kb else a < b)
	var pool: Array = local + Array(rnd.get("pool", []))
	for mid: String in pool:
		if not content.missions.has(mid) or str(state.missions.get(mid, {}).get("status", "")) in ["open", "active"]:
			continue
		if not DeckRules.allowed(content, state, mid):
			continue
		var ev := MissionFlow.open(content, state, mid)
		if not ev.is_empty():
			return ev
	return []


# --- дела лагеря ---------------------------------------------------------------------------

static func new_day(state: RunState) -> void:
	state.flags["tasks_done"] = []
	state.flags["watch"] = false


static func task_def(content: Content, task: String) -> Dictionary:
	return content.days.get("tasks", {}).get(task, {})


## Дела лагеря, которые сегодня ещё можно сделать (есть свободный герой и отряд не на миссии).
static func tasks_left(content: Content, state: RunState) -> Array:
	if not DayRules.restricted(content, state) or not state.squads.is_empty() or MissionFlow.free_heroes(content, state).is_empty():
		return []
	var done: Array = state.flags.get("tasks_done", [])
	return TASKS.filter(func(t: String) -> bool: return not done.has(t) and not task_def(content, t).is_empty())


## Почему герой не может взяться за дело ("" — может).
static func can_task(content: Content, state: RunState, task: String, cid: String) -> String:
	if not DayRules.restricted(content, state):
		return "Дела лагеря — на карте главы"
	if task_def(content, task).is_empty():
		return "Нет такого дела"
	if Array(state.flags.get("tasks_done", [])).has(task):
		return "Сегодня это уже сделано"
	if not state.squads.is_empty():
		return "Отряд на миссии"
	return MissionFlow.busy_reason(content, state, cid)


## Сделать дело лагеря. Возвращает {ok, error, entries}.
static func do_task(content: Content, state: RunState, task: String, cid: String) -> Dictionary:
	var why := can_task(content, state, task, cid)
	if why != "":
		return {"ok": false, "error": why, "entries": []}
	var out: Array = []
	var d := task_def(content, task)
	# выход героя: усталость как за миссию
	var loss := DayRules.fatigue_cost(content, state, cid)
	var ch := state.character(cid)
	ch["sorties"] = DayRules.sorties(state, cid) + 1
	if loss < 0:
		out.append_array(PsycheRules.change(content, state, cid, loss, "усталость", [cid], null, "mission", false))
	var rng := RandomNumberGenerator.new()
	rng.seed = state.rng_seed + 7919 * state.day + cid.hash() + task.hash()
	var name := content.card_name(cid)
	match task:
		"scout":
			out.append_array(_scout(content, state, name))
		"forage":
			var r: Array = d.get("shards", [2, 3])
			var n := rng.randi_range(int(r[0]), int(r[1]))
			if str(DayRules.phase(content, state).get("tide", "")) == "ebb":
				n += int(d.get("shards_ebb", 2))
			state.resources["shards"] = int(state.resources.get("shards", 0)) + n
			out.append({"kind": "task", "text": "%s собирает у лагеря: +%d %s" % [name, n, _shards(n)]})
		"watch":
			state.flags["watch"] = true
			out.append({"kind": "task", "text": "%s будет сторожить лагерь: ночью нападут вдвое реже" % name})
	var done: Array = state.flags.get("tasks_done", [])
	done.append(task)
	state.flags["tasks_done"] = done
	return {"ok": true, "error": "", "entries": out}


## Разведка: места в двух переходах открыты, в ближайшем пустом — встреча.
static func _scout(content: Content, state: RunState, name: String) -> Array:
	var out: Array = []
	var adj := TravelRules.adjacency(content, state)
	var sc: Array = state.flags.get("scouted", [])
	var found := 0
	for n: String in adj.get(state.party_at, []):
		for p: String in [n] + Array(adj.get(n, [])):
			if p != state.party_at and not sc.has(p) and MapRules.present(content, state, p):
				sc.append(p)
				found += 1
	state.flags["scouted"] = sc
	out.append({"kind": "task", "text": "%s обходит окрестности: открыто мест — %d" % [name, found]})
	for lid: String in _candidates(content, state, 2):
		var ev := spawn_local(content, state, lid)
		if not ev.is_empty():
			out.append_array(ev)
			break
	return out


static func _shards(n: int) -> String:
	return ["осколок", "осколка", "осколков"][0 if n % 10 == 1 and n % 100 != 11 else (1 if n % 10 in [2, 3, 4] and not n % 100 in [12, 13, 14] else 2)]
