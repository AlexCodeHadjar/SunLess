extends TestCase
## Глава 4 (docs «Глава 4 — Путь к Мрачному городу и Мрачный город — карта»): местность (TerrainRules — буря и сети
## троп, хрупкий мост, опасный спуск, Чёрная вода и лодка, дань, завалы), зоны (ZoneRules — гнев Владыки, Очарование,
## территории хозяев), подвижные угрозы (MoverRules — Демон, приманка, охотники), сюжет по зачищенным районам, прогоны бота.


func _tree(seed_value: int = 5) -> RunState:
	return AutoPlay.draft_start(content(), "tree", seed_value)


func _dark(seed_value: int = 5) -> RunState:
	return AutoPlay.draft_start(content(), "dark_city", seed_value)


func _has_link(c: Content, s: RunState, a: String, b: String) -> bool:
	return MapRules.links(c, s).any(func(p: Array) -> bool: return (p[0] == a and p[1] == b) or (p[0] == b and p[1] == a))


func test_chapter_chain() -> void:
	var c := content()
	eq(str(c.missions["SH32"].get("next_chapter", "")), "tree", "после Берега — Древо Души:")
	eq(str(c.missions["TS14"].get("next_chapter", "")), "dark_city", "после Древа — Мрачный город:")
	eq(str(c.missions["DS12"].get("next_chapter", "")), "city", "после Мрачного города — Город людей:")
	check(MapRules.has_map(c, "tree") and MapRules.has_map(c, "dark_city"), "у обеих частей главы карты-планы")
	var s := _tree()
	eq(s.party_at, "shore_exit", "Древо Души начинается у выхода с Берега:")
	eq(s.characters.size(), 3, "глава-черновик — с отрядом региона:")


func test_ash_storm_changes_paths() -> void:
	var c := content()
	var s := _tree()
	check(_has_link(c, s, "ash_dunes", "stone_hulk"), "до бури: дюны — остов")
	s.day = 4
	var ev := DayRules.end_day(c, s)
	eq(str(DayRules.phase(c, s)["id"]), "ash_storm", "пятый день — пепельная буря:")
	eq(int(s.flags.get("path_set", 0)), 1, "сеть троп сменилась:")
	check(not _has_link(c, s, "ash_dunes", "stone_hulk") and _has_link(c, s, "ash_bones", "stone_hulk"), "тропы Пепельного моря другие")
	check(ev.any(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "terrain"), "событие бури в окне ночи")
	# без тупиков при любой сети: от выхода с Берега до Маяка есть путь
	for i in 3:
		s.flags["path_set"] = i
		check(not TravelRules.route(c, s, "shore_exit", "death_beacon").is_empty(), "сеть %d: путь к Маяку есть" % i)


func test_ash_pits_and_islets_emerge() -> void:
	var c := content()
	var s := _tree()
	s.day = 2
	DayRules.end_day(c, s)
	eq(str(DayRules.phase(c, s)["id"]), "dawn", "третий день — Рассвет:")
	var ash := MapRules.emerged(s).keys().filter(func(l: String) -> bool: return str(c.locations[l].get("socket_group", "")) == "ash")
	var lake := MapRules.emerged(s).keys().filter(func(l: String) -> bool: return str(c.locations[l].get("socket_group", "")) == "lake")
	check(not ash.is_empty(), "на Рассвете в пепле поднялись котловины: %s" % str(ash))
	check(not lake.is_empty(), "и островки в Чёрной воде: %s" % str(lake))
	for l: String in ash:
		check(int(MapRules.emerged(s)[l]) in [0, 1, 2, 3], "котловина на своей площадке")
	DayRules.end_day(c, s)
	DayRules.end_day(c, s)
	check(MapRules.emerged(s).keys().all(func(l: String) -> bool: return str(c.locations[l].get("socket_group", "")) != "lake"),
		"после Рассвета островки ушли под воду")


func test_bridge_cracks_and_collapses() -> void:
	var c := content()
	var s := _tree()
	s.party_at = "death_beacon"
	var out: Array = []
	for i in 3:
		TravelRules.new_day(s)
		eq(TravelRules.travel(c, s, "lake_shore" if s.party_at == "death_beacon" else "death_beacon", out), "", "переход %d по мосту:" % (i + 1))
	eq(str(TerrainRules.terrain(s).get("abyss_bridge", "")), "cracked", "мост треснул:")
	TravelRules.new_day(s)
	TravelRules.travel(c, s, "death_beacon" if s.party_at == "lake_shore" else "lake_shore", out)
	check(TerrainRules.blocked(c, s, "abyss_bridge"), "мост рухнул")
	check(not TravelRules.passable(c, s, "abyss_bridge"), "по рухнувшему мосту не пройти")
	var r := TravelRules.route(c, s, "death_beacon", "lake_shore")
	check(not r.is_empty() and r.has("abyss_edge"), "дальше — спуском у Края Бездны: %s" % str(r))


