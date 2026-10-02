class_name MapStory
extends RefCounted
## Почему место на карте-плане выглядит так (для коллажей «как меняется карта»: tools/map_coverage.gd,
## tools/mission_shots.gd --mshots-from=timeline). Повторяет порядок MapRules.place_state и называет причину.

const SITE := {"alarm": "тревога", "fight": "бой", "damaged": "повреждён", "ruined": "разрушен", "burning": "горит",
	"barricaded": "баррикада", "repair": "ремонт", "lockdown": "ставни", "leak": "утечка", "breached": "прорыв", "crowded": "переполнен",
	"overcrowded": "переполнен", "closed": "закрыт", "collapsed": "обрушен", "evac": "эвакуация", "sealed": "запечатан", "burned": "выгорел"}


## Причина облика st у места lid ("" — обычный облик).
static func why(c: Content, s: RunState, lid: String, st: String) -> String:
	if st == "" or st == "dry":
		return ""
	var have := MapRules.states(c, s, lid)
	if st == "flooded" and TideRules.flooded(s, lid):
		return "вода: %s" % ("шторм недели" if str(s.tide.get("source", "")) != "story" else "сюжетный прилив")
	if GateRules.visible_state(s, lid, have) == st:
		var ss := GateRules.site_state(s, lid)
		return "%s: %s" % ["прорыв" if GateRules.kind(c, s) == "breach" else "Врата и волна", SITE.get(ss, ss)]
	if TerrainRules.state_of(c, s, lid, have) == st:
		if str(TerrainRules.terrain(s).get(lid, "")) == st:
			return "переходы по мосту" if st == "cracked" else "мост рухнул (переходы или сюжет)"
		return "фаза недели: %s" % str(DayRules.phase(c, s).get("name", ""))
	var mark: Dictionary = Dictionary(s.tide.get("marks", {})).get(lid, {})
	if str(mark.get("state", "")) == st:
		var t := _mark_mission(c, s, lid, st)
		return "след миссии" + (" «%s»" % t if t != "" else "")
	if st == "silt":
		return "ил после отлива"
	if st == "storm":
		return "небо: шторм"
	return "отлив или буря перестроили проход"


## Какая выполненная миссия оставила след map_mark на месте.
static func _mark_mission(c: Content, s: RunState, lid: String, st: String) -> String:
	for mid: String in MissionFlow._sorted(s.missions):
		if str(s.missions[mid].get("status", "")) != "done":
			continue
		var m: Dictionary = c.missions.get(mid, {})
		for a: Dictionary in m.get("actions", []):
			for key: String in ["on_success", "on_partial", "on_failure"]:
				for e: Dictionary in a.get(key, []):
					if str(e.get("cmd", "")) == "map_mark" and str(e.get("place", "")) == lid and str(e.get("state", "")) == st:
						return str(m.get("title", mid))
	return ""


## Снимок карты: облик каждого места с причиной, вода, новые места, угрозы, зоны, подвижные угрозы.
static func snapshot(c: Content, s: RunState) -> Dictionary:
	var sky := Atmosphere.sky(c, s)
	var cfg := MapRules.config(c, s.chapter)
	var places := {}
	var kn := MapRules.known(c, s)
	for lid: String in cfg.get("places", {}):
		if not MapRules.present(c, s, lid) or MapRules.states(c, s, lid).is_empty():
			continue
		var st := MapRules.place_state(c, s, lid, sky)
		places[lid] = {"state": st, "why": why(c, s, lid, st), "known": kn.has(lid) or c.shops.has(lid),
			"name": str(c.locations.get(lid, c.shops.get(lid, {})).get("name", lid))}
	var gates := {}
	if GateRules.active(c, s):
		for pid: String in GateRules.points(s):
			gates[pid] = GateRules.stage(s, pid)
	var zones := {}
	for zid: String in ZoneRules.cfg(c, s):
		if ZoneRules.radius(c, s, zid) >= 0:
			zones[zid] = ZoneRules.places(c, s, zid).size()
	var movers := {}
	for mid: String in MoverRules.movers(s):
		if MoverRules.active(s, mid):
			movers[mid] = MoverRules.at(s, mid)
	return {"chapter": s.chapter, "day": s.day, "phase": str(DayRules.phase(c, s).get("name", "")), "sky": sky,
		"party_at": s.party_at, "places": places, "emerged": MapRules.emerged(s).keys(),
		"flooded": Array(s.tide.get("places", [])) if TideRules.phase(s) == "flood" else [],
		"gates": gates, "swarms": GateRules.swarms(s).size() if GateRules.active(c, s) else 0, "panic": GateRules.panic(s),
		"zones": zones, "movers": movers, "path_set": int(s.flags.get("path_set", 0)), "boat": bool(s.flags.get("boat", false)),
		"rubble": Dictionary(s.flags.get("rubble", {})).keys().filter(func(r: String) -> bool: return str(s.flags["rubble"][r]) == "blocked"),
		"known": kn.size(), "done": s.missions.keys().filter(func(m: String) -> bool: return str(s.missions[m].get("status", "")) == "done").size()}


## Начало главы для прогонов: Берег и Академия — как в тестах, черновики — с отрядом региона.
static func start(c: Content, chapter: String, seed_value: int) -> RunState:
	if chapter in ["shore", "academy"]:
		return MissionFlow.new_run(c, seed_value, chapter)
	return AutoPlay.draft_start(c, chapter, seed_value)
