extends TestCase
## Перемещение и «без тупиков» (TravelRules, DayPlanner, docs/17): сухой хребет карты при любой воде,
## маршруты и шаги дня, путь к каждой открытой миссии виден, утром всегда есть чем заняться, дела лагеря,
## и прогоны бота по Берегу: ни одного пустого утра, сюжет не стоит под водой дольше дня.


func _shore(seed_value: int = 5, steps: bool = false) -> RunState:
	var s := MissionFlow.new_run(content(), seed_value, "shore")
	if steps:
		s.flags["movement"] = "steps"   # старые шаги дня (docs/17) — в ветке фигуры (docs/18) их включают явно
	return s


func _shore_places(c: Content) -> Array:
	var out: Array = []
	for lid: String in MapRules.config(c, "shore").get("places", {}):
		if c.locations.has(lid) and not MapRules.is_emerging(c, lid):
			out.append(lid)
	return out


## Затопить всё, что может утонуть: низины и средние места (худший прилив).
func _worst_flood(c: Content, s: RunState) -> void:
	var places: Array = []
	for lid: String in _shore_places(c):
		if TideRules.height(c, lid) in ["low", "mid"]:
			places.append(lid)
	s.tide = {"phase": "flood", "left": 1, "places": places, "source": "story"}


func test_dry_spine() -> void:
	var c := content()
	var s := _shore()
	var all := _shore_places(c)
	# в сухую погоду из лагеря дойти можно до любого места
	for lid: String in all:
		check(lid == s.party_at or TravelRules.distance(c, s, lid) > 0, "без воды дойти можно до %s" % lid)
	# худший прилив: высоты и лавка связаны между собой без низин и средних мест
	_worst_flood(c, s)
	var highs: Array = all.filter(func(l: String) -> bool: return TideRules.height(c, l) == "high")
	for a: String in highs:
		for b: String in highs:
			if a != b:
				check(not TravelRules.route(c, s, a, b).is_empty(), "в прилив с %s дойти до %s по высотам" % [a, b])
	# данные тоже проверяют это при загрузке
	check(ContentValidator.dry_spine_errors(c).is_empty(), "проверка данных: сухой хребет цел")


func test_route_and_steps() -> void:
	var c := content()
	var s := _shore(5, true)
	s.party_at = "stone_isle"
	var r := TravelRules.route(c, s, "stone_isle", "statue_hill")
	check(r.size() >= 2 and r[r.size() - 1] == "statue_hill", "маршрут до Холма: %s" % str(r))
	check(r.has("shelter"), "путь идёт через Расщелину")
	eq(TravelRules.steps_left(c, s), 3, "утром три бесплатных перехода:")
	var psy := PsycheRules.psyche(s, "P01")
	var out: Array = []
	eq(TravelRules.travel(c, s, "shelter", out), "", "переход в соседнее место:")
	eq(PsycheRules.psyche(s, "P01"), psy, "бесплатный переход психики не стоит:")
	eq(TravelRules.steps_left(c, s), 2, "осталось два перехода:")
	s.flags["steps"] = 3
	out.clear()
	eq(TravelRules.travel(c, s, "stone_isle", out), "", "марш-бросок разрешён:")
	check(PsycheRules.psyche(s, "P01") < psy, "марш-бросок стоит психики")
	eq(TravelRules.why_not(c, s, "shore_altar"), "Здесь нельзя встать лагерем — только пройти мимо", "у лавки лагерем не встать:")
	TravelRules.new_day(s)
	eq(TravelRules.steps_left(c, s), 3, "новый день — шаги снова бесплатны:")


func test_flood_blocks_and_explains() -> void:
	var c := content()
	var s := _shore()
	s.party_at = "stone_isle"
	s.tide = {"phase": "flood", "left": 1, "places": ["low_tide", "coral_maze"], "source": "week"}
	check(TravelRules.why_not(c, s, "coral_maze").begins_with("Место под водой"), "под воду не пройти — и видно почему")
	check(TravelRules.route(c, s, "stone_isle", "low_tide").is_empty(), "по воде не ходят")


