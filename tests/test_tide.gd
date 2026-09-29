extends TestCase
## Прилив Забытого Берега (TideRules, docs/16 §11.1, §12): вода по неделе (Прилив и шторм), по сюжету —
## своим счётом дней; лагерь в затопленном месте бежит; ночь у логова опаснее.


func _shore() -> RunState:
	return MissionFlow.new_run(content(), 21, "shore")


func _low_high(c: Content) -> Array:
	var low := ""
	var high := ""
	for lid: String in c.locations:
		if str(c.locations[lid].get("chapter", "")) != "shore" or bool(c.locations[lid].get("emerge", false)):
			continue
		if TideRules.height(c, lid) == "low" and low == "":
			low = lid
		if TideRules.height(c, lid) == "high" and high == "":
			high = lid
	return [low, high]


func test_heights_in_data() -> void:
	var c := content()
	var lh := _low_high(c)
	check(lh[0] != "" and lh[1] != "", "у мест Берега есть низины и высоты")
	for lid: String in c.locations:
		var h := TideRules.height(c, lid)
		if str(c.locations[lid].get("chapter", "")) == "shore":
			check(h in ["low", "mid", "high"], "%s: высота задана (%s)" % [lid, h])


func test_schedule_picks_low_never_high() -> void:
	var c := content()
	for sd in 12:
		var s := _shore()
		s.rng_seed = 500 + sd
		var ev := TideRules.schedule(c, s, 2, 2)
		check(not ev.is_empty() and TideRules.phase(s) == "warn", "прилив объявлен")
		for lid: String in c.locations:
			if str(c.locations[lid].get("chapter", "")) != "shore" or not MapRules.present(c, s, lid):
				continue
			var h := TideRules.height(c, lid)
			if h == "low":
				check(TideRules.places(s).has(lid), "низина %s уходит под воду" % lid)
			if h == "high":
				check(not TideRules.places(s).has(lid), "высота %s не тонет" % lid)


func test_story_flood_by_days() -> void:
	# сюжетная вода (команда tide) идёт своим счётом дней; Рассвет её не снимает
	var c := content()
	var s := _shore()
	var low: String = _low_high(c)[0]
	var side := ""
	var story := ""
	for mid: String in c.missions:
		var m: Dictionary = c.missions[mid]
		if str(m.get("location", "")) != low:
			continue
		if str(m.get("type", "")) in ["random", "side"] and side == "":
			side = mid
		if str(m.get("type", "")) == "story" and story == "":
			story = mid
	check(side != "" and story != "", "в низине %s есть случайная и сюжетная миссии" % low)
	MissionFlow.open(c, s, side, true)
	MissionFlow.open(c, s, story)
	s.party_at = _low_high(c)[1]
	TideRules.schedule(c, s, 2, 2)
	check(TideRules.threatened(s, low), "низина под угрозой")
	MissionFlow.after_completion(c, s)
	eq(TideRules.phase(s), "warn", "выполненная миссия воду не приводит — только ночь:")
	DayRules.end_day(c, s)
	eq(TideRules.phase(s), "warn", "одна ночь — вода ещё не пришла:")
	DayRules.end_day(c, s)
	eq(TideRules.phase(s), "flood", "две ночи — вода пришла:")
	eq(str(DayRules.phase(c, s)["id"]), "dawn", "это Рассвет — но сюжетная вода стоит:")
	eq(str(s.missions[side]["status"]), "expired", "побочную смыло:")
	eq(str(s.missions[story]["status"]), "open", "сюжетная ждёт:")
	s.party_at = low
	eq(MissionFlow.can_launch(c, s, story, ["P01"]), "Под водой — ждите отлива", "под воду не отправить:")
	s.party_at = _low_high(c)[1]
	DayRules.end_day(c, s)
	var ev := DayRules.end_day(c, s)
	check(ev.any(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "tide_ebb"), "через два дня вода сошла")


