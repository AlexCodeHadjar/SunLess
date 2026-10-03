extends TestCase
## Места и следы событий на карте-плане (MapEventRules, tools/shore_events_map.py; комплекты событий Берега и Главы 4):
## места событий поднимаются в свои фазы на свои площадки, отлив их не трогает, облики по фазе и лагерю, метки
## по модификаторам, следы отступления, гибели, нападения и шторма; картинки пака Главы 4 подключены к угрозам.


func _shore(seed_value: int = 5) -> RunState:
	var c := content()
	var s := MissionFlow.new_run(c, seed_value, "shore")
	s.party_at = "shelter"
	return s


func _event_places(c: Content) -> Array:
	var out: Array = []
	for lid: String in c.locations:
		if str(c.locations[lid].get("chapter", "")) == "shore" and str(c.locations[lid].get("socket_group", "")) != "":
			out.append(lid)
	return out


func test_event_places_data() -> void:
	var c := content()
	var ev := _event_places(c)
	eq(ev.size(), 11, "мест событий Берега:")
	var cfg := MapRules.config(c, "shore")
	eq((cfg["sockets"] as Array).size(), 14, "площадок S1–S14:")
	for lid: String in ev:
		check(bool(c.locations[lid].get("raid_only", false)), "%s не поднимается отливом сам" % lid)
		check(cfg["emerge_groups"].has(lid), "у %s своя группа площадок" % lid)
		check((c.locations[lid].get("random", {}).get("pool", []) as Array).size() == 2, "у %s две встречи" % lid)


func test_low_tide_keeps_to_silt() -> void:
	var c := content()
	var ev := _event_places(c)
	for sd in 12:
		var s := _shore(100 + sd)
		var rng := RandomNumberGenerator.new()
		rng.seed = sd
		MapRules.low_tide(c, s, rng)
		for lid: String in MapRules.emerged(s):
			check(not ev.has(lid), "отлив не поднимает место события: %s" % lid)
			check(int(MapRules.emerged(s)[lid]) <= 5, "место отлива — на площадке ила S1–S6: %s" % lid)


func test_places_rise_in_their_phase() -> void:
	var c := content()
	var s := _shore(7)
	var seen := {}
	for d in 15:
		DayRules.end_day(c, s)
		for lid: String in MapRules.emerged(s):
			if not seen.has(lid):
				seen[lid] = [s.day, str(DayRules.phase(c, s)["id"]), int(MapRules.emerged(s)[lid])]
	check(seen.has("strangers_camp"), "чужой лагерь встал в отлив: %s" % str(seen.keys()))
	check(seen.has("stranded_islet") and seen["stranded_islet"][1] == "storm", "островок отрезанных — в шторм: %s" % str(seen.get("stranded_islet")))
	check(seen.has("whale_carcass") and int(seen["whale_carcass"][2]) in [8, 9], "туша — после шторма на площадке в море: %s" % str(seen.get("whale_carcass")))
	check(seen.has("messenger_nest") and int(seen["messenger_nest"][0]) >= 8, "гнездо посланника — со второй недели: %s" % str(seen.get("messenger_nest")))
	check(not seen.has("sleepers_graves"), "могил нет, пока никто не погиб")


func test_event_states() -> void:
	var c := content()
	var s := _shore()
	s.day = 6   # Кровавая луна
	eq(str(DayRules.phase(c, s)["id"]), "blood_moon", "шестой день — Кровавая луна:")
	eq(MapRules.place_state(c, s, "shore_altar"), "blood", "алтарь в крови:")
	eq(MapRules.place_state(c, s, "hunting_grounds"), "molting", "в коридорах — линька:")
	eq(MapRules.place_state(c, s, "spire_view"), "dry", "на первой неделе Шпиль ещё не алый:")
	s.day = 13
	eq(MapRules.place_state(c, s, "spire_view"), "red", "со второй недели — красный отсвет:")
	s.day = 1
	s.party_at = "statue_hill"
	eq(MapRules.place_state(c, s, "statue_hill"), "bonfire", "лагерь у статуи — костёр горит:")
	s.party_at = "shelter"
	eq(MapRules.place_state(c, s, "statue_hill"), "dry", "ушли — костёр погас:")


