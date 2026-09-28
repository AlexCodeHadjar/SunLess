extends TestCase
## Прилив Забытого Берега (TideRules, docs/16 §10.1): по сюжету — предупреждение, вода, отлив.


func _shore() -> RunState:
	return MissionFlow.new_run(content(), 21, "shore")


func _low_high(c: Content) -> Array:
	var low := ""
	var high := ""
	for lid: String in c.locations:
		if str(c.locations[lid].get("chapter", "")) != "shore":
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
		var ev := TideRules.schedule(c, s, 30, 60)
		check(not ev.is_empty() and TideRules.phase(s) == "warn", "прилив объявлен")
		for lid: String in c.locations:
			if str(c.locations[lid].get("chapter", "")) != "shore":
				continue
			var h := TideRules.height(c, lid)
			if h == "low":
				check(TideRules.places(s).has(lid), "низина %s уходит под воду" % lid)
			if h == "high":
				check(not TideRules.places(s).has(lid), "высота %s не тонет" % lid)


func test_flood_washes_side_blocks_story_and_ebb_reshapes() -> void:
	var c := content()
	var s := _shore()
	var low: String = _low_high(c)[0]
	# побочная и сюжетная миссии в низине
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
	MissionFlow.open(c, s, side)
	MissionFlow.open(c, s, story)
	TideRules.schedule(c, s, 10, 20)
	check(TideRules.threatened(s, low), "низина под угрозой")
	check(TideRules.risky(c, s, story), "отряд не успеет — отмечено")
	MissionFlow.tick(c, s, 11.0)
	eq(TideRules.phase(s), "flood", "вода пришла:")
	eq(str(s.missions[side]["status"]), "expired", "побочную смыло:")
	eq(str(s.missions[story]["status"]), "open", "сюжетная ждёт:")
	eq(MissionFlow.can_launch(c, s, story, ["P01"]), "Под водой — ждите отлива", "под воду не отправить:")
	var before := TideRules.pos(c, s, low)
	var ev := MissionFlow.tick(c, s, 25.0)
	eq(TideRules.phase(s), "", "отлив:")
	check(ev.any(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "tide_ebb"), "событие отлива")
	check(MissionFlow.can_launch(c, s, story, ["P01"]) != "Под водой — ждите отлива", "после отлива — снова можно")
	check(before.size() == 2, "у места есть точка")
	# ячейки только переставляются: два места никогда не встают в одну точку
	var seen := {}
	for lid: String in c.locations:
		if str(c.locations[lid].get("chapter", "")) == "shore":
			var cell := TideRules.slot(s, lid)
			check(not seen.has(cell), "ячейка %s занята одним местом" % cell)
			seen[cell] = true


func test_caught_squad_flees() -> void:
	var c := content()
	var fails := 0
	for sd in 40:
		var s := _shore()
		s.rng_seed = 900 + sd
		var low: String = _low_high(c)[0]
		var mid := ""
		for m2: String in c.missions:
			if str(c.missions[m2].get("location", "")) == low and str(c.missions[m2].get("type", "")) == "story":
				mid = m2
				break
		MissionFlow.open(c, s, mid)
		var r := MissionFlow.launch(c, s, mid, ["P01"])
		check(bool(r["ok"]), "отряд ушёл: %s" % r.get("error", ""))
		TideRules.schedule(c, s, 1, 30)
		var ev := MissionFlow.tick(c, s, 2.0)
		var caught: Array = ev.filter(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "tide_caught")
		eq(caught.size(), 1, "вода застала отряд:")
		check(s.squads.is_empty(), "отряд вернулся")
		eq(str(s.missions[mid]["status"]), "open", "сюжетная миссия осталась:")
		check(PsycheRules.psyche(s, "P01") < 100, "психика задета")
		if not bool(caught[0]["ok"]):
			fails += 1
			check(EdgeRules.on_edge(s, "P01") or not s.is_alive("P01"), "провал бегства — поражение")
	check(fails > 0 and fails < 40, "бегство иногда проваливается: %d из 40" % fails)


func test_tide_command_and_save() -> void:
	var c := content()
	var s := _shore()
	var rng := RandomNumberGenerator.new()
	var ev := EffectApplier.apply(c, s, {"cmd": "tide", "warn": 20, "flood": 40, "text": "Вода!"}, "P01", rng)
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
	TideRules.schedule(c, s, 10, 20)
	MissionFlow.start_chapter(c, s, "shore")
	eq(TideRules.phase(s), "", "новая глава — без прилива:")
