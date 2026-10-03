extends TestCase
## Прорывы Академии (GateRules, docs «Глава 2 — Академия — карта»): карта-план, сигнал → прорыв → рой → повреждение
## → ремонт, закрытие миссией, отсрочка, баррикада, оборона Зала капсул, лагерь в тревоге.


func _academy(seed_value: int = 5) -> RunState:
	var s := MissionFlow.new_run(content(), seed_value, "academy")
	s.flags["movement"] = "steps"   # ход прорыва по ночам — со старыми сроками (с фигурой сроки вдвое длиннее, docs/18)
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


# --- Город людей: Врата Кошмара (kind gate) ------------------------------------------------------

func _city(seed_value: int = 5) -> RunState:
	var s := AutoPlay.draft_start(content(), "city", seed_value)
	for mid: String in MissionFlow.open_missions(s):
		s.missions[mid]["status"] = "done"
	return s


## Довести до ночной фазы (Врата открываются только ночью).
func _to_night(c: Content, s: RunState) -> void:
	for i in 6:
		if str(DayRules.phase(c, s)["id"]) == "night":
			return
		DayRules.end_day(c, s)


func test_city_map() -> void:
	var c := content()
	check(MapRules.has_map(c, "city"), "у Города карта-план")
	var s := _city()
	eq(GateRules.kind(c, s), "gate", "в Городе — Врата:")
	eq(s.characters.size(), 3, "глава-черновик начинается с отрядом региона:")
	var cfg := MapRules.config(c, "city")
	eq(Array(cfg["threat"]["points"].keys()).size(), 8, "точек Врат (G1–G8):")
	for lid: String in c.locations:
		if str(c.locations[lid].get("chapter", "")) == "city":
			check(cfg["threat"]["swarm"].has(lid), "у квартала %s есть миссия волны" % lid)


func test_gate_opens_at_night_wave_ruins() -> void:
	var c := content()
	var s := _city(21)
	s.party_at = "academy_link"
	GateRules.raise_signal(c, s, "G2")
	eq(GateRules.stage(s, "G2"), "signal", "предвестие у промзоны:")
	var opened := false
	for i in 8:
		DayRules.end_day(c, s)
		if GateRules.stage(s, "G2") == "open":
			opened = true
			break
	check(opened, "Врата открылись")
	eq(str(DayRules.phase(c, s)["id"]), "night", "только ночью:")
	check(GateRules.panic(s) > 0, "паника выросла: %d" % GateRules.panic(s))
	check(str(s.missions.get("CG2", {}).get("status", "")) == "open", "миссия Врат открыта")
	check(GateRules.swarms(s).any(func(w: Dictionary) -> bool: return str(w["point"]) == "G2"), "из Врат вышла волна")
	eq(GateRules.site_state(s, "industry"), "fight", "в промзоне бой:")
	# волну не встретили: квартал повреждён, затем разрушен, волна идёт дальше
	var ruined := false
	for i in 10:
		DayRules.end_day(c, s)
		if GateRules.site_state(s, "industry") == "ruined":
			ruined = true
			break
	check(ruined, "без помощи промзона разрушена")
	# закрыли Врата — шрам, паника падает
	var before := GateRules.panic(s)
	GateRules.command(c, s, {"do": "close", "point": "G2"})
	eq(GateRules.stage(s, "G2"), "scar", "закрытые Врата — шрам:")
	check(GateRules.panic(s) < before, "паника падает, когда Врата закрыты")


func test_evacuate_and_bridge() -> void:
	var c := content()
	var s := _city(31)
	GateRules.command(c, s, {"do": "evacuate", "place": "market"})
	check(GateRules.evacuated(s, "market"), "рынок эвакуирован")
	var w := {"at": "market", "from": "", "point": "G4", "nights": 0, "path": ["market"]}
	var out: Array = []
	GateRules._wave_arrive(c, s, w, out)
	check(bool(w.get("passing", false)), "волна проходит мимо эвакуированного квартала")
	eq(GateRules.site_state(s, "market"), "damaged", "но квартал задет:")
	GateRules.command(c, s, {"do": "blow", "place": "bridges"})
	check(GateRules.blocked(s, "bridges"), "взорванный мост не пройти")
	eq(GateRules._wave_target(c, s, "market", ["market"]) != "bridges", true, "волна не идёт на взорванный мост:")
	s.party_at = "market"
	check(TravelRules.route(c, s, "market", "port").is_empty(), "порт отрезан")


