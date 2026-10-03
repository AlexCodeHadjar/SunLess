extends TestCase
## Фигура (docs/18, ветка gameplay/figure): с Академии отряд — фигура на карте-плане; день — две половины, действие —
## полдня (шаг на соседний участок, событие там, где фигура, дело лагеря, ожидание); две половины — ночь;
## планировщик держит события здесь и по соседству; бот проходит главы фигурой.


func _shore(seed_value: int = 5) -> RunState:
	var c := content()
	var s := MissionFlow.new_run(c, seed_value, "shore")
	s.party_at = "shelter"
	TravelRules.visit(s, "shelter")
	for mid: String in MissionFlow.open_missions(s):
		s.missions[mid]["status"] = "done"
	return s


func _far_place(c: Content, s: RunState) -> String:
	for lid: String in MapRules.config(c, s.chapter).get("places", {}):
		if c.locations.has(lid) and TravelRules.distance(c, s, lid) >= 2:
			return lid
	return ""


## Местная встреча на участке (открыть и вернуть id).
func _event_at(c: Content, s: RunState, lid: String) -> String:
	DayPlanner.spawn_local(c, s, lid)
	for mid: String in MissionFlow.open_missions(s):
		if str(c.missions[mid].get("location", "")) == lid:
			return mid
	return ""


func test_figure_from_academy() -> void:
	var c := content()
	check(FigureRules.on(c, MissionFlow.new_run(c, 3, "academy")), "в Академии — фигура")
	check(not FigureRules.on(c, MissionFlow.new_run(c, 3, "nightmare")), "в Первом Кошмаре карты-плана нет — фигуры тоже")
	var s := _shore()
	check(FigureRules.on(c, s), "на Берегу — фигура")
	s.flags["movement"] = "steps"
	check(not FigureRules.on(c, s), "старое передвижение включается явно")


func test_move_is_half_a_day() -> void:
	var c := content()
	var s := _shore()
	var targets := FigureRules.targets(c, s)
	check(not targets.is_empty(), "есть куда шагнуть: %s" % str(targets))
	var far := _far_place(c, s)
	check(FigureRules.why_not(c, s, far).begins_with("Далеко"), "дальний участок — нельзя: %s" % FigureRules.why_not(c, s, far))
	eq(FigureRules.why_not(c, s, s.party_at), "Фигура уже здесь", "на свой участок:")
	var day := s.day
	var to: String = targets[0]
	var r := FigureRules.move(c, s, to)
	check(r["ok"], "шаг на соседний участок: %s" % str(r["error"]))
	eq(s.party_at, to, "фигура — на новом участке (там и лагерь):")
	eq(s.day, day, "шаг — полдня, день тот же:")
	eq(FigureRules.half(s), 1, "наступил полдень:")


func test_events_only_where_figure_stands() -> void:
	var c := content()
	var s := _shore()
	var n: String = FigureRules.targets(c, s)[0]
	var there := _event_at(c, s, n)
	check(there != "", "встреча на соседнем участке")
	eq(FigureRules.reach(c, s, there), 1, "соседнее событие — в одном дне:")
	check(MissionFlow.can_launch(c, s, there, ["P01"]).begins_with("Событие не здесь"), "провести можно только там, где фигура")
	var here := _event_at(c, s, s.party_at)
	check(here != "", "встреча у фигуры")
	eq(FigureRules.reach(c, s, here), 0, "событие здесь:")
	eq(MissionFlow.can_launch(c, s, here, ["P01"]), "", "здесь — можно:")
	var r := MissionFlow.launch(c, s, here, ["P01"])
	check(r["ok"], "отряд вышел")
	eq(s.party_at, "shelter", "фигура не сдвинулась:")