func test_mod_and_phase_decals() -> void:
	var c := content()
	var s := _shore()
	MissionFlow.open(c, s, "RS02", true)
	s.missions["RS02"]["mods"] = ["fog"]
	check(MapEventRules.decals(c, s).any(func(d: Dictionary) -> bool: return d["decal"] == "decal_fog_bank" and d.get("place", "") == "coral_maze"),
		"туман у встречи с модификатором «Туман»")
	s.day = 6
	check(MapEventRules.decals(c, s).any(func(d: Dictionary) -> bool: return d["decal"] == "decal_blood_flowers"), "кровавые цветы в Кровавую луну")


func test_traces() -> void:
	var c := content()
	var s := _shore()
	var rng := RandomNumberGenerator.new()
	MapEventRules.after_mission(c, s, "RS02", {"outcome": "retreat", "deaths": []}, rng)
	check(MapEventRules.decals(c, s).any(func(d: Dictionary) -> bool: return d["decal"] == "decal_abandoned_gear"), "отступили — брошенное снаряжение")
	var ev := MapEventRules.after_mission(c, s, "RS02", {"outcome": "failure", "deaths": ["P02"]}, rng)
	check(MapRules.emerged(s).has("sleepers_graves"), "погиб герой — рядом Могилы Спящих")
	check(MapEventRules.decals(c, s).any(func(d: Dictionary) -> bool: return d["decal"] == "decal_fallen_sleepers"), "павшие под плащами")
	MapEventRules.night_attack(c, s)
	check(MapEventRules.decals(c, s).any(func(d: Dictionary) -> bool: return d["decal"] == "decal_hunter_mark"), "ночью напали — метка охотника у лагеря")
	s.day += 3
	check(not MapEventRules.decals(c, s).any(func(d: Dictionary) -> bool: return d["decal"] == "decal_hunter_mark"), "через пару дней следы стираются")
	check(not ev.is_empty(), "событие «на карте: могилы»")


func test_event_place_changes_after_encounter() -> void:
	var c := content()
	var s := _shore()
	var rng := RandomNumberGenerator.new()
	MapRules.emerge(c, s, "sleeping_golem", rng)
	eq(MapRules.place_state(c, s, "sleeping_golem"), "dry", "голем спит:")
	EffectApplier.apply(c, s, {"cmd": "map_mark", "place": "sleeping_golem", "state": "broken", "missions": 999}, "P01", rng)
	eq(MapRules.place_state(c, s, "sleeping_golem"), "broken", "после боя голем разбит:")


func test_chapter4_pack_art_wired() -> void:
	var c := content()
	var ash := MapRules.config(c, "tree")
	eq(str(ash["movers"]["demon"].get("token", "")), "decal_token_demon", "Демон — фишкой:")
	eq(str(ash["zones"]["wrath"].get("decal", "")), "decal_zone_wrath", "гнев Владыки — кольцом:")
	var dc := MapRules.config(c, "dark_city")
	eq(str(dc["zones"]["spiders"].get("spread", "")), "decal_web_spread", "паутина по тропам:")
	check(dc["movers"]["fiend"].has("nest"), "логово Изверга на карте")
	var s := AutoPlay.draft_start(c, "tree", 3)
	MoverRules.command(c, s, {"do": "spawn", "mover": "demon"})
	MoverRules.command(c, s, {"do": "lure", "mover": "demon", "place": "death_beacon", "days": 3})
	check(MapEventRules.decals(c, s).any(func(d: Dictionary) -> bool: return d["decal"] == "decal_beacon_fire"), "Маяк горит — огонь на карте")
	s.flags["boat"] = true
	check(MapEventRules.decals(c, s).any(func(d: Dictionary) -> bool: return d["decal"] == "decal_boat"), "лодка готова — лодка у заводи")