func test_week_cycle() -> void:
	# неделя Берега: ночь 2 · рассвет 2 · прилив и шторм 2 · кровавая луна 2
	var c := content()
	var s := _shore()
	s.party_at = _low_high(c)[1]
	eq(DayRules.week_len(c, "shore"), 8, "неделя — 8 дней:")
	eq(str(DayRules.phase(c, s)["id"]), "night", "день 1 — ночь:")
	s.day = 3
	eq(str(DayRules.phase(c, s)["id"]), "dawn", "день 3 — рассвет:")
	eq(TideRules.phase(s), "", "воды нет:")
	var ev := DayRules.end_day(c, s)
	eq(s.day, 4, "ночь прошла:")
	eq(TideRules.phase(s), "warn", "накануне шторма — предупреждение:")
	DayRules.end_day(c, s)
	eq(str(DayRules.phase(c, s)["id"]), "storm", "день 5 — прилив и шторм:")
	eq(TideRules.phase(s), "flood", "вода пришла сама:")
	eq(Atmosphere.sky(c, s), "storm", "небо штормовое:")
	DayRules.end_day(c, s)
	eq(TideRules.phase(s), "flood", "стоит весь шторм:")
	ev = DayRules.end_day(c, s)
	eq(str(DayRules.phase(c, s)["id"]), "blood_moon", "день 7 — кровавая луна:")
	eq(TideRules.phase(s), "", "после шторма вода сходит:")
	check(ev.any(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "tide_ebb"), "событие схода воды")
	for i in 4:
		ev = DayRules.end_day(c, s)
	eq(str(DayRules.phase(c, s)["id"]), "dawn", "день 11 — снова рассвет:")
	check(not MapRules.emerged(s).is_empty(), "большой отлив поднял новые места")


func test_flooded_camp_flees() -> void:
	var c := content()
	var fled := 0
	for sd in 30:
		var s := _shore()
		s.rng_seed = 900 + sd
		var low: String = _low_high(c)[0]
		s.party_at = low
		s.day = 4                    # завтра шторм — вода придёт ночью, а отряд остался в низине
		var ev := DayRules.end_day(c, s)
		if TideRules.flooded(s, low):
			fled += 1
			check(s.party_at != low and not TideRules.flooded(s, s.party_at), "отряд бежал на сухое: %s" % s.party_at)
			check(ev.any(func(e: Dictionary) -> bool: return str(e.get("text", "")).begins_with("Вода пришла в лагерь")), "испытание бегством")
	eq(fled, 30, "низину заливает каждый раз:")


func test_night_attack_by_camp() -> void:
	# у логова в кровавую луну нападают часто, в укрытии — почти никогда
	var c := content()
	var near_lair := 0
	var shelter := 0
	for sd in 40:
		for place: String in ["hunting_grounds", "shelter"]:
			var s := _shore()
			s.rng_seed = 300 + sd
			s.day = 7
			s.party_at = place
			var ev := DayRules.end_day(c, s)
			if ev.any(func(e: Dictionary) -> bool: return str(e.get("text", "")).begins_with("На лагерь напали")):
				if place == "shelter":
					shelter += 1
				else:
					near_lair += 1
	check(near_lair > shelter + 10, "у логова нападают чаще: %d против %d" % [near_lair, shelter])


func test_tide_command_and_save() -> void:
	var c := content()
	var s := _shore()
	var rng := RandomNumberGenerator.new()
	var ev := EffectApplier.apply(c, s, {"cmd": "tide", "warn": 2, "flood": 2, "text": "Вода!"}, "P01", rng)
	check(not ev.is_empty() and str(ev[0]["text"]).begins_with("Вода!"), "команда tide объявляет прилив")
	var s2 := RunState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	eq(TideRules.phase(s2), "warn", "прилив сохраняется:")
	eq(TideRules.places(s2), TideRules.places(s), "места те же:")
	# story-миссии Берега объявляют прилив
	var n := 0
	for mid: String in c.missions:
		for e: Dictionary in c.missions[mid].get("on_complete", []):
			if str(e.get("cmd", "")) == "tide":
				n += 1
	check(n >= 4, "приливов по сюжету: %d" % n)


func test_new_chapter_clears_tide() -> void:
	var c := content()
	var s := _shore()
	TideRules.schedule(c, s, 2, 2)
	MissionFlow.start_chapter(c, s, "shore")
	eq(TideRules.phase(s), "", "новая глава — без прилива:")
	eq(s.day, 1, "неделя новой главы — с первого дня:")