## Решение владельца 03.10 (вместо прыжка): шаг к соседнему событию — полдня, событие — полдня, потом ночь.
func test_step_and_event_is_one_day() -> void:
	var c := content()
	var s := _shore(7)
	var n: String = FigureRules.targets(c, s)[0]
	var mid := _event_at(c, s, n)
	var day := s.day
	var r := FigureRules.move(c, s, n)
	check(r["ok"], "шаг к событию: %s" % str(r["error"]))
	eq(s.day, day, "после шага — полдень, ночь ещё не наступила:")
	eq(FigureRules.half(s), 1, "осталось полдня:")
	check(not FigureRules.is_night(r["entries"]), "в записях — полдень, не ночь")
	eq(FigureRules.reach(c, s, mid), 0, "событие теперь здесь:")
	var lr := MissionFlow.launch(c, s, mid, ["P01"])
	check(lr["ok"], "событие начато во второй половине дня")
	var act := ""
	for e: Dictionary in MissionFlow.actions_for(c, s, mid, ["P01"]):
		if e["available"] and not bool(e["action"].get("retreat", false)):
			act = str(e["action"]["id"])
			break
	s = MissionResolver.resolve_through(c, s, int(lr["squad"]["id"]), act)["state"]
	check(FigureRules.is_night(FigureRules.end_after_event(c, s)), "после события — ночь")
	eq(s.day, day + 1, "шаг и событие — один день:")
	eq(FigureRules.half(s), 0, "утро — снова две половины:")


func test_two_steps_a_day() -> void:
	var c := content()
	var s := _shore(9)
	var day := s.day
	var a: String = FigureRules.targets(c, s)[0]
	check(FigureRules.move(c, s, a)["ok"], "первый шаг")
	var back := FigureRules.targets(c, s)
	check(not back.is_empty(), "после полудня можно шагнуть ещё раз")
	var r := FigureRules.move(c, s, str(back[0]))
	check(r["ok"], "второй шаг: %s" % str(r["error"]))
	check(FigureRules.is_night(r["entries"]), "два шага — день прошёл, ночь")
	eq(s.day, day + 1, "день прошёл:")


func test_wait_is_half_a_day() -> void:
	var c := content()
	var s := _shore(21)
	var day := s.day
	var r := FigureRules.wait(c, s)
	check(r["ok"] and not FigureRules.is_night(r["entries"]), "утром переждать — до полудня")
	eq(s.day, day, "день тот же:")
	r = FigureRules.wait(c, s)
	check(FigureRules.is_night(r["entries"]), "после полудня переждать — до ночи")
	eq(s.day, day + 1, "наступил новый день:")


func test_camp_task_is_half_a_day() -> void:
	var c := content()
	var s := _shore(15)
	var day := s.day
	var r := FigureRules.task(c, s, "forage", "P01")
	check(r["ok"], "сбор: %s" % str(r["error"]))
	eq(s.day, day, "дело лагеря — полдня, день тот же:")
	check(not FigureRules.is_night(r["entries"]), "после первого дела — полдень")
	r = FigureRules.task(c, s, "watch", "P01")
	check(r["ok"], "второе дело в тот же день: %s" % str(r["error"]))
	check(FigureRules.is_night(r["entries"]), "два дела — ночь")
	eq(s.day, day + 1, "день прошёл:")


func test_expires_longer_with_figure() -> void:
	var c := content()
	var s := _shore(19)
	var mid := ""
	for m: String in c.missions:
		if float(c.missions[m].get("expires", 0)) > 0 and MissionFlow.chapter_of(c, m) == "shore":
			mid = m
			break
	var base := ModifierRules.expires(c, s, mid)
	s.flags["movement"] = "steps"
	var old := ModifierRules.expires(c, s, mid)
	check(base > old and base <= int(ceil(old * 1.5)) + 1, "с фигурой срок в полтора раза длиннее: %d против %d" % [base, old])


func test_event_is_half_a_day() -> void:
	var c := content()
	var s := _shore(11)
	var mid := _event_at(c, s, s.party_at)
	eq(FigureRules.end_after_event(c, s), [], "без события день не кончается (закрыли брифинг):")
	var r := MissionFlow.launch(c, s, mid, ["P01"])
	check(r["ok"], "событие начато")
	eq(FigureRules.end_after_event(c, s), [], "отряд ещё на месте — ночь не наступает:")
	var act := ""
	for e: Dictionary in MissionFlow.actions_for(c, s, mid, ["P01"]):
		if e["available"] and not bool(e["action"].get("retreat", false)):
			act = str(e["action"]["id"])
			break
	var res := MissionResolver.resolve_through(c, s, int(r["squad"]["id"]), act)
	s = res["state"]
	var day := s.day
	var ev := FigureRules.end_after_event(c, s)
	check(not ev.is_empty() and not FigureRules.is_night(ev), "событие утром — полдня, наступил полдень")
	eq(s.day, day, "день тот же:")
	eq(FigureRules.end_after_event(c, s), [], "полдень не повторяется:")