func test_risky_descent_is_a_check() -> void:
	var c := content()
	var s := _tree()
	s.party_at = "demon_trail"
	var out: Array = []
	TravelRules.travel(c, s, "abyss_edge", out)
	check(out.any(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "terrain" and str(e.get("text", "")).begins_with("Спуск")),
		"спуск у Края Бездны — испытание")


func test_black_water_needs_boat_and_night() -> void:
	var c := content()
	var s := _tree()
	s.party_at = "boat_cove"
	s.day = 1
	check(TravelRules.route(c, s, "boat_cove", "black_rocks").is_empty(), "без лодки к Чёрным камням не пройти")
	check(TravelRules.why_not(c, s, "black_rocks").contains("лодк"), "окно перехода объясняет: %s" % TravelRules.why_not(c, s, "black_rocks"))
	s.flags["boat"] = true
	check(not TravelRules.route(c, s, "boat_cove", "black_rocks").is_empty(), "с лодкой ночью — можно")
	s.day = 3
	check(TravelRules.route(c, s, "boat_cove", "black_rocks").is_empty(), "на Рассвете — нельзя")
	check(TravelRules.why_not(c, s, "black_rocks").contains("ночью"), "объяснение: %s" % TravelRules.why_not(c, s, "black_rocks"))


func test_charm_holds_and_breaks() -> void:
	var c := content()
	var s := _tree()
	s.party_at = "soul_tree"
	s.day = 3
	check(ZoneRules.in_zone(c, s, "charm", "soul_tree"), "Древо — в зоне Очарования")
	var ev: Array = []
	for i in 3:
		ev.append_array(ZoneRules.night(c, s))
	eq(ZoneRules.charmed(c, s).size(), 3, "три ночи под Древом — весь отряд очарован:")
	check(ev.any(func(e: Dictionary) -> bool: return str(e.get("text", "")).contains("очарован")), "событие очарования")
	check(TravelRules.why_not(c, s, "death_beacon").contains("чары"), "очарованные не уходят: %s" % TravelRules.why_not(c, s, "death_beacon"))
	eq(TravelRules.why_not(c, s, "lake_shore"), "", "внутри зоны — ходить можно:")
	ZoneRules.command(c, s, {"do": "break", "zone": "charm"})
	eq(ZoneRules.charmed(c, s).size(), 0, "чары разорваны:")
	eq(TravelRules.why_not(c, s, "death_beacon"), "", "отряд снова свободен:")
	eq(ZoneRules.radius(c, s, "charm"), -1, "зоны Очарования больше нет:")


func test_wrath_zone_wider_at_night() -> void:
	var c := content()
	var s := _tree()
	s.day = 3
	check(not ZoneRules.in_zone(c, s, "wrath", "death_beacon"), "на Рассвете гнев Владыки — только у воронки")
	s.day = 1
	check(ZoneRules.in_zone(c, s, "wrath", "death_beacon"), "ночью — и у Маяка")
	s.party_at = "death_beacon"
	check(float(DayRules.camp(c, s).get("danger", 0.0)) >= 0.8, "лагерь в зоне гнева — опасен")


func test_demon_chases_lure_and_clash() -> void:
	var c := content()
	var s := _tree()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	MoverRules.command(c, s, {"do": "spawn", "mover": "demon", "place": "ash_bones"})
	s.party_at = "stone_hulk"
	s.day = 3
	MoverRules.night(c, s, rng)
	eq(MoverRules.at(s, "demon"), "demon_trail", "Демон идёт по следу к лагерю:")
	var ev := MoverRules.night(c, s, rng)
	check(ev.any(func(e: Dictionary) -> bool: return str(e.get("text", "")).contains("у лагеря")), "пришёл к лагерю — ночной бой")
	eq(MoverRules.at(s, "demon"), "demon_trail", "и отступил туда, откуда пришёл:")
	# Маяк смерти тянет Демона к огню; ночью у Маяка — гнев Владыки: Демон ранен и отходит
	s.party_at = "lake_shore"
	MoverRules.command(c, s, {"do": "lure", "mover": "demon", "place": "death_beacon", "days": 4})
	s.day = 1
	MoverRules.night(c, s, rng)
	eq(MoverRules.at(s, "demon"), "stone_hulk", "Демон идёт на огонь:")
	ev = MoverRules.night(c, s, rng)
	check(bool(MoverRules.movers(s)["demon"].get("wounded", false)), "сцепился с Владыкой — ранен")
	eq(MoverRules.at(s, "demon"), "stone_hulk", "и отступил:")
	MoverRules.command(c, s, {"do": "kill", "mover": "demon"})
	check(not MoverRules.active(s, "demon"), "Демон повержен")


func test_tribute_and_fallback() -> void:
	var c := content()
	var s := _dark()
	s.party_at = "bright_castle"
	s.resources["shards"] = 10
	var out: Array = []
	TerrainRules.tribute(c, s, out)
	eq(int(s.resources["shards"]), 7, "дань за ночь в замке — 3:")
	s.resources["shards"] = 1
	TerrainRules.tribute(c, s, out)
	eq(s.party_at, "castle_gate", "нечем платить — ночь у ворот:")
	eq(int(s.resources["shards"]), 1, "осколки не списаны:")


