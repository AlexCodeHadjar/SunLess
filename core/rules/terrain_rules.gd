class_name TerrainRules
extends RefCounted
## Местность карты-плана (docs «Глава 4 — Путь к Мрачному городу и Мрачный город»). Настройки — data/maps/<регион>.json:
## - path_sets {sets: [[пары троп]…]} — сети троп, которые меняет буря (storm_phase): тропы Пепельного моря
##   открываются и закрываются; в бурю у variants новый облик, засыпанные котловины уходят, открытое пеплом
##   снова скрыто (кроме соседей лагеря), ночь в открытом пепле (exposed) — «засыпало».
## - emerge_groups {группа: {sockets: [номера площадок], phase, day_in, count [от, до], sink_after}} — где и когда
##   поднимаются новые места: котловины после бури, островки Чёрной воды на Рассвете; у мест — socket_group.
## - fragile {место: {crossings, storm, warn}} — хрупкий проход (Мост над Бездной): после N переходов трескается,
##   затем рушится (место непроходимо); в бурю рушится сразу.
## - risky [{pair, name, req, tags}] — опасный проход (спуск у Края Бездны): проверка лучшего героя, провал — грань.
## - water_paths [пары], water_phases — водные тропы: только с лодкой (флаг boat) и только в эти фазы.
## - phase_states {место: {фаза: облик}} — облик по фазе недели (Древо светится ночью, ворота замка закрыты).
## - rubble {R1: {at, pair}} — завалы Мрачного города: обвал закрывает тропу, расчистка открывает (команда terrain).
## У лагеря поле tribute — дань за ночь (Светлый замок); не заплатили — ночь у tribute_fallback.
## Состояние: state.flags — path_set, crossed {место: n}, terrain {место: облик}, rubble {R: blocked}, boat.


static func cfg(content: Content, state: RunState) -> Dictionary:
	return MapRules.config(content, state.chapter)


static func terrain(state: RunState) -> Dictionary:
	return Dictionary(state.flags.get("terrain", {}))


## Облик места от местности ("" — нет): обрушен/треснул мост, облик по фазе недели.
static func state_of(content: Content, state: RunState, lid: String, have: Array) -> String:
	var st := str(terrain(state).get(lid, ""))
	if st != "" and have.has(st):
		return st
	var ph := str(DayRules.phase(content, state).get("id", ""))
	var ps: String = str(cfg(content, state).get("phase_states", {}).get(lid, {}).get(ph, ""))
	return ps if have.has(ps) else ""


## Место непроходимо: хрупкий проход обрушен.
static func blocked(content: Content, state: RunState, lid: String) -> bool:
	return str(terrain(state).get(lid, "")) == "collapsed"


## Тропы сверх постоянных: текущая сеть бури и водные тропы; без заваленных.
static func extra_paths(content: Content, state: RunState) -> Array:
	var c := cfg(content, state)
	var out: Array = []
	var sets: Array = c.get("path_sets", {}).get("sets", [])
	if not sets.is_empty():
		out.append_array(Array(sets[posmod(int(state.flags.get("path_set", 0)), sets.size())]))
	out.append_array(Array(c.get("water_paths", [])))
	return out


## Тропа открыта (не завалена обвалом).
static func path_open(content: Content, state: RunState, a: String, b: String) -> bool:
	var rb: Dictionary = cfg(content, state).get("rubble", {})
	var st: Dictionary = state.flags.get("rubble", {})
	for rid: String in rb:
		var pr: Array = rb[rid].get("pair", [])
		if pr.size() == 2 and ((pr[0] == a and pr[1] == b) or (pr[0] == b and pr[1] == a)) and str(st.get(rid, "")) == "blocked":
			return false
	return true


static func _is_water(content: Content, state: RunState, a: String, b: String) -> bool:
	for pr: Array in cfg(content, state).get("water_paths", []):
		if (pr[0] == a and pr[1] == b) or (pr[0] == b and pr[1] == a):
			return true
	return false