func test_onslaught_comes_to_figure() -> void:
	var c := content()
	var s := _shore(13)
	var ons := ""
	for mid: String in c.missions:
		if str(c.missions[mid].get("type", "")) == "onslaught" and MissionFlow.chapter_of(c, mid) == "shore":
			ons = mid
			break
	if ons == "":
		return
	MissionFlow.open(c, s, ons, true)
	eq(FigureRules.reach(c, s, ons), 0, "Натиск приходит к фигуре:")
	var team := MissionFlow.heroes(c, s).slice(0, int(c.missions[ons]["squad"]["max"]))
	if MissionFlow.can_launch(c, s, ons, team) == "":
		MissionFlow.launch(c, s, ons, team)
		eq(s.party_at, "shelter", "Натиск не уводит лагерь с участка фигуры:")


func test_planner_keeps_events_near_figure() -> void:
	var c := content()
	var s := _shore(17)
	eq((DayPlanner.options(c, s)["today"] as Array).size(), 0, "рядом пусто:")
	DayPlanner.ensure(c, s)
	var today: Array = DayPlanner.options(c, s)["today"]
	check(today.size() >= DayPlanner.min_options(c), "утром рядом с фигурой появились встречи: %s" % str(today))
	for mid: String in today:
		check(FigureRules.reach(c, s, mid) in [0, 1], "встреча здесь или по соседству: %s" % mid)


func test_shop_near_figure() -> void:
	var c := content()
	var s := _shore()
	for sid: String in ShopRules.shops_of(c, s):
		if not MapRules.config(c, "shore").get("places", {}).has(sid):
			continue
		var nb := MapRules.neighbors(c, s, sid)
		if nb.is_empty():
			continue
		s.party_at = str(nb[0])
		check(DayRules.shop_near(c, s, sid), "фигура у лавки — лавка открыта")
		s.party_at = sid
		check(DayRules.shop_near(c, s, sid), "фигура на лавке — лавка открыта")


## Бот играет фигурой: главы проходятся, пустых утр нет, тупиков нет.
func test_figure_runs() -> void:
	var c := content()
	for chapter: String in ["academy", "shore", "city", "tree", "dark_city"]:
		var runs := 6
		var done := 0
		var empty := 0
		var stuck := ""
		var days := 0
		for sd in runs:
			var s := MapStory.start(c, chapter, 8100 + sd * 19)
			var last := 0
			for step in 6000:
				if s.day != last:
					last = s.day
					if FigureRules.on(c, s) and DayPlanner.count_today(c, s) == 0 and s.squads.is_empty():
						empty += 1
				var r := AutoPlay.step(c, s)
				s = r["state"]
				if str(r["error"]) != "":
					stuck = "%s зерно %d: %s" % [chapter, 8100 + sd * 19, r["error"]]
					break
				if s.demo_complete or s.game_over or s.chapter != chapter:
					break
			if s.demo_complete or s.chapter != chapter:
				done += 1
			elif not s.game_over and stuck == "":
				stuck = "%s зерно %d: день %d, %s, открыто %s" % [chapter, 8100 + sd * 19, s.day, s.party_at, MissionFlow.open_missions(s)]
			days += s.day
		print("   [фигура] %s: прогонов %d, пройдено %d, дней в среднем %.1f, пустых утр %d" % [chapter, runs, done, float(days) / runs, empty])
		eq(stuck, "", "без тупиков (%s):" % chapter)
		eq(empty, 0, "пустых утр (%s):" % chapter)
		check(done >= runs * 2 / 3, "%s проходится фигурой: %d из %d" % [chapter, done, runs])