func test_route_to_open_missions_revealed() -> void:
	var c := content()
	var s := _shore()
	s.party_at = "stone_isle"
	MissionFlow.open(c, s, "SH22", true)   # Холм у статуи — далеко от платформы
	var kn := MapRules.known(c, s)
	for p: String in TravelRules.route(c, s, "stone_isle", "statue_hill", false):
		check(kn.has(p), "путь к миссии виден: %s" % p)
	check(DayRules.mission_reachable(c, s, "SH22"), "далёкую миссию можно запустить — отряд дойдёт сам")


func test_launch_far_walks_route() -> void:
	var c := content()
	var s := _shore(5, true)
	s.party_at = "stone_isle"
	for mid: String in MissionFlow.open_missions(s):
		s.missions[mid]["status"] = "done"
	MissionFlow.open(c, s, "SH22", true)
	var r := MissionFlow.launch(c, s, "SH22", ["P01"])
	check(r["ok"], "запуск далёкой миссии: %s" % str(r.get("error", "")))
	eq(s.party_at, "statue_hill", "отряд пришёл к миссии:")
	check(TravelRules.steps_used(s) >= 2, "переходы посчитаны: %d" % TravelRules.steps_used(s))
	check(TravelRules.visited(s).has("shelter"), "пройденные места посещены")


func test_morning_ensures_options() -> void:
	var c := content()
	var s := _shore()
	s.party_at = "shelter"
	for mid: String in MissionFlow.open_missions(s):
		s.missions[mid]["status"] = "done"
	eq((DayPlanner.options(c, s)["today"] as Array).size(), 0, "миссий рядом нет:")
	var ev := DayPlanner.ensure(c, s)
	check((DayPlanner.options(c, s)["today"] as Array).size() >= DayPlanner.min_options(c), "утром появились встречи рядом: %s" % str(ev))
	check(ev.any(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "planner"), "игроку сказано, что рядом неспокойно")
	# в прилив встречи — только на сухом
	var s2 := _shore(9)
	s2.party_at = "shelter"
	for mid: String in MissionFlow.open_missions(s2):
		s2.missions[mid]["status"] = "done"
	_worst_flood(c, s2)
	DayPlanner.ensure(c, s2)
	for mid: String in MissionFlow.open_missions(s2):
		check(not TideRules.flooded(s2, str(c.missions[mid]["location"])), "встреча не под водой: %s" % mid)


func test_camp_tasks() -> void:
	var c := content()
	var s := _shore()
	s.party_at = "shelter"
	eq(DayPlanner.tasks_left(c, s).size(), 3, "три дела лагеря:")
	var sh := int(s.resources.get("shards", 0))
	var r := DayPlanner.do_task(c, s, "forage", "P01")
	check(r["ok"], "сбор сделан")
	check(int(s.resources.get("shards", 0)) > sh, "сбор приносит осколки")
	eq(DayRules.sorties(s, "P01"), 1, "дело лагеря — это выход героя:")
	check(not DayPlanner.do_task(c, s, "forage", "P01")["ok"], "одно дело — раз в день")
	var before := MapRules.known(c, s).size()
	check(DayPlanner.do_task(c, s, "scout", "P01")["ok"], "разведка сделана")
	check(MapRules.known(c, s).size() >= before, "разведка открывает места")
	check(DayPlanner.do_task(c, s, "watch", "P01")["ok"], "дозор выставлен")
	check(bool(s.flags.get("watch", false)), "дозор до ночи")
	eq(DayPlanner.tasks_left(c, s).size(), 0, "дела на сегодня сделаны:")
	DayRules.end_day(c, s)
	eq(DayPlanner.tasks_left(c, s).size(), 3, "утром дела снова свободны:")
	check(not bool(s.flags.get("watch", false)), "дозор снят")