## По тропе можно пройти сейчас: водная — только с лодкой и в свои фазы.
static func edge_ok(content: Content, state: RunState, a: String, b: String) -> bool:
	if not _is_water(content, state, a, b):
		return true
	if not bool(state.flags.get("boat", false)):
		return false
	var phases: Array = cfg(content, state).get("water_phases", ["night"])
	return phases.is_empty() or phases.has(str(DayRules.phase(content, state).get("id", "")))


## Почему по тропе не пройти (для окна перехода): "" — можно.
static func edge_why(content: Content, state: RunState, a: String, b: String) -> String:
	if not _is_water(content, state, a, b):
		return ""
	if not bool(state.flags.get("boat", false)):
		return "По Чёрной воде — только на лодке"
	return "" if edge_ok(content, state, a, b) else "По Чёрной воде — только ночью"


## Отряд прошёл маршрут: хрупкий проход трескается/рушится, опасный спуск — проверка, зона гнева — психика.
static func on_travel(content: Content, state: RunState, path: Array, from: String, out: Array) -> void:
	var c := cfg(content, state)
	var frag: Dictionary = c.get("fragile", {})
	var crossed: Dictionary = Dictionary(state.flags.get("crossed", {})).duplicate()
	var prev := from
	var rng := RandomNumberGenerator.new()
	rng.seed = state.rng_seed + 6007 * state.day + int(state.clock * 10.0)
	for p: String in path:
		if frag.has(p):
			crossed[p] = int(crossed.get(p, 0)) + 1
			_wear_out(content, state, p, int(crossed[p]), out)
		for rk: Dictionary in c.get("risky", []):
			var pr: Array = rk.get("pair", [])
			if (pr[0] == prev and pr[1] == p) or (pr[1] == prev and pr[0] == p):
				out.append_array(_ordeal(content, state, rk, rng))
		prev = p
	state.flags["crossed"] = crossed
	var zc := ZoneRules.pass_cost(content, state, path)
	if zc < 0:
		for cid: String in MissionFlow.heroes(content, state):
			out.append_array(PsycheRules.change(content, state, cid, zc, "гнев Владыки", [], null, "mission", false))


static func _wear_out(content: Content, state: RunState, lid: String, n: int, out: Array) -> void:
	var f: Dictionary = cfg(content, state).get("fragile", {}).get(lid, {})
	var limit := int(f.get("crossings", 4))
	var t := terrain(state).duplicate()
	if n >= limit:
		t[lid] = "collapsed"
		out.append({"kind": "terrain", "text": "%s рушится за спиной отряда" % _name(content, lid)})
	elif n >= limit - 1:
		t[lid] = str(f.get("warn", "cracked"))
		out.append({"kind": "terrain", "text": "%s трещит — выдержит ещё один переход" % _name(content, lid)})
	state.flags["terrain"] = t


static func _ordeal(content: Content, state: RunState, rk: Dictionary, rng: RandomNumberGenerator) -> Array:
	var heroes := MissionFlow.heroes(content, state)
	if heroes.is_empty():
		return []
	var st := {"name": str(rk.get("name", "Опасный проход")), "req": rk.get("req", {"power": 7}), "tags": rk.get("tags", ["climb"])}
	var best := MissionForecast.stage_actor(content, state, {}, {}, st, heroes)
	var ok := rng.randi_range(1, 100) <= int(best.get("chance", 50))
	var entries: Array = []
	if not ok:
		var victim: String = heroes[rng.randi_range(0, heroes.size() - 1)]
		EdgeRules.defeat(content, state, victim, MissionFlow.pocket(state, victim), rng, {}, entries)
	var out: Array = [{"kind": "terrain", "ok": ok, "text": "%s — %s" % [str(st["name"]), "прошли" if ok else "сорвались"]}]
	out.append_array(entries)
	return out


static func _name(content: Content, lid: String) -> String:
	return str(content.locations.get(lid, {}).get("name", lid))


