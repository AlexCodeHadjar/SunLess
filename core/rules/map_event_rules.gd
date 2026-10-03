class_name MapEventRules
extends RefCounted
## Следы событий на карте-плане (docs «Забытый Берег — локации и текстуры для событий», комплекты событий Берега
## и Главы 4): по ним видно, что где случилось или ждёт. Всё — из data/maps/<регион>.json, без своих правил игры:
## - event_states [{place, state, phase?, from_day?, day_in?, camp?}] — облик места: в фазу недели (кровавый алтарь,
##   линька), с недели N (красный Шпиль), в первый день фазы (лабиринт горит после шторма), пока здесь лагерь (костёр
##   у статуи, сигнальный огонь на Высоте);
## - place_decals [{decal, place|camp, phase?, from_day?, open?, variant? [место, облик], flag?, lure?, fog?, height?}]
##   — метка у места; path_decals [{decal, path [a, b] | to (место), phase?, variant?, flag?}] — полоса на тропе;
## - mod_decals {модификатор: метка} — у места открытой встречи с этим модификатором (туман, тайник, проклятие…);
## - следы на дни (state.flags.decals): отступили — брошенное снаряжение, погибли — павшие и Могилы Спящих рядом,
##   ночное нападение — метка охотника и следы когтей у лагеря, после шторма — сундук и опалённый коралл;
## - haze (дымка в Кровавую луну), edge_glow (отсвет Шпиля с северо-запада, с недели 2).


static func cfg(content: Content, state: RunState) -> Dictionary:
	return MapRules.config(content, state.chapter)


static func _when(content: Content, state: RunState, d: Dictionary) -> bool:
	var ph := DayRules.phase(content, state)
	if d.has("phase") and not Array(d["phase"]).has(str(ph.get("id", ""))):
		return false
	if state.day < int(d.get("from_day", 0)):
		return false
	if d.has("day_in") and int(ph.get("day_in", 1)) != int(d["day_in"]):
		return false
	if d.has("flag") and not bool(state.flags.get(str(d["flag"]), false)):
		return false
	if d.has("variant"):
		var v: Array = d["variant"]
		if str(Dictionary(state.tide.get("variant", {})).get(str(v[0]), "dry")) != str(v[1]):
			return false
	return true


## Облик места от событий ("" — нет): фаза недели, неделя, лагерь здесь.
static func state_of(content: Content, state: RunState, lid: String, have: Array) -> String:
	for d: Dictionary in cfg(content, state).get("event_states", []):
		if str(d.get("place", "")) != lid or not have.has(str(d.get("state", ""))):
			continue
		if bool(d.get("camp", false)) and state.party_at != lid:
			continue
		if _when(content, state, d):
			return str(d["state"])
	return ""


## Метки сейчас: [{decal, place} | {decal, path [a, b]} | {decal, place, fog: true}] — рисует SleeperMap.
static func decals(content: Content, state: RunState) -> Array:
	var c := cfg(content, state)
	var out: Array = []
	if c.is_empty():
		return out
	for d: Dictionary in c.get("place_decals", []):
		var lid := state.party_at if bool(d.get("camp", false)) else str(d.get("place", ""))
		if not MapRules.present(content, state, lid) or not _when(content, state, d):
			continue
		if d.has("height") and not Array(d["height"]).has(TideRules.height(content, lid)):
			continue
		if d.has("open") and not _open_at(content, state, lid):
			continue
		if d.has("lure") and not _lured(state, str(d["lure"]), lid):
			continue
		out.append({"decal": str(d["decal"]), "place": lid, "fog": bool(d.get("fog", false))})
	for d: Dictionary in c.get("path_decals", []):
		if not _when(content, state, d):
			continue
		var pr: Array = d.get("path", [])
		if d.has("to"):
			var to := str(d["to"])
			if not MapRules.present(content, state, to):
				continue
			var nb := MapRules.neighbors(content, state, to)
			if nb.is_empty():
				continue
			pr = [to, str(nb[0])]
		if pr.size() == 2 and MapRules.present(content, state, str(pr[0])) and MapRules.present(content, state, str(pr[1])):
			out.append({"decal": str(d["decal"]), "path": [str(pr[0]), str(pr[1])]})
	# модификаторы открытых встреч — метка у их места
	var md: Dictionary = c.get("mod_decals", {})
	if not md.is_empty():
		for mid: String in MissionFlow.open_missions(state):
			var lid := str(content.missions.get(mid, {}).get("location", ""))
			for mod: String in state.missions[mid].get("mods", []):
				if md.has(mod) and MapRules.present(content, state, lid):
					out.append({"decal": str(md[mod]), "place": lid})
	# следы на дни
	for e: Dictionary in state.flags.get("decals", []):
		if int(e.get("until", 0)) < state.day:
			continue
		if e.has("path"):
			out.append({"decal": str(e["decal"]), "path": e["path"]})
		elif MapRules.present(content, state, str(e.get("place", ""))):
			out.append({"decal": str(e["decal"]), "place": str(e["place"])})
	return out


