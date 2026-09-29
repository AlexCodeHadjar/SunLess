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
	MissionFlow.open(c, s, side, true)
	MissionFlow.open(c, s, story)
	TideRules.schedule(c, s, 2, 2)
	check(TideRules.threatened(s, low), "низина под угрозой")
	check(not TideRules.risky(c, s, story), "до воды две миссии — ещё можно")
	MissionFlow.tick(c, s, 500.0)
	eq(TideRules.phase(s), "warn", "время само по себе воду не приводит:")
	MissionFlow.after_completion(c, s)
	check(not TideRules.risky(c, s, story), "одна миссия до воды, других отрядов нет — успеет")
	# другой отряд в деле может закончить раньше и привести воду
	s.squads.append({"id": 99, "mission": side, "heroes": [], "phase": "travel", "launched_at": 0.0, "arrive_at": 99.0})
	check(TideRules.risky(c, s, story), "другой отряд в деле — отмечено")
	s.squads.clear()
	MissionFlow.after_completion(c, s)
	MissionFlow.tick(c, s, 0.1)
	eq(TideRules.phase(s), "flood", "две миссии — вода пришла:")
	eq(str(s.missions[side]["status"]), "expired", "побочную смыло:")
	eq(str(s.missions[story]["status"]), "open", "сюжетная ждёт:")
	eq(MissionFlow.can_launch(c, s, story, ["P01"]), "Под водой — ждите отлива", "под воду не отправить:")
	var before := TideRules.pos(c, s, low)
	# на высоте есть чем заняться — вода стоит, пока не выполнены две миссии
	var high: String = _low_high(c)[1]
	for m3: String in c.missions:
		if str(c.missions[m3].get("location", "")) == high and str(c.missions[m3].get("type", "")) == "story" and not s.missions.has(m3):
			MissionFlow.open(c, s, m3)
			break
	MissionFlow.tick(c, s, 500.0)
	eq(TideRules.phase(s), "flood", "время воду не уводит:")
	MissionFlow.after_completion(c, s)
	MissionFlow.after_completion(c, s)
	var ev := MissionFlow.tick(c, s, 0.1)
	eq(TideRules.phase(s), "", "отлив после двух миссий:")
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
		TideRules.schedule(c, s, 1, 2)
		MissionFlow.after_completion(c, s)   # другой отряд закончил своё — вода пришла
		var ev := MissionFlow.tick(c, s, 0.1)
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


func test_stuck_flood_ebbs() -> void:
	var c := content()
	var s := _shore()
	for mid: String in s.missions.keys():
		s.missions.erase(mid)
	TideRules.schedule(c, s, 1, 5)
	MissionFlow.after_completion(c, s)
	MissionFlow.tick(c, s, 0.1)
	# открытых миссий нет, отрядов нет — ждать нечем: вода уходит сама
	MissionFlow.tick(c, s, 0.1)
	eq(TideRules.phase(s), "", "глава не встаёт — вода ушла:")


func test_new_chapter_clears_tide() -> void:
	var c := content()
	var s := _shore()
	TideRules.schedule(c, s, 2, 2)
	MissionFlow.start_chapter(c, s, "shore")
	eq(TideRules.phase(s), "", "новая глава — без прилива:")