# --- ночь ---------------------------------------------------------------------------------------------------

## Дань за ночь в лагере с tribute (Светлый замок): не хватает осколков — ночь у ворот.
static func tribute(content: Content, state: RunState, out: Array) -> void:
	var camp := DayRules.camp_at(content, state.party_at)
	var t := int(camp.get("tribute", 0))
	if t <= 0:
		return
	var have := int(state.resources.get("shards", 0))
	if have >= t:
		state.resources["shards"] = have - t
		out.append({"kind": "terrain", "text": "Дань за ночь в замке: −%d %s" % [t, "осколка" if t < 5 else "осколков"]})
	else:
		var fb := str(cfg(content, state).get("tribute_fallback", ""))
		if fb != "":
			state.party_at = fb
		out.append({"kind": "terrain", "text": "Нечем платить дань — стража выставила отряд за ворота: ночь в руинах"})


## Утро после ночи (новый день уже наступил): буря меняет тропы и засыпает котловины, на Рассвете — островки.
static func morning(content: Content, state: RunState, rng: RandomNumberGenerator, yesterday: Dictionary) -> Array:
	var out: Array = []
	var c := cfg(content, state)
	var today := DayRules.phase(content, state)
	var ph := str(today.get("id", ""))
	var storm := str(c.get("path_sets", {}).get("storm_phase", ""))
	if storm != "" and ph == storm and int(today.get("day_in", 1)) == 1:
		out.append_array(_storm(content, state, rng))
	# площадки: поднять новые места в свою фазу, утопить/засыпать в конце
	for g: String in MissionFlow._sorted(c.get("emerge_groups", {})):
		var eg: Dictionary = c["emerge_groups"][g]
		if str(eg.get("sink_after", "")) == str(yesterday.get("id", "")) and ph != str(yesterday.get("id", "")):
			out.append_array(_sink_group(content, state, g))
		if ph == str(eg.get("phase", "")) and int(today.get("day_in", 1)) == int(eg.get("day_in", 1)):
			var r: Array = eg.get("count", [1, 2])
			out.append_array(_emerge_group(content, state, g, rng.randi_range(int(r[0]), int(r[1])), rng))
	# обвалы: в шторм — один случайный завал
	var rb: Dictionary = c.get("rubble", {})
	if not rb.is_empty() and ph == str(c.get("rubble_phase", "storm")) and int(today.get("day_in", 1)) == 1:
		var keys: Array = MissionFlow._sorted(rb)
		var rid: String = keys[rng.randi_range(0, keys.size() - 1)]
		var st: Dictionary = Dictionary(state.flags.get("rubble", {})).duplicate()
		st[rid] = "open" if str(st.get(rid, "")) == "blocked" else "blocked"
		state.flags["rubble"] = st
		out.append({"kind": "terrain", "text": "Обвал в руинах: %s" % ("проход завален" if st[rid] == "blocked" else "завал пробит — новый лаз")})
	return out


## Ночь в открытом пепле в бурю — «засыпало»: психика и вещи.
static func exposed_night(content: Content, state: RunState, out: Array) -> void:
	var c := cfg(content, state)
	var storm := str(c.get("path_sets", {}).get("storm_phase", ""))
	if storm == "" or str(DayRules.phase(content, state).get("id", "")) != storm:
		return
	if not Array(c.get("exposed", [])).has(state.party_at):
		return
	for cid: String in MissionFlow.heroes(content, state):
		out.append_array(PsycheRules.change(content, state, cid, -6, "засыпало пеплом", [], null, "mission", false))
		for card: String in MissionFlow.pocket(state, cid):
			if WearRules.wears(content, state, card):
				state.wear[card] = mini(100, WearRules.current(state, card) + 5)
	out.append({"kind": "terrain", "text": "Ночь в открытом пепле — лагерь засыпало"})