static func _open_at(content: Content, state: RunState, lid: String) -> bool:
	return MissionFlow.open_missions(state).any(func(m: String) -> bool: return str(content.missions.get(m, {}).get("location", "")) == lid)


static func _lured(state: RunState, mover: String, lid: String) -> bool:
	var m: Dictionary = MoverRules.movers(state).get(mover, {})
	return int(m.get("lure_left", 0)) > 0 and str(m.get("lure", "")) == lid


## Положить след на N дней (у места или на тропе).
static func add(state: RunState, decal: String, place: String, days: int, path: Array = []) -> void:
	var lst: Array = Array(state.flags.get("decals", [])).filter(func(e: Dictionary) -> bool: return int(e.get("until", 0)) >= state.day)
	var e := {"decal": decal, "until": state.day + days - 1}
	if path.size() == 2:
		e["path"] = path
	else:
		e["place"] = place
	lst.append(e)
	state.flags["decals"] = lst


## Событие закончено: отступили — брошенное снаряжение; кто-то погиб — павшие и Могилы Спящих рядом.
static func after_mission(content: Content, state: RunState, mid: String, report: Dictionary, rng: RandomNumberGenerator) -> Array:
	var traces: Dictionary = cfg(content, state).get("traces", {})
	if traces.is_empty():
		return []
	var lid := str(content.missions.get(mid, {}).get("location", ""))
	if not MapRules.present(content, state, lid):
		return []
	var out: Array = []
	if str(report.get("outcome", "")) == "retreat" and traces.has("retreat"):
		add(state, str(traces["retreat"]), lid, 3)
	if not Array(report.get("deaths", [])).is_empty():
		if traces.has("death"):
			add(state, str(traces["death"]), lid, 4)
		var graves := str(traces.get("graves", ""))
		if graves != "" and content.locations.has(graves):
			out.append_array(MapRules.emerge(content, state, graves, rng, lid))
	return out


## Ночью на лагерь напали: метка охотника у стоянки и следы когтей на тропе к ней.
static func night_attack(content: Content, state: RunState) -> void:
	var traces: Dictionary = cfg(content, state).get("traces", {})
	if traces.has("attack"):
		add(state, str(traces["attack"]), state.party_at, 2)
	var nb := MapRules.neighbors(content, state, state.party_at)
	if traces.has("attack_path") and not nb.is_empty():
		add(state, str(traces["attack_path"]), "", 2, [str(nb[0]), state.party_at])


## Шторм прошёл: море выбросило сундук у низины, молния опалила место.
static func after_storm(content: Content, state: RunState, rng: RandomNumberGenerator) -> void:
	var traces: Dictionary = cfg(content, state).get("traces", {})
	var low: Array = []
	var any: Array = []
	for lid: String in cfg(content, state).get("places", {}):
		if not content.locations.has(lid) or not MapRules.present(content, state, lid):
			continue
		any.append(lid)
		if TideRules.height(content, lid) == "low":
			low.append(lid)
	if traces.has("storm_chest") and not low.is_empty():
		add(state, str(traces["storm_chest"]), str(low[rng.randi_range(0, low.size() - 1)]), 2)
	if traces.has("storm_scorch") and not any.is_empty():
		add(state, str(traces["storm_scorch"]), str(any[rng.randi_range(0, any.size() - 1)]), 2)


static func reset(state: RunState) -> void:
	state.flags.erase("decals")