func test_territories_grow_and_clear() -> void:
	var c := content()
	var s := _dark()
	eq(ZoneRules.radius(c, s, "statues"), 0, "статуи — сначала только на площади:")
	ZoneRules.night(c, s)
	eq(ZoneRules.radius(c, s, "statues"), 1, "ночью территория расползается:")
	check(ZoneRules.in_zone(c, s, "statues", "hunters_guild"), "до Гильдии охотников")
	ZoneRules.night(c, s)
	ZoneRules.night(c, s)
	eq(ZoneRules.radius(c, s, "statues"), 2, "но не дальше max:")
	ZoneRules.command(c, s, {"do": "clear", "zone": "statues", "days": 5})
	eq(ZoneRules.radius(c, s, "statues"), -1, "зачищено:")
	eq(ZoneRules.cleared_total(s), 1, "зачищенных районов:")


func test_story_waits_for_cleared_districts() -> void:
	var c := content()
	var s := _dark()
	for mid: String in ["DS01", "DS02", "DS03", "DS04", "DS05", "DS06", "DS07"]:
		s.missions[mid] = {"status": "done"}
	ZoneRules.command(c, s, {"do": "clear", "zone": "statues", "days": 30})
	MissionFlow.after_completion(c, s)
	check(not s.missions.has("DS08"), "собор ждёт зачищенных районов")
	check(MissionFlow.story_wait(c, s).contains("1 из 3"), "строка «Сегодня»: %s" % MissionFlow.story_wait(c, s))
	ZoneRules.command(c, s, {"do": "clear", "zone": "spiders"})
	ZoneRules.command(c, s, {"do": "clear", "zone": "flowers"})
	MissionFlow.after_completion(c, s)
	eq(str(s.missions.get("DS08", {}).get("status", "")), "open", "три района зачищены — собор открыт:")
	eq(MissionFlow.story_wait(c, s), "", "сюжет больше не ждёт:")


func test_rubble_closes_and_opens() -> void:
	var c := content()
	var s := _dark()
	check(_has_link(c, s, "statue_plaza", "castle_gate"), "проход площадь — ворота открыт")
	TerrainRules.command(c, s, {"do": "collapse", "rubble": "R1"})
	check(not _has_link(c, s, "statue_plaza", "castle_gate"), "обвал закрыл проход")
	check(not TravelRules.route(c, s, "statue_plaza", "castle_gate").is_empty(), "но обход есть")
	TerrainRules.command(c, s, {"do": "clear", "rubble": "R1"})
	check(_has_link(c, s, "statue_plaza", "castle_gate"), "завал расчищен")


func test_hunters_go_to_noise() -> void:
	var c := content()
	var s := _dark()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	s.day = 1
	s.party_at = "sunny_lair"
	MoverRules.noise(s, "hunters_guild")
	MoverRules.night(c, s, rng)
	eq(MoverRules.at(s, "fiend"), "hunters_guild", "Кровавый Изверг идёт на шум боя:")


## Прогоны бота по обеим частям главы: проходятся, тупиков и пустых утр нет, механики встречаются.
func test_chapter4_runs() -> void:
	var c := content()
	for chapter: String in ["tree", "dark_city"]:
		var runs := 10
		var done := 0
		var empty := 0
		var stuck := ""
		var died := 0
		var days := 0
		var seen := {}
		for sd in runs:
			var s := AutoPlay.draft_start(c, chapter, 7100 + sd * 17)
			var n0 := MissionFlow.heroes(c, s).size()
			var last := 0
			for step in 3000:
				if s.day != last:
					last = s.day
					if DayPlanner.count_today(c, s) == 0 and not MissionFlow.free_heroes(c, s).is_empty() and s.squads.is_empty():
						empty += 1
				var r := AutoPlay.step(c, s)
				s = r["state"]
				if str(r["error"]) != "":
					stuck = "%s зерно %d: %s" % [chapter, 7100 + sd * 17, r["error"]]
					break
				for k: String in ["path_set", "crossed", "boat", "zones_done", "rubble"]:
					if s.flags.has(k):
						seen[k] = true
				if s.demo_complete or s.game_over or s.chapter != chapter:
					break
			if s.demo_complete or s.chapter != chapter:
				done += 1
			elif not s.game_over and stuck == "":
				stuck = "%s зерно %d: день %d, %s, открыто %s" % [chapter, 7100 + sd * 17, s.day, s.party_at, MissionFlow.open_missions(s)]
			died += maxi(0, n0 - MissionFlow.heroes(c, s).size())
			days += s.day
		print("   [глава 4] %s: прогонов %d, пройдено %d, дней в среднем %.1f, гибелей %d, пустых утр %d, механики %s" \
			% [chapter, runs, done, float(days) / runs, died, empty, str(seen.keys())])
		eq(stuck, "", "без тупиков (%s):" % chapter)
		eq(empty, 0, "пустых утр (%s):" % chapter)
		check(done >= runs * 8 / 10, "%s проходится: %d из %d" % [chapter, done, runs])