## Прогоны бота по Берегу, как игрока: каждое утро есть что делать, миссии всегда видны, сюжет под водой
## стоит не дольше дня подряд, глава проходится.
func test_no_dead_ends_simulation() -> void:
	var c := content()
	var runs := 40
	var empty_mornings := 0
	var hidden := 0
	var worst_story_wait := 0
	var finished := 0
	var days_total := 0
	var wait_note := ""
	for sd in runs:
		var s := MissionFlow.new_run(c, 3000 + sd * 7, "shore")
		var last_day := 0
		var story_wait := 0
		for step in 1500:
			if s.day != last_day:
				last_day = s.day
				# утро: дела на сегодня
				if DayPlanner.count_today(c, s) == 0 and not MissionFlow.free_heroes(c, s).is_empty():
					empty_mornings += 1
				# открытые миссии видны игроку
				var kn := MapRules.known(c, s)
				for mid: String in MissionFlow.open_missions(s):
					var loc := str(c.missions[mid].get("location", ""))
					if MissionFlow.chapter_of(c, mid) == "shore" and not kn.has(loc) and not c.shops.has(loc):
						hidden += 1
				# сюжет ждёт воды
				var cut: Array = DayPlanner.options(c, s)["cut"]
				if cut.any(func(m: String) -> bool: return str(c.missions[m]["type"]) == "story"):
					story_wait += 1
					worst_story_wait = maxi(worst_story_wait, story_wait)
					if story_wait >= 2:
						wait_note = "зерно %d, день %d, фаза %s, вода %s (%s), лагерь %s, сюжет %s" % [3000 + sd * 7, s.day,
							DayRules.phase(c, s)["id"], TideRules.phase(s), str(s.tide.get("source", "")), s.party_at,
							str(cut.filter(func(m: String) -> bool: return str(c.missions[m]["type"]) == "story"))]
				else:
					story_wait = 0
			var r := AutoPlay.step(c, s)
			s = r["state"]
			if s.demo_complete or s.game_over or s.chapter != "shore":
				break
		if s.demo_complete or s.chapter != "shore":
			finished += 1
		days_total += s.day
		hidden += int(s.flags.get("bot_hidden", 0))
	print("   [дни] прогонов Берега: %d, пройдено: %d, дней в среднем: %.1f, пустых утр: %d, скрытых миссий: %d, дольше всего сюжет ждал воды: %d дн." \
		% [runs, finished, float(days_total) / runs, empty_mornings, hidden, worst_story_wait])
	eq(empty_mornings, 0, "пустых утр (нечего делать):")
	eq(hidden, 0, "открытых миссий, скрытых туманом:")
	check(worst_story_wait <= 1, "сюжет ждёт воду не дольше дня подряд: %d · %s" % [worst_story_wait, wait_note])
	check(finished >= runs * 9 / 10, "глава проходится: %d из %d" % [finished, runs])


## Режиссёр напряжения (docs/17 §18): вымотанному отряду — спокойные встречи, свежему — с боем.
func test_director_tension() -> void:
	var c := content()
	var s := _shore()
	s.party_at = "shelter"
	s.day = 1
	check(DayPlanner.tension(c, s) < DayPlanner.FIGHT_BELOW, "свежий отряд — низкое напряжение: %.2f" % DayPlanner.tension(c, s))
	eq(DayPlanner.preferred_kind(c, s), "fight", "свежему — с боем:")
	var ev := DayPlanner.spawn_local(c, s, "shelter")
	check(not ev.is_empty() and str(c.missions[str(ev[0]["card"])].get("local_kind", "")) == "fight", "в Расщелине поднялась встреча с боем")
	# вымотанный: психика низкая, герой на грани
	var s2 := _shore(11)
	s2.party_at = "shelter"
	PsycheRules.change(c, s2, "P01", -80, "тест", [], null, "mission", false)
	s2.character("P01")["edge"] = true
	check(DayPlanner.tension(c, s2) >= DayPlanner.CALM_FROM, "вымотанный отряд — высокое напряжение: %.2f" % DayPlanner.tension(c, s2))
	eq(DayPlanner.preferred_kind(c, s2), "calm", "вымотанному — спокойные:")
	var ev2 := DayPlanner.spawn_local(c, s2, "shelter")
	check(not ev2.is_empty() and str(c.missions[str(ev2[0]["card"])].get("local_kind", "")) == "calm", "в Расщелине поднялась спокойная встреча")


func test_local_encounters_data() -> void:
	var c := content()
	for lid: String in _shore_places(c):
		var kinds := {}
		for mid: String in c.locations[lid].get("random", {}).get("local", []):
			kinds[str(c.missions[mid].get("local_kind", ""))] = true
			eq(float(c.missions[mid].get("xp_mult", 1.0)), 1.5, "%s — опыт тегов ×1,5:" % mid)
		check(kinds.has("calm") and kinds.has("fight"), "у %s есть спокойная и боевая встречи" % lid)


func test_high_places_two_paths() -> void:
	var c := content()
	check(not ContentValidator.dry_spine_errors(c).any(func(e: String) -> bool: return e.contains("одна тропа")), "у каждой высоты не меньше двух троп")
