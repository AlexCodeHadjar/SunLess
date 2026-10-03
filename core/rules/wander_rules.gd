class_name WanderRules
extends RefCounted
## Бродячие боссы (просьба владельца 03.10, docs/22): исполинская тварь бродит по карте-плану главы. С дня появления
## она стоит на одном из своих мест 2–3 дня, потом ночью уходит на другое (обычно недалеко). Пока стоит — там особое
## событие «Бродячий босс: …» (data/missions/wanderers.json, по событию на каждое место; поле wander). Победа — награда:
## легендарное Воспоминание и осколки, босс уходит из главы навсегда. Поражение — босс остаётся (раны врага
## сохраняются) и бродит дальше.
## Не мешает игроку: встаёт только на открытое место, не туда, где фигура, не на место с другими событиями, не туда,
## где открыт сюжет, и не на путь фигуры к сюжету; не на воду и не на перекрытое. Сам не нападает. Фигура пришла к
## боссу — он ждёт её (не уходит ночью), пока она рядом.
## Данные — data/wanderers.json (tools/gen_wanderers.py); состояние — state.flags.wanderers {босс: {at, mid, days,
## rest, from, done}}.


## Боссы главы.
static func defs(content: Content, chapter: String) -> Array:
	return Array(content.wanderers.get("list", [])).filter(func(w: Dictionary) -> bool: return str(w.get("chapter", "")) == chapter)


static func _st(state: RunState) -> Dictionary:
	if not state.flags.has("wanderers"):
		state.flags["wanderers"] = {}
	return state.flags["wanderers"]


## Босс сейчас стоит на карте: [{id, name, at, mid, left (дней до ухода), from}].
static func active(content: Content, state: RunState) -> Array:
	var out: Array = []
	var all: Dictionary = state.flags.get("wanderers", {})
	for w: Dictionary in defs(content, state.chapter):
		var st: Dictionary = all.get(str(w["id"]), {})
		if bool(st.get("done", false)) or str(st.get("at", "")) == "":
			continue
		out.append({"id": str(w["id"]), "name": str(w["name"]), "at": str(st["at"]), "mid": str(st.get("mid", "")),
			"left": maxi(1, int(st.get("rest", 2)) - int(st.get("days", 0))), "from": str(st.get("from", ""))})
	return out


## Событие босса (по полю wander) — его ли это.
static func is_wander(content: Content, mid: String) -> bool:
	return str(content.missions.get(mid, {}).get("wander", "")) != ""


## Можно ли боссу встать на место: открыто, не у фигуры, без других событий, не сюжет и не путь к нему, не вода.
static func haunt_ok(content: Content, state: RunState, lid: String, route: Array = []) -> bool:
	if lid == state.party_at or not content.locations.has(lid) or not MapRules.present(content, state, lid):
		return false
	if not MapRules.revealed(content, state, lid):
		return false
	if TideRules.flooded(state, lid) or TideRules.threatened(state, lid) or GateRules.blocked(state, lid) \
			or TerrainRules.blocked(content, state, lid):
		return false
	if route.has(lid):
		return false
	for mid: String in MissionFlow.open_missions(state):
		if str(content.missions.get(mid, {}).get("location", "")) == lid and not is_wander(content, mid):
			return false
	return true


## Места на пути фигуры к открытым сюжетным событиям главы (и сами места сюжета) — туда босс не встаёт.
static func story_route(content: Content, state: RunState) -> Array:
	var out: Array = []
	for mid: String in MissionFlow.open_missions(state):
		var m: Dictionary = content.missions.get(mid, {})
		if str(m.get("type", "")) != "story" or MissionFlow.chapter_of(content, mid) != state.chapter:
			continue
		var lid := str(m.get("location", ""))
		out.append(lid)
		out.append_array(TravelRules.route(content, state, state.party_at, lid, false))
	return out


## Ночь: босс появляется, стоит или уходит на новое место; побеждённый — уходит из главы. Записи для окна ночи.
static func night(content: Content, state: RunState, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	if not DayRules.restricted(content, state):
		return out
	var all := _st(state)
	var route := story_route(content, state)
	for w: Dictionary in defs(content, state.chapter):
		var wid := str(w["id"])
		var st: Dictionary = all.get(wid, {})
		if bool(st.get("done", false)):
			continue
		var mid := str(st.get("mid", ""))
		if mid != "" and str(state.missions.get(mid, {}).get("status", "")) == "done":
			st["done"] = true
			st["at"] = ""
			all[wid] = st
			continue
		if mid != "" and state.squads.any(func(q: Dictionary) -> bool: return str(q["mission"]) == mid):
			continue   # бой идёт — босс на месте
		if mid == "":
			if state.day < int(w.get("appear_day", 3)):
				continue
			var lid := _pick(content, state, w, "", route, rng)
			if lid == "":
				continue
			_place(content, state, w, st, lid, "", rng)
			all[wid] = st
			out.append({"kind": "wander", "text": "По карте бродит %s — %s: %s" % [w["name"], w.get("stop", "встал"), _name(content, lid)]})
			continue
		var at := str(st.get("at", ""))
		var open := str(state.missions.get(mid, {}).get("status", "")) in ["open", "active"]   # смыло водой — уходит
		if at == state.party_at and open:
			continue   # фигура пришла к боссу — он ждёт
		st["days"] = int(st.get("days", 0)) + 1
		var stay_ok := open and haunt_ok(content, state, at, route)
		if int(st["days"]) < int(st.get("rest", 2)) and stay_ok:
			all[wid] = st
			continue
		var next := _pick(content, state, w, at, route, rng)
		if next == "":
			all[wid] = st
			continue
		state.missions.erase(mid)   # событие на старом месте уходит вместе с боссом
		_place(content, state, w, st, next, at, rng)
		all[wid] = st
		out.append({"kind": "wander", "text": "%s ушёл дальше: %s → %s" % [w["name"], _name(content, at), _name(content, next)]})
	return out


## Новое место: из своих мест, где можно встать; сначала — недалеко (до трёх переходов) от прежнего.
static func _pick(content: Content, state: RunState, w: Dictionary, from: String, route: Array, rng: RandomNumberGenerator) -> String:
	var ok: Array = Array(w.get("haunts", [])).filter(func(l: String) -> bool:
		return l != from and haunt_ok(content, state, l, route))
	if ok.is_empty():
		return ""
	if from != "":
		var dist := TravelRules.distances(content, state, from, false)
		var near := ok.filter(func(l: String) -> bool: return dist.has(l) and int(dist[l]) <= 3)
		if not near.is_empty():
			ok = near
	ok.sort()
	return str(ok[rng.randi() % ok.size()])


static func _place(content: Content, state: RunState, w: Dictionary, st: Dictionary, lid: String, from: String,
		rng: RandomNumberGenerator) -> void:
	var mid := "%s_%s" % [w["id"], lid]
	MissionFlow.open(content, state, mid, true)
	var r: Array = w.get("rest", [2, 3])
	st["at"] = lid
	st["mid"] = mid
	st["days"] = 0
	st["rest"] = rng.randi_range(int(r[0]), int(r[1]))
	st["from"] = from


static func _name(content: Content, lid: String) -> String:
	return str(content.locations.get(lid, {}).get("name", lid))
