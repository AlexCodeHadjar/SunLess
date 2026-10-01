extends TestCase
## Прорывы Академии (GateRules, docs «Глава 2 — Академия — карта»): карта-план, сигнал → прорыв → рой → повреждение
## → ремонт, закрытие миссией, отсрочка, баррикада, оборона Зала капсул, лагерь в тревоге.


func _academy(seed_value: int = 5) -> RunState:
	var s := MissionFlow.new_run(content(), seed_value, "academy")
	for mid: String in MissionFlow.open_missions(s):
		s.missions[mid]["status"] = "done"   # без сюжета под ногами: только прорывы
	return s


func _night(c: Content, s: RunState) -> Array:
	return DayRules.end_day(c, s)


func test_academy_has_plan_map() -> void:
	var c := content()
	check(MapRules.has_map(c, "academy"), "у Академии карта-план")
	check(GateRules.active(c, _academy()), "у Академии есть прорывы")
	var cfg := MapRules.config(c, "academy")
	for lid: String in ["admin", "range", "lab"]:
		check(c.locations.has(lid) and cfg["places"].has(lid), "новое место Академии: %s" % lid)
	eq(Array(cfg["threat"]["points"].keys()).size(), 7, "точек прорыва (B0–B6):")


func test_signal_open_swarm_damage_repair() -> void:
	var c := content()
	var s := _academy()
	s.party_at = "capsules"
	var ev := GateRules.raise_signal(c, s, "B3")
	eq(GateRules.stage(s, "B3"), "signal", "сигнал у восточной стены:")
	check(str(s.missions.get("BA04", {}).get("status", "")) == "open", "миссия сигнала открыта")
	check(ev.any(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "breach_signal"), "событие сигнала")
	_night(c, s)
	eq(GateRules.stage(s, "B3"), "open", "ночью — прорыв:")
	check(GateRules.alarm(s), "Тревога")
	eq(GateRules.site_state(s, "medbay"), "alarm", "медкрыло в тревоге:")
	check(str(s.missions.get("BA09", {}).get("status", "")) == "open", "миссия пролома открыта")
	_night(c, s)   # пролом не закрыли
	eq(GateRules.swarms(s).size(), 1, "рой вошёл в кампус:")
	eq(str(GateRules.swarms(s)[0]["at"]), "medbay", "рой в медкрыле:")
	eq(GateRules.stage(s, "B3"), "sealed", "пролом заложили за спиной роя:")
	_night(c, s)   # рой не отбили
	check(GateRules.site_state(s, "medbay") in ["damaged", "burning"], "медкрыло повреждено: %s" % GateRules.site_state(s, "medbay"))
	check(str(GateRules.swarms(s)[0]["at"]) != "medbay", "рой пошёл дальше: %s" % str(GateRules.swarms(s)[0]["at"]))
	# рой отбили — тревога кончается, медкрыло в ремонт
	var at := str(GateRules.swarms(s)[0]["at"])
	GateRules.command(c, s, {"do": "clear", "place": at})
	check(not GateRules.alarm(s), "рой отбит — тревоги нет")
	_night(c, s)
	eq(GateRules.site_state(s, "medbay"), "repair", "после тревоги — ремонт:")
	for i in 5:
		_night(c, s)
	eq(GateRules.site_state(s, "medbay"), "", "отремонтировано:")


func test_seal_and_delay() -> void:
	var c := content()
	var s := _academy(7)
	GateRules.raise_signal(c, s, "B1")
	GateRules.command(c, s, {"do": "delay", "point": "B1"})
	_night(c, s)
	eq(GateRules.stage(s, "B1"), "signal", "отсрочка: ещё сигнал:")
	_night(c, s)
	eq(GateRules.stage(s, "B1"), "open", "через день — прорыв:")
	GateRules.command(c, s, {"do": "seal", "point": "B1"})
	eq(GateRules.stage(s, "B1"), "sealed", "закрыт миссией:")
	_night(c, s)
	eq(GateRules.swarms(s).size(), 0, "закрытый прорыв роя не выпускает:")


func test_mission_command_seals() -> void:
	var c := content()
	var s := _academy(9)
	GateRules.raise_signal(c, s, "B2")
	_night(c, s)
	eq(GateRules.stage(s, "B2"), "open", "прорыв у ворот:")
	check(str(s.missions.get("NA02", {}).get("status", "")) == "open", "«Рой у ворот» — миссия прорыва")
	var rng := RandomNumberGenerator.new()
	EffectApplier.apply_all(c, s, c.missions["NA02"].get("on_complete", []), "P01", rng)
	eq(GateRules.stage(s, "B2"), "sealed", "выполненная миссия закрывает прорыв:")


