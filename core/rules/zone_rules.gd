class_name ZoneRules
extends RefCounted
## Зоны карты-плана (docs «Глава 4»): гнев Владыки Пепла, Очарование Древа Души, территории хозяев-ужасов
## Мрачного города. Зона — место-центр и радиус в переходах по тропам; радиус зависит от фазы недели (ночью шире),
## у территорий растёт каждую ночь до max, пока хозяина не зачистят (команда zone do=clear).
## Настройки — data/maps/<регион>.json → zones {id: {name, center, radius {фаза|default: n}, grow, max, camp {rest,
## danger}, pass_psyche, charm, owner (вид хозяина — для подписи), color}}.
## Очарование: ночь в зоне — у каждого героя +1 Очарования (0–3); на 3 — герой не уходит от Древа: отряд не покинет
## зону, пока сюжет не разорвёт чары (команда zone do=break).
## Состояние: state.flags.zones {id: {grow, cleared}}, у героев — characters[cid].charm; flags.charm_broken.


static func cfg(content: Content, state: RunState) -> Dictionary:
	return Dictionary(MapRules.config(content, state.chapter).get("zones", {}))


static func zstate(state: RunState, zid: String) -> Dictionary:
	return Dictionary(Dictionary(state.flags.get("zones", {})).get(zid, {}))


static func cleared(state: RunState, zid: String) -> bool:
	return int(zstate(state, zid).get("cleared", 0)) >= state.day


## Сколько разных районов зачищено за главу (сюжет Мрачного города: unlock.zones_cleared).
static func cleared_total(state: RunState) -> int:
	return Array(state.flags.get("zones_done", [])).size()


## Радиус зоны сейчас (в переходах; -1 — зоны нет).
static func radius(content: Content, state: RunState, zid: String) -> int:
	var z: Dictionary = cfg(content, state).get(zid, {})
	if z.is_empty() or cleared(state, zid):
		return -1
	if bool(z.get("charm", false)) and bool(state.flags.get("charm_broken", false)):
		return -1
	var ph := str(DayRules.phase(content, state).get("id", ""))
	var r: Dictionary = z.get("radius", {"default": 0})
	var base := int(r.get(ph, r.get("default", 0)))
	return mini(base + int(zstate(state, zid).get("grow", 0)), int(z.get("max", 9)))


## Места зоны: обход в ширину от центра по тропам на radius переходов.
static func places(content: Content, state: RunState, zid: String) -> Array:
	var rad := radius(content, state, zid)
	if rad < 0:
		return []
	var center := str(cfg(content, state)[zid].get("center", ""))
	var adj := TravelRules.adjacency(content, state)
	var dist := {center: 0}
	var queue: Array = [center]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if int(dist[cur]) >= rad:
			continue
		for n: String in adj.get(cur, []):
			if not dist.has(n) and MapRules.present(content, state, n):
				dist[n] = int(dist[cur]) + 1
				queue.append(n)
	return dist.keys()


static func in_zone(content: Content, state: RunState, zid: String, lid: String) -> bool:
	return places(content, state, zid).has(lid)


## Зоны, в которые попадает место.
static func zones_at(content: Content, state: RunState, lid: String) -> Array:
	var out: Array = []
	for zid: String in MissionFlow._sorted(cfg(content, state)):
		if in_zone(content, state, zid, lid):
			out.append(zid)
	return out


## Лагерь в зоне: отдых и опасность ночи.
static func camp_mod(content: Content, state: RunState, lid: String, camp: Dictionary) -> Dictionary:
	var c := cfg(content, state)
	if c.is_empty():
		return camp
	var d := camp.duplicate(true)
	for zid: String in zones_at(content, state, lid):
		var zc: Dictionary = c[zid].get("camp", {})
		d["rest"] = int(d.get("rest", 20)) + int(zc.get("rest", 0))
		d["danger"] = clampf(float(d.get("danger", 0.0)) + float(zc.get("danger", 0.0)), 0.0, 0.95)
		if int(zc.get("beds", 0)) > 0:
			d["beds"] = int(d.get("beds", 0)) + int(zc["beds"])
	return d


