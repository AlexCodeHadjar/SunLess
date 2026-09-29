extends TestCase
## «Карта Спящего» (MapRules, docs/16 §11.6): места на своих точках, облик по состоянию, отлив — новые проходы,
## ил и новые места на площадках, следы набегов и шторма, туман неизвестного.


func _shore(seed_value: int = 5) -> RunState:
	return MissionFlow.new_run(content(), seed_value, "shore")


func _rng(v: int = 3) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = v
	return r


func test_config() -> void:
	var c := content()
	check(MapRules.has_map(c, "shore"), "у Берега есть карта-план")
	check(not MapRules.has_map(c, "nightmare"), "у Кошмара — прежняя панорама")
	var cfg := MapRules.config(c, "shore")
	eq(Array(cfg.get("sockets", [])).size(), 6, "шесть площадок ила:")
	for lid: String in c.locations:
		if str(c.locations[lid].get("chapter", "")) == "shore":
			check(cfg["places"].has(lid), "у места %s есть точка на карте" % lid)
	for lid: String in cfg["places"]:
		var a: Array = cfg["places"][lid].get("at", [0.5, 0.5])
		check(float(a[0]) > 0.0 and float(a[0]) < 1.0 and float(a[1]) > 0.0 and float(a[1]) < 1.0, "%s внутри основы" % lid)


func test_emerge() -> void:
	var c := content()
	var s := _shore()
	check(not MapRules.present(c, s, "leviathan_ribs"), "появляющегося места сначала нет")
	var ev := MapRules.emerge(c, s, "leviathan_ribs", _rng())
	check(MapRules.present(c, s, "leviathan_ribs"), "место поднялось")
	eq(str(s.missions.get("RS11", {}).get("status", "")), "open", "с ним — его встреча:")
	check(ev.any(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "emerge"), "событие появления")
	var sk: Array = MapRules.config(c, "shore")["sockets"][int(MapRules.emerged(s)["leviathan_ribs"])]
	eq(MapRules.anchor(c, s, "leviathan_ribs"), Vector2(float(sk[0]), float(sk[1])), "стоит на своей площадке:")
	eq(MapRules.emerge(c, s, "leviathan_ribs", _rng()), [], "второй раз не поднимается")
	for lid: String in ["sea_stair", "shell_field", "sunken_watch", "current_sink", "carapace_nest"]:
		MapRules.emerge(c, s, lid, _rng())
	var used := {}
	for lid: String in MapRules.emerged(s):
		check(not used.has(int(MapRules.emerged(s)[lid])), "одна площадка — одно место")
		used[int(MapRules.emerged(s)[lid])] = true
	eq(used.size(), 6, "заняты все шесть:")


func test_ebb_on_map() -> void:
	var c := content()
	var s := _shore(8)
	MapRules.emerge(c, s, "shell_field", _rng())
	TideRules.schedule(c, s, 1, 1)
	check(TideRules.places(s).has("shell_field"), "появившееся место тоже уйдёт под воду")
	check(not TideRules.places(s).has("leviathan_ribs"), "а того, что не поднималось, вода не видит")
	s.party_at = "high_ground"
	DayRules.end_day(c, s)                    # день 2 — ночь: вода пришла
	eq(TideRules.phase(s), "flood", "вода пришла:")
	eq(MapRules.place_state(c, s, "coral_maze"), "flooded", "лабиринт под водой:")
	eq(MapRules.place_state(c, s, "high_ground"), "dry", "высота сухая:")
	eq(str(s.missions["RS16"]["status"]), "expired", "встречу поля раковин смыло:")
	var before := TideRules.pos(c, s, "coral_maze")
	var ev := DayRules.end_day(c, s)          # день 3 — рассвет: вода сошла, большой отлив
	eq(TideRules.phase(s), "", "отлив:")
	check(not MapRules.present(c, s, "shell_field") or MapRules.emerged(s).size() > 1, "смытое место ушло с карты")
	var n := MapRules.emerged(s).size()
	check(n >= 1 and n <= 2, "на Рассвете поднялось 1–2 новых места: %d" % n)
	check(ev.any(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "emerge"), "событие появления")
	eq(TideRules.pos(c, s, "coral_maze"), before, "на карте-плане места не переставляются:")
	check(MapRules.place_state(c, s, "coral_maze") in ["dry_b", "dry_c"], "у лабиринта новые проходы: %s" % MapRules.place_state(c, s, "coral_maze"))
	eq(MapRules.place_state(c, s, "low_tide"), "silt", "отмель в иле:")
	DayRules.end_day(c, s)
	eq(MapRules.place_state(c, s, "low_tide"), "silt", "ил ещё день:")
	eq(int(s.tide.get("silt", {}).get("low_tide", 0)), 1, "и подсыхает:")


func test_nest_only_from_raid() -> void:
	var c := content()
	for sd in 30:
		var s := _shore(100 + sd)
		MapRules.on_ebb(c, s, [], _rng(sd))
		check(not MapRules.present(c, s, "carapace_nest"), "Гнездовье не поднимается отливом")
	var s2 := _shore()
	var ns02: Dictionary = c.missions["NS02"]
	var cmds: Array = ns02.get("on_expire", []).filter(func(e: Dictionary) -> bool: return str(e.get("cmd", "")) == "emerge")
	eq(cmds.size(), 1, "набег стаи поднимает Гнездовье:")
	EffectApplier.apply_all(c, s2, cmds, "P01", _rng())
	check(MapRules.present(c, s2, "carapace_nest"), "Гнездовье на карте")
	eq(str(s2.missions.get("RS14", {}).get("status", "")), "open", "его можно выжечь:")


func test_marks_and_sky() -> void:
	var c := content()
	var s := _shore()
	EffectApplier.apply(c, s, {"cmd": "map_mark", "place": "shelter", "state": "ravaged", "missions": 2}, "P01", _rng())
	eq(MapRules.place_state(c, s, "shelter"), "ravaged", "укрытие разорено:")
	s.party_at = "high_ground"
	DayRules.end_day(c, s)
	eq(MapRules.place_state(c, s, "shelter"), "ravaged", "ещё день:")
	DayRules.end_day(c, s)
	eq(MapRules.place_state(c, s, "shelter"), "dry", "след стёрся:")
	eq(MapRules.place_state(c, s, "high_ground", "storm"), "storm", "в шторм — облик после бури:")
	eq(MapRules.place_state(c, s, "shelter", "storm"), "dry", "у кого нет бури — как было:")


func test_fog() -> void:
	var c := content()
	var s := _shore()
	check(MapRules.revealed(c, s, "stone_isle"), "место первой миссии открыто")
	check(not MapRules.revealed(c, s, "spire_view"), "Костяной хребет в тумане")
	check(MapRules.revealed(c, s, "shore_altar"), "алтарь торговца виден сразу")