func test_barricade_bypass_and_core() -> void:
	var c := content()
	var s := _academy(11)
	s.flags["swarms"] = [{"at": "arena", "from": "", "point": "B1"}]
	GateRules.set_site(s, "arena", "alarm")
	GateRules.command(c, s, {"do": "barricade", "place": "arena"})
	eq(GateRules.site_state(s, "arena"), "barricaded", "арена забаррикадирована:")
	check(not TravelRules.passable(c, s, "arena"), "через баррикаду не пройти")
	var at := str(GateRules.swarms(s)[0]["at"]) if not GateRules.swarms(s).is_empty() else ""
	check(at != "arena", "рой обошёл баррикаду: %s" % at)
	# рой у Зала капсул — оборона
	s.flags["swarms"] = [{"at": "admin", "from": "", "point": "B1"}]
	GateRules.set_site(s, "admin", "alarm")
	_night(c, s)   # рой у административного корпуса не встретили — шаг к Залу капсул
	var core_open := str(s.missions.get("BA27", {}).get("status", "")) == "open"
	var at_core := GateRules.swarms(s).any(func(x: Dictionary) -> bool: return str(x.get("at", "")) == "capsules")
	check(core_open and at_core, "рой у Зала капсул — «Настоящая тревога»")
	eq(GateRules.site_state(s, "capsules"), "lockdown", "Зал капсул закрыт ставнями:")


func test_alarm_camp() -> void:
	var c := content()
	var s := _academy(13)
	s.party_at = "dorm"
	var calm := DayRules.camp(c, s)
	GateRules.set_site(s, "dorm", "alarm")
	s.flags["swarms"] = [{"at": "yard", "from": "", "point": "B1"}]
	var hot := DayRules.camp(c, s)
	check(int(hot["rest"]) < int(calm["rest"]), "в тревоге отдых хуже: %d < %d" % [int(hot["rest"]), int(calm["rest"])])
	check(not Array(hot["services"]).has("equip"), "в тревоге службы закрыты")
	GateRules.set_site(s, "dorm", "burning")
	eq(int(DayRules.camp(c, s)["beds"]), 0, "в горящем корпусе коек нет:")


## Прогоны бота по Академии: глава проходится, прорывы случаются и закрываются, тупиков нет.
func test_academy_runs() -> void:
	var c := content()
	var runs := 20
	var done := 0
	var signals := 0
	var swarms := 0
	var empty := 0
	var stuck := ""
	var died := 0
	for sd in runs:
		var s := MissionFlow.new_run(c, 7000 + sd * 13, "academy")
		var last := 0
		for step in 1200:
			if s.day != last:
				last = s.day
				if DayPlanner.count_today(c, s) == 0 and not MissionFlow.free_heroes(c, s).is_empty() and s.squads.is_empty():
					empty += 1
				for pid: String in GateRules.points(s):
					if GateRules.stage(s, pid) == "signal":
						signals += 1
				swarms += GateRules.swarms(s).size()
			s = AutoPlay.step(c, s)["state"]
			if s.demo_complete or s.game_over or s.chapter != "academy":
				break
		if s.demo_complete or s.chapter != "academy":
			done += 1
		elif s.game_over:
			died += 1   # Санни один, без Кошмара за плечами, может погибнуть — это не тупик
		elif stuck == "":
			stuck = "зерно %d: день %d, конец игры %s, открыто %s, отряды %s, герои %s" % [7000 + sd * 13, s.day, s.game_over,
				str(MissionFlow.open_missions(s)), str(s.squads.map(func(q: Dictionary) -> String: return "%s:%s" % [q["mission"], q["phase"]])),
				str(MissionFlow.heroes(c, s))]
	print("   [Академия] прогонов: %d, пройдено: %d, гибель: %d, дней-сигналов: %d, дней роя: %d, пустых утр: %d" % [runs, done, died, signals, swarms, empty])
	check(done + died == runs, "Академия не застревает: пройдено %d, гибель %d из %d · %s" % [done, died, runs, stuck])
	check(done >= runs * 3 / 4, "Академия проходится: %d из %d" % [done, runs])
	check(signals > 0, "прорывы случаются")
	eq(empty, 0, "пустых утр:")