func test_big_alarm() -> void:
	var c := content()
	var s := _city(41)
	s.flags["gates"] = {"G1": {"stage": "open", "open_day": s.day, "rank": 1}, "G4": {"stage": "open", "open_day": s.day, "rank": 2}}
	check(GateRules.big_alarm(c, s), "двое Врат — Тревога")
	GateRules._city_alarm_states(c, s)
	eq(GateRules.site_state(s, "bunker"), "crowded", "убежище переполнено:")
	eq(GateRules.site_state(s, "metro_hub"), "closed", "подземка закрыта:")
	s.flags["gates"] = {}
	GateRules._city_alarm_states(c, s)
	eq(GateRules.site_state(s, "bunker"), "", "Тревога снята — убежище как обычно:")


func test_gate_rank_mods() -> void:
	var c := content()
	var s := _city(51)
	GateRules.command(c, s, {"do": "raise", "point": "G3", "rank": 3, "open": true})
	eq(GateRules.stage(s, "G3"), "open", "сюжет открыл Врата:")
	check(Array(s.missions["CG3"].get("mods", [])).has("gate_rank3"), "ранг 3 — модификатор силы")
	check(ModifierRules.threat(c, s, "CG3") > int(c.missions["CG3"]["threat"]), "угроза выше")


## Прогоны бота по Городу: глава проходится, Врата открываются и закрываются, пустых утр нет.
func test_city_runs() -> void:
	var c := content()
	var runs := 15
	var done := 0
	var died := 0
	var stuck := ""
	var opened := 0
	var closed := 0
	var empty := 0
	var max_panic := 0
	for sd in runs:
		var s := AutoPlay.draft_start(c, "city", 9000 + sd * 11)
		var last := 0
		var seen_open := {}
		for step in 2000:
			if s.day != last:
				last = s.day
				if DayPlanner.count_today(c, s) == 0 and not MissionFlow.free_heroes(c, s).is_empty() and s.squads.is_empty():
					empty += 1
				for pid: String in GateRules.points(s):
					var key := "%s@%d" % [pid, int(GateRules.points(s)[pid].get("open_day", 0))]
					if GateRules.stage(s, pid) == "open" and not seen_open.has(key):
						seen_open[key] = true
						opened += 1
					if GateRules.stage(s, pid) == "scar" and int(GateRules.points(s)[pid].get("closed_day", -1)) == s.day - 1:
						closed += 1
				max_panic = maxi(max_panic, GateRules.panic(s))
			s = AutoPlay.step(c, s)["state"]
			if s.demo_complete or s.game_over:
				break
		if s.demo_complete:
			done += 1
		elif s.game_over:
			died += 1
		elif stuck == "":
			stuck = "зерно %d: день %d, открыто %s, отряды %s, герои %s" % [9000 + sd * 11, s.day, str(MissionFlow.open_missions(s)),
				str(s.squads.map(func(q: Dictionary) -> String: return "%s:%s" % [q["mission"], q["phase"]])), str(MissionFlow.heroes(c, s))]
	print("   [Город] прогонов: %d, пройдено: %d, гибель: %d, Врат открыто: %d, закрыто: %d, паника до %d, пустых утр: %d" % [runs, done, died, opened, closed, max_panic, empty])
	check(done + died == runs, "Город не застревает: %s" % stuck)
	check(done >= runs * 2 / 3, "Город проходится: %d из %d" % [done, runs])
	check(opened > 0, "Врата открываются")
	eq(empty, 0, "пустых утр:")
