class_name TravelRules
extends RefCounted
## Перемещение отряда по карте-плану (docs/17 §2, решения владельца 29.09.2026).
## Карта — граф: узлы — места карты (и лавки), рёбра — тропы (MapRules.links). По воде не ходят: место под
## водой непроходимо. Лавку можно пройти насквозь, но лагерем встать можно только в месте из locations.
## Шаги дня: steps_free переходов в день бесплатно, каждый следующий — марш-бросок (march_psyche всем героям).
## Маршрут — кратчайший путь (поиск в ширину) до цели. Миссию «далеко» запускают сразу: отряд идёт по маршруту.
## Что игрок видит (MapRules.revealed): посещённые места, соседи посещённых, путь к каждой открытой миссии.


static func free_steps(content: Content) -> int:
	return int(content.days.get("steps_free", 3))


static func steps_used(state: RunState) -> int:
	return int(state.flags.get("steps", 0))


static func steps_left(content: Content, state: RunState) -> int:
	return maxi(0, free_steps(content) - steps_used(state))


## Место можно пройти: есть на карте сейчас и не под водой.
static func passable(content: Content, state: RunState, lid: String) -> bool:
	if not MapRules.present(content, state, lid):
		return false
	if not content.locations.has(lid) and not content.shops.has(lid):
		return false
	if GateRules.blocked(state, lid) or TerrainRules.blocked(content, state, lid):
		return false
	return not TideRules.flooded(state, lid)


## Здесь можно встать лагерем (лавка — только проход).
static func can_stop(content: Content, state: RunState, lid: String) -> bool:
	return content.locations.has(lid) and passable(content, state, lid)


## Соседи по тропам (все, включая затопленные).
static func adjacency(content: Content, state: RunState) -> Dictionary:
	var adj := {}
	for pair: Array in MapRules.links(content, state):
		for k in 2:
			var a := str(pair[k])
			var b := str(pair[1 - k])
			if not adj.has(a):
				adj[a] = []
			if not (adj[a] as Array).has(b):
				(adj[a] as Array).append(b)
	for a: String in adj:
		(adj[a] as Array).sort()   # порядок — для одинаковых маршрутов при одинаковой длине
	return adj