static func _storm(content: Content, state: RunState, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var c := cfg(content, state)
	var sets: Array = c.get("path_sets", {}).get("sets", [])
	if not sets.is_empty():
		state.flags["path_set"] = posmod(int(state.flags.get("path_set", 0)) + 1, sets.size())
	# дюны сдвигаются: новый облик проходов
	var variants: Dictionary = Dictionary(state.tide.get("variant", {})).duplicate()
	for lid: String in c.get("variants", {}):
		var vs: Array = c["variants"][lid]
		var cur := str(variants.get(lid, "dry"))
		var others: Array = vs.filter(func(v: String) -> bool: return v != cur)
		if not others.is_empty():
			variants[lid] = others[rng.randi_range(0, others.size() - 1)]
	state.tide["variant"] = variants
	# хрупкие проходы с storm=true рушатся
	var t := terrain(state).duplicate()
	for lid: String in c.get("fragile", {}):
		if bool(c["fragile"][lid].get("storm", false)) and str(t.get(lid, "")) != "collapsed":
			t[lid] = "collapsed"
			out.append({"kind": "terrain", "text": "Буря обрушила %s" % _name(content, lid)})
	state.flags["terrain"] = t
	# пепел прячет открытое (кроме лагеря и соседей)
	var keep := {state.party_at: true}
	for n: String in MapRules.neighbors(content, state, state.party_at):
		keep[n] = true
	for key: String in ["visited", "scouted"]:
		var v: Array = state.flags.get(key, [])
		state.flags[key] = v.filter(func(l: String) -> bool: return keep.has(l) or not Array(c.get("exposed", [])).has(l))
	out.append({"kind": "terrain", "text": "Пепельная буря: дюны сдвинулись, тропы Пепельного моря другие"})
	return out


static func _emerge_group(content: Content, state: RunState, g: String, n: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var pool: Array = []
	for lid: String in MissionFlow._sorted(content.locations):
		var loc: Dictionary = content.locations[lid]
		if str(loc.get("chapter", "")) == state.chapter and str(loc.get("socket_group", "")) == g and not MapRules.emerged(state).has(lid):
			pool.append(lid)
	for i in n:
		if pool.is_empty():
			break
		var lid: String = pool[rng.randi_range(0, pool.size() - 1)]
		pool.erase(lid)
		out.append_array(MapRules.emerge(content, state, lid, rng))
	return out


static func _sink_group(content: Content, state: RunState, g: String) -> Array:
	var em := MapRules.emerged(state).duplicate()
	var gone: Array = []
	for lid: String in em.keys():
		if str(content.locations.get(lid, {}).get("socket_group", "")) == g and lid != state.party_at:
			em.erase(lid)
			gone.append(str(content.locations[lid].get("name", lid)))
	state.tide["emerged"] = em
	if gone.is_empty():
		return []
	return [{"kind": "terrain", "text": "Скрылись: %s" % ", ".join(gone)}]


## {cmd: terrain, do: collapse|clear|repair|set, place?, rubble?, state?}
static func command(content: Content, state: RunState, e: Dictionary) -> Array:
	match str(e.get("do", "")):
		"collapse", "clear":
			var st: Dictionary = Dictionary(state.flags.get("rubble", {})).duplicate()
			st[str(e.get("rubble", ""))] = "blocked" if str(e["do"]) == "collapse" else "open"
			state.flags["rubble"] = st
			return [{"kind": "terrain", "text": "Завал %s" % ("рухнул — проход закрыт" if str(e["do"]) == "collapse" else "расчищен — проход открыт")}]
		"set":
			var t := terrain(state).duplicate()
			var lid := str(e.get("place", ""))
			if str(e.get("state", "")) == "":
				t.erase(lid)
			else:
				t[lid] = str(e["state"])
			state.flags["terrain"] = t
			return []
	return []


static func reset(state: RunState) -> void:
	for k: String in ["path_set", "crossed", "terrain", "rubble", "boat"]:
		state.flags.erase(k)
