class_name MoverRules
extends RefCounted
## Подвижные угрозы карты-плана (docs «Глава 4 — Путь к Мрачному городу и Мрачный город»): Демон Карапакса идёт
## по следу отряда, тень гиганта ходит по Чёрной воде, ночные охотники Мрачного города идут на шум, живые статуи
## переходят между площадями. Настройки — data/maps/<регион>.json → movers {id: {name, start, target (camp|noise|patrol),
## patrol [места], phases [фазы, когда ходит], step (шагов за ночь), active (с начала главы), hunt {req, tags, psyche,
## edge}, clash {zone, text} (в этой зоне угроза ранена и отступает)}}.
## Каждую ночь (DayRules.end_day) угроза делает шаг по тропам к цели; пришла к лагерю — ночное испытание отряда.
## Огонь (команда mover_lure: Маяк смерти) тянет угрозу к себе, а не к лагерю. Не видно места — видны следы на тропе.
## Состояние: state.flags.movers {id: {at, from, lure, lure_left, wounded, dead, idx}}, flags.noise [места боёв за день].


static func cfg(content: Content, state: RunState) -> Dictionary:
	return Dictionary(MapRules.config(content, state.chapter).get("movers", {}))


static func movers(state: RunState) -> Dictionary:
	return Dictionary(state.flags.get("movers", {}))


static func at(state: RunState, mid: String) -> String:
	return str(movers(state).get(mid, {}).get("at", ""))


static func active(state: RunState, mid: String) -> bool:
	var m: Dictionary = movers(state).get(mid, {})
	return not m.is_empty() and not bool(m.get("dead", false))


static func name_of(content: Content, state: RunState, mid: String) -> String:
	return str(cfg(content, state).get(mid, {}).get("name", mid))


## Начало главы: угрозы с active=true встают на старт.
static func reset(content: Content, state: RunState) -> void:
	var out := {}
	var c := cfg(content, state)
	for mid: String in c:
		if bool(c[mid].get("active", false)):
			out[mid] = {"at": str(c[mid].get("start", "")), "from": ""}
	state.flags["movers"] = out
	state.flags.erase("noise")


## Отряд дрался здесь сегодня — охотники ночью придут на шум.
static func noise(state: RunState, lid: String) -> void:
	var n: Array = state.flags.get("noise", [])
	if not n.has(lid):
		n.append(lid)
	state.flags["noise"] = n


## Угрозы в месте (для лагеря и брифинга).
static func here(state: RunState, lid: String) -> Array:
	var out: Array = []
	for mid: String in movers(state):
		if active(state, mid) and at(state, mid) == lid:
			out.append(mid)
	return out


# --- ночь ---------------------------------------------------------------------------------------------