## Кратчайший маршрут from → to по проходимым местам: [следующее, …, to]; [] — нет пути или уже там.
## dry_only=false — искать и через воду (чтобы показать путь, «отрезанный водой»).
static func route(content: Content, state: RunState, from: String, to: String, dry_only: bool = true) -> Array:
	if from == to or from == "" or to == "":
		return []
	var adj := adjacency(content, state)
	var prev := {from: ""}
	var queue: Array = [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == to:
			break
		for n: String in adj.get(cur, []):
			if prev.has(n) or not MapRules.present(content, state, n):
				continue
			if not content.locations.has(n) and not content.shops.has(n):
				continue
			if dry_only and (TideRules.flooded(state, n) or GateRules.blocked(state, n) or TerrainRules.blocked(content, state, n) \
					or not TerrainRules.edge_ok(content, state, cur, n)):
				continue
			prev[n] = cur
			queue.append(n)
	if not prev.has(to):
		return []
	var path: Array = []
	var at := to
	while at != from:
		path.push_front(at)
		at = str(prev[at])
	return path


## Сколько переходов до места от лагеря: 0 — здесь, -1 — пути нет (вода или тропы нет).
## Расстояния от from до всех мест разом — тот же обход и те же правила, что у route (длина пути = глубина обхода).
## {место: переходов}; from — 0; недостижимых нет в ответе.
static func distances(content: Content, state: RunState, from: String, dry_only: bool = true) -> Dictionary:
	if from == "":
		return {}
	var adj := adjacency(content, state)
	var out := {from: 0}
	var queue: Array = [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for n: String in adj.get(cur, []):
			if out.has(n) or not MapRules.present(content, state, n):
				continue
			if not content.locations.has(n) and not content.shops.has(n):
				continue
			if dry_only and (TideRules.flooded(state, n) or GateRules.blocked(state, n) or TerrainRules.blocked(content, state, n) \
					or not TerrainRules.edge_ok(content, state, cur, n)):
				continue
			out[n] = int(out[cur]) + 1
			queue.append(n)
	return out


static func distance(content: Content, state: RunState, lid: String) -> int:
	if lid == state.party_at:
		return 0
	var r := route(content, state, state.party_at, lid)
	return r.size() if not r.is_empty() else -1


## Сколько из n переходов будут марш-броском (сверх бесплатных на сегодня).
static func march_steps(content: Content, state: RunState, n: int) -> int:
	return maxi(0, steps_used(state) + n - free_steps(content))


## Психика каждому герою за n переходов сегодня (0 или отрицательная).
static func march_cost(content: Content, state: RunState, n: int) -> int:
	return march_steps(content, state, n) * int(content.days.get("march_psyche", -6))


## Почему туда не пройти ("" — можно). Цель — место, где можно встать лагерем.
static func why_not(content: Content, state: RunState, lid: String) -> String:
	if not state.squads.is_empty():
		return "Сначала закончите миссию"
	if lid == state.party_at:
		return ""
	if not content.locations.has(lid):
		return "Здесь нельзя встать лагерем — только пройти мимо"
	if not MapRules.present(content, state, lid):
		return "Туда не пройти"
	if TideRules.flooded(state, lid):
		return "Место под водой — отлив через %s" % TideRules.left_text(state)
	if GateRules.blocked(state, lid):
		return "Забаррикадировано до конца тревоги"
	if TerrainRules.blocked(content, state, lid):
		return "Проход обрушен"
	var zw := ZoneRules.why_not(content, state, lid)
	if zw != "":
		return zw
	if route(content, state, state.party_at, lid).is_empty():
		var wet := route(content, state, state.party_at, lid, false)
		if not wet.is_empty():
			var prev := state.party_at
			for p: String in wet:
				var ew := TerrainRules.edge_why(content, state, prev, p)
				if ew != "":
					return ew
				prev = p
			if TideRules.phase(state) != "flood":
				return "Проход перекрыт — до конца тревоги"
			return "Путь отрезан водой — отлив через %s" % TideRules.left_text(state)
		return "Туда нет тропы"
	return ""


## Пройти по маршруту к месту: шаги дня, марш-бросок сверх бесплатных, лагерь переезжает. "" — дошли.
static func travel(content: Content, state: RunState, lid: String, out: Array) -> String:
	var why := why_not(content, state, lid)
	if why != "" or lid == state.party_at:
		return why
	var path := route(content, state, state.party_at, lid)
	var march := march_steps(content, state, path.size())
	if march > 0:
		var cost := march * int(content.days.get("march_psyche", -6))
		for cid: String in MissionFlow.heroes(content, state):
			out.append_array(PsycheRules.change(content, state, cid, cost, "марш-бросок", [], null, "mission", false))
	state.flags["steps"] = steps_used(state) + path.size()
	TerrainRules.on_travel(content, state, path, state.party_at, out)   # хрупкий мост, опасный спуск, зона гнева
	for p: String in path:
		visit(state, p)
	var names: Array = path.map(func(p: String) -> String: return str(content.locations.get(p, content.shops.get(p, {})).get("name", p)))
	state.party_at = lid
	state.clock += 1.0
	out.append({"kind": "move", "text": "Отряд перешёл: %s%s" % [" → ".join(names),
		(" · марш-бросок, психика %d" % (march * int(content.days.get("march_psyche", -6)))) if march > 0 else ""]})
	return ""


## Отряд побывал в месте: оно и его соседи больше не скрыты туманом.
static func visit(state: RunState, lid: String) -> void:
	if lid == "":
		return
	var v: Array = state.flags.get("visited", [])
	if not v.has(lid):
		v.append(lid)
	state.flags["visited"] = v


static func visited(state: RunState) -> Array:
	return Array(state.flags.get("visited", []))


## Новый день: шаги снова бесплатны.
static func new_day(state: RunState) -> void:
	state.flags["steps"] = 0