## Психика за проход через зону (гнев Владыки): сумма по местам маршрута.
static func pass_cost(content: Content, state: RunState, path: Array) -> int:
	var total := 0
	for zid: String in cfg(content, state):
		var cost := int(cfg(content, state)[zid].get("pass_psyche", 0))
		if cost == 0:
			continue
		for p: String in path:
			if in_zone(content, state, zid, p):
				total += cost
	return total


# --- Очарование -----------------------------------------------------------------------------------------

static func charm(state: RunState, cid: String) -> int:
	return int(state.character(cid).get("charm", 0))


## Очарованные (3) герои: не уйдут из зоны Очарования.
static func charmed(content: Content, state: RunState) -> Array:
	if bool(state.flags.get("charm_broken", false)):
		return []
	return MissionFlow.heroes(content, state).filter(func(cid: String) -> bool: return charm(state, cid) >= 3)


## Почему отряд не уйдёт в место ("" — уйдёт): очарованные не покидают зону Очарования.
static func why_not(content: Content, state: RunState, lid: String) -> String:
	var ch := charmed(content, state)
	if ch.is_empty():
		return ""
	for zid: String in cfg(content, state):
		if bool(cfg(content, state)[zid].get("charm", false)) and in_zone(content, state, zid, state.party_at) and not in_zone(content, state, zid, lid):
			return "%s не уйдёт от Древа — чары держат" % ", ".join(ch.map(func(x: String) -> String: return content.card_name(x)))
	return ""


# --- ночь -------------------------------------------------------------------------------------------------

## Ночь: рост территорий, Очарование у героев в зоне.
static func night(content: Content, state: RunState) -> Array:
	var out: Array = []
	var c := cfg(content, state)
	if c.is_empty():
		return out
	var zs: Dictionary = Dictionary(state.flags.get("zones", {})).duplicate(true)
	for zid: String in MissionFlow._sorted(c):
		var z: Dictionary = c[zid]
		var e: Dictionary = zs.get(zid, {})
		if int(z.get("grow", 0)) > 0 and not cleared(state, zid):
			var g := int(e.get("grow", 0))
			if g < int(z.get("max", 2)):
				e["grow"] = g + int(z["grow"])
				if int(e["grow"]) == int(z.get("max", 2)):
					out.append({"kind": "zone", "text": "%s расползается по руинам" % str(z.get("name", zid))})
		zs[zid] = e
		if bool(z.get("charm", false)) and not bool(state.flags.get("charm_broken", false)) and in_zone(content, state, zid, state.party_at):
			for cid: String in MissionFlow.heroes(content, state):
				var ch: Dictionary = state.character(cid)
				var before := int(ch.get("charm", 0))
				ch["charm"] = mini(3, before + 1)
				if before < 3 and int(ch["charm"]) == 3:
					out.append({"kind": "zone", "text": "%s очарован Древом — не хочет уходить" % content.card_name(cid)})
	state.flags["zones"] = zs
	return out


## {cmd: zone, do: clear|break, zone, days?}
static func command(content: Content, state: RunState, e: Dictionary) -> Array:
	var zid := str(e.get("zone", ""))
	var zs: Dictionary = Dictionary(state.flags.get("zones", {})).duplicate(true)
	match str(e.get("do", "")):
		"clear":
			zs[zid] = {"grow": 0, "cleared": state.day + int(e.get("days", 5))}
			state.flags["zones"] = zs
			var done: Array = state.flags.get("zones_done", [])
			if not done.has(zid):
				done.append(zid)
			state.flags["zones_done"] = done
			return [{"kind": "zone", "text": "%s зачищено — на время здесь безопасно" % str(cfg(content, state).get(zid, {}).get("name", zid))}]
		"break":
			state.flags["charm_broken"] = true
			for cid: String in MissionFlow.heroes(content, state):
				state.character(cid)["charm"] = 0
			return [{"kind": "zone", "text": "Чары Древа разорваны — отряд видит правду"}]
	return []


static func reset(state: RunState) -> void:
	for k: String in ["zones", "charm_broken", "zones_done"]:
		state.flags.erase(k)
	for cid: String in state.characters:
		state.characters[cid].erase("charm")
