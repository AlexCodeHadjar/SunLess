extends TestCase
## Небо над картой (docs/15 §19), герои Академии, купленные спутники после Кошмара.


func test_day_and_night_by_clock() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 1)
	eq(Atmosphere.sky(c, s), "night", "в начале — ночь:")
	s.clock = Atmosphere.DAY_CYCLE * 0.6
	eq(Atmosphere.sky(c, s), "day", "полцикла спустя — день:")
	s.clock = Atmosphere.DAY_CYCLE * 1.1
	eq(Atmosphere.sky(c, s), "night", "и снова ночь:")


func test_story_sky() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 1)
	s.clock = Atmosphere.DAY_CYCLE * 0.6
	MissionFlow.open(c, s, "MS05")
	eq(Atmosphere.sky(c, s), "blood_moon", "Горный Король — кровавая луна даже днём:")
	MissionFlow.open(c, s, "MS09")
	eq(Atmosphere.sky(c, s), "eclipse", "затмение сильнее луны:")
	s.missions["MS09"]["status"] = "done"
	s.missions["MS05"]["status"] = "done"
	eq(Atmosphere.sky(c, s), "day", "сюжет прошёл — снова обычное небо:")
	s.chapter = "academy"
	MissionFlow.open(c, s, "MS05")
	eq(Atmosphere.story_sky(c, s), "", "миссии чужой главы небо не трогают:")


func test_sky_art_exists() -> void:
	for sk: String in ["night", "day", "eclipse", "blood_moon"]:
		check(ResourceLoader.exists("res://art/regions/mountain_pass_%s.webp" % sk), "фон Первого Кошмара: %s" % sk)


func test_academy_heroes_join() -> void:
	var c := content()
	for cid: String in ["P02", "P03", "P04"]:
		eq(c.card_kind(cid), "character", "%s — играбельный персонаж:" % cid)
		eq(str(c.characters[cid].get("status", "")), "playable", "%s не уходит с концом главы:" % cid)
	eq(c.missions["SA02"]["on_complete"][0]["card"], "P03", "Касси — после «Пророчества в коридоре»:")
	eq(c.missions["SA04"]["on_complete"][0]["card"], "P04", "Кастер — после спарринга:")
	eq(c.missions["SA05"]["on_complete"][0]["card"], "P02", "Нефис — «Меняющаяся Звезда»:")
	var s := MissionFlow.new_run(c, 1)
	EffectApplier.add_card(c, s, "P03")
	check(Array(s.characters["P03"]["abilities"]).has("A04"), "у Касси — Пророческое Видение")


func test_bought_companions_stay_after_nightmare() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 1)
	EffectApplier.add_card(c, s, "P09")          # Шолар пришёл по сюжету
	s.resources["shards"] = 99
	s.shops["nightmare_trader"] = {"gen": 0, "seen": 0, "items": [{"card": "P10", "price": 8, "sold": false}]}
	eq(ShopRules.buy(c, s, "nightmare_trader", "P10"), "", "Шифти куплен:")
	var rng := RandomNumberGenerator.new()
	var out := EffectApplier.apply(c, s, {"cmd": "remove_temporaries"}, "P01", rng)
	check(not s.owns("P09"), "сюжетный спутник остаётся в Кошмаре")
	check(s.owns("P10"), "купленный спутник идёт дальше")
	check(str(out).contains("Остаются"), "игроку сказано, кто остаётся")
	var s2 := RunState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check(bool(s2.characters["P10"].get("bought", false)), "отметка «куплен» сохраняется")