static func night(content: Content, state: RunState, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var c := cfg(content, state)
	if c.is_empty():
		return out
	var ph := str(DayRules.phase(content, state).get("id", ""))
	var all := movers(state).duplicate(true)
	for mid: String in MissionFlow._sorted(all):
		var m: Dictionary = all[mid]
		var d: Dictionary = c.get(mid, {})
		if bool(m.get("dead", false)):
			continue
		var phases: Array = d.get("phases", [])
		if not phases.is_empty() and not phases.has(ph):
			continue
		for i in int(d.get("step", 1)):
			var nxt := _next(content, state, mid, m, d)
			if nxt == "" or nxt == str(m.get("at", "")):
				break
			m["from"] = str(m.get("at", ""))
			m["at"] = nxt
			# сцепилась с хозяином зоны (Демон у Владыки Пепла) — ранена и отступает
			var clash: Dictionary = d.get("clash", {})
			if not clash.is_empty() and ZoneRules.in_zone(content, state, str(clash.get("zone", "")), nxt) and not bool(m.get("wounded", false)):
				m["wounded"] = true
				m["at"] = str(m["from"])
				out.append({"kind": "mover", "text": str(clash.get("text", "%s сцепился с хозяином зоны — ранен и отступил" % name_of(content, state, mid)))})
				break
		if int(m.get("lure_left", 0)) > 0:
			m["lure_left"] = int(m["lure_left"]) - 1
		all[mid] = m
	state.flags["movers"] = all
	state.flags.erase("noise")
	# пришли к лагерю — ночное испытание
	for mid: String in MissionFlow._sorted(all):
		if active(state, mid) and at(state, mid) == state.party_at and not c.get(mid, {}).get("hunt", {}).is_empty():
			out.append_array(_hunt(content, state, mid, rng))
	return out


## Куда шаг: к огню (приманка), к лагерю, на шум или по кругу патруля.
static func _next(content: Content, state: RunState, mid: String, m: Dictionary, d: Dictionary) -> String:
	var here_at := str(m.get("at", ""))
	var goal := ""
	if int(m.get("lure_left", 0)) > 0 and str(m.get("lure", "")) != "":
		goal = str(m["lure"])
	else:
		match str(d.get("target", "camp")):
			"camp":
				goal = state.party_at
			"noise":
				var n: Array = state.flags.get("noise", [])
				goal = str(n.back()) if not n.is_empty() else ""
				if goal == "":
					goal = _patrol_next(m, d)
			"patrol":
				goal = _patrol_next(m, d)
	if goal == "" or goal == here_at:
		return here_at
	var r := TravelRules.route(content, state, here_at, goal, false)
	if r.is_empty():
		return here_at
	return str(r[0]) if content.locations.has(str(r[0])) or r.size() == 1 else str(r[1])


static func _patrol_next(m: Dictionary, d: Dictionary) -> String:
	var pat: Array = d.get("patrol", [])
	if pat.is_empty():
		return ""
	var i := (int(m.get("idx", -1)) + 1) % pat.size()
	if str(m.get("at", "")) == str(pat[i % pat.size()]):
		i = (i + 1) % pat.size()
	m["idx"] = i
	return str(pat[i])


## Угроза у лагеря ночью: лучший герой — проверка; провал — один на грань, психика всем; угроза отступает на шаг.
static func _hunt(content: Content, state: RunState, mid: String, rng: RandomNumberGenerator) -> Array:
	var d: Dictionary = cfg(content, state).get(mid, {})
	var h: Dictionary = d.get("hunt", {})
	var heroes := MissionFlow.heroes(content, state)
	if heroes.is_empty():
		return []
	var req: Dictionary = h.get("req", {"power": 8})
	if bool(movers(state).get(mid, {}).get("wounded", false)):
		var easier := {}
		for k: String in req:
			easier[k] = maxi(1, int(req[k]) - 2)   # раненая угроза слабее
		req = easier
	var st := {"name": name_of(content, state, mid), "req": req, "tags": h.get("tags", ["combat"])}
	var best := MissionForecast.stage_actor(content, state, {}, {}, st, heroes)
	var ok := rng.randi_range(1, 100) <= int(best.get("chance", 50))
	var entries: Array = []
	for cid: String in heroes:
		entries.append_array(PsycheRules.change(content, state, cid, int(h.get("ok_psyche", -5)) if ok else int(h.get("psyche", -12)),
			name_of(content, state, mid).to_lower(), heroes, rng, "mission", false))
	if not ok and bool(h.get("edge", true)):
		var victim: String = heroes[rng.randi_range(0, heroes.size() - 1)]
		EdgeRules.defeat(content, state, victim, MissionFlow.pocket(state, victim), rng, {}, entries)
	# отбились или нет — угроза отходит туда, откуда пришла
	var all := movers(state).duplicate(true)
	if all.has(mid) and str(all[mid].get("from", "")) != "":
		all[mid]["at"] = str(all[mid]["from"])
	state.flags["movers"] = all
	var out: Array = [{"kind": "mover", "ok": ok, "text": "%s у лагеря ночью — %s" % [name_of(content, state, mid), "отбились" if ok else "не все целы"], "entries": entries}]
	out.append_array(entries)
	return out


# --- команды ------------------------------------------------------------------------------------------

## {cmd: mover, do: spawn|lure|kill|scatter, mover, place?, days?}
static func command(content: Content, state: RunState, e: Dictionary) -> Array:
	var mid := str(e.get("mover", ""))
	var all := movers(state).duplicate(true)
	var d: Dictionary = cfg(content, state).get(mid, {})
	match str(e.get("do", "")):
		"spawn":
			all[mid] = {"at": str(e.get("place", d.get("start", ""))), "from": ""}
			state.flags["movers"] = all
			return [{"kind": "mover", "text": "%s идёт по следу отряда" % name_of(content, state, mid)}]
		"lure":
			for m2: String in all:
				if mid == "" or m2 == mid:
					all[m2]["lure"] = str(e.get("place", ""))
					all[m2]["lure_left"] = int(e.get("days", 3))
			state.flags["movers"] = all
			return [{"kind": "mover", "text": "Огонь горит — угрозы идут к нему, а не к лагерю"}]
		"kill":
			if all.has(mid):
				all[mid]["dead"] = true
				state.flags["movers"] = all
				return [{"kind": "mover", "text": "%s повержен" % name_of(content, state, mid)}]
		"scatter":
			if all.has(mid):
				all[mid]["from"] = str(all[mid].get("at", ""))
				all[mid]["at"] = str(d.get("start", all[mid].get("at", "")))
				state.flags["movers"] = all
				return [{"kind": "mover", "text": "%s сбит со следа" % name_of(content, state, mid)}]
	return []
