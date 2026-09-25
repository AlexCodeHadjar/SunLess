extends TestCase
## Ядро миссий (docs/15, Ф2): отряды, часы, действия, этапы, прогноз, отдых, смерть навсегда.


func _run(seed_value: int = 7) -> RunState:
	return MissionFlow.new_run(content(), seed_value)


## Отправить отряд и промотать часы до прибытия. Возвращает id отряда.
func _arrive(c: Content, s: RunState, mid: String, heroes: Array) -> int:
	var r := MissionFlow.launch(c, s, mid, heroes)
	check(r["ok"], "отряд должен уйти: %s" % r.get("error", ""))
	MissionFlow.tick(c, s, float(c.missions[mid]["duration"]))
	return int(r["squad"]["id"])


func test_new_run() -> void:
	var s := _run()
	eq(s.mode, "missions", "режим:")
	check(s.is_alive("P01"), "Санни жив")
	eq(MissionFlow.open_missions(s), ["MS02"], "с начала открыта только стартовая миссия:")
	check(not s.resources.has("mana"), "маны в режиме миссий нет")


func test_launch_rules() -> void:
	var c := content()
	var s := _run()
	check(MissionFlow.can_launch(c, s, "MS03", ["P01"]) != "", "закрытую миссию не запустить")
	check(MissionFlow.can_launch(c, s, "MS02", []) != "", "пустой отряд не уходит")
	check(MissionFlow.can_launch(c, s, "MS02", ["P01", "P01"]) != "", "в MS02 одно место")
	var r := MissionFlow.launch(c, s, "MS02", ["P01"])
	check(r["ok"], "отряд ушёл")
	eq(MissionFlow.busy_reason(c, s, "P01"), "на миссии", "Санни занят:")
	eq(s.missions["MS02"]["status"], "active", "миссия в работе:")
	check(MissionFlow.can_launch(c, s, "MS02", ["P01"]) != "", "вторично ту же миссию не запустить")


func test_clock_and_arrival() -> void:
	var c := content()
	var s := _run()
	var r := MissionFlow.launch(c, s, "MS02", ["P01"])
	var ev := MissionFlow.tick(c, s, 2.0)
	eq(MissionFlow.squad(s, int(r["squad"]["id"]))["phase"], "travel", "через 2 с ещё в пути:")
	check(ev.is_empty(), "событий пока нет")
	ev = MissionFlow.tick(c, s, 10.0)
	eq(MissionFlow.squad(s, int(r["squad"]["id"]))["phase"], "arrived", "прибыл:")
	check(ev.size() == 1 and ev[0]["kind"] == "arrived", "событие «прибыл»")


func test_actions_depend_on_squad() -> void:
	var c := content()
	var s := _run()
	var acts := MissionFlow.actions_for(c, s, "MS02", ["P01"])
	var over: Dictionary = acts.filter(func(e: Dictionary) -> bool: return e["action"]["id"] == "MS02_overhear")[0]
	check(over["available"], "у Санни есть Скрытность/Чутьё — подслушать можно")
	acts = MissionFlow.actions_for(c, s, "MS03", ["P01"])
	var debris: Dictionary = acts.filter(func(e: Dictionary) -> bool: return e["action"]["id"] == "MS03_debris")[0]
	check(debris["available"], "у Санни-раба есть Импровизация — обломки доступны")
	c.characters["P01"]["stages"]["slave"]["tags"].erase("Импровизация")
	acts = MissionFlow.actions_for(c, s, "MS03", ["P01"])
	debris = acts.filter(func(e: Dictionary) -> bool: return e["action"]["id"] == "MS03_debris")[0]
	check(not debris["available"], "без Импровизации обломки закрыты")


func test_resolve_updates_state() -> void:
	var c := content()
	# в данных MS02 для Санни почти беспроигрышна — ужесточаем, чтобы встретить и провал
	c.missions["MS02"]["actions"][0]["stages"][0]["req"] = {"cunning": 14}
	var saw_success := false
	var saw_failure := false
	for seed_value in range(1, 40):
		var s := _run(seed_value)
		var sid := _arrive(c, s, "MS02", ["P01"])
		var clock := s.clock
		var r := MissionResolver.resolve(c, s, sid, "MS02_watch")
		check(r["ok"], "действие выполнено")
		var ns: RunState = r["state"]
		var rep: Dictionary = r["report"]
		check(ns.squads.is_empty(), "отряд вернулся")
		eq(rep["stages"].size(), 2, "два этапа:")
		if ns.is_alive("P01"):
			check(float(ns.rest_until["P01"]) >= clock + 20.0, "Санни отдыхает не меньше 20 с")
		if rep["outcome"] in ["success", "partial"]:
			saw_success = true
			eq(ns.missions["MS02"]["status"], "done", "миссия выполнена:")
			eq(ns.missions.get("MS03", {}).get("status", ""), "open", "сюжет открыл MS03:")
			eq(ns.completed_missions, 1, "счётчик миссий:")
		else:
			saw_failure = true
			eq(ns.missions["MS02"]["status"], "open", "проваленную можно повторить:")
			eq(int(ns.missions["MS02"]["attempts"]), 1, "попытка засчитана:")
		check(s.squads.size() == 1, "исходное состояние не тронуто (транзакция)")
	check(saw_success, "за 40 прохождений хотя бы один успех")
	check(saw_failure, "за 40 прохождений хотя бы один провал")


func test_retreat() -> void:
	var c := content()
	var s := _run()
	var sid := _arrive(c, s, "MS02", ["P01"])
	var r := MissionResolver.resolve(c, s, sid, "MS02_lay_low")
	var ns: RunState = r["state"]
	eq(r["report"]["outcome"], "retreat", "итог:")
	eq(ns.missions["MS02"]["status"], "open", "после отступления миссия снова открыта:")
	eq(int(ns.missions["MS02"]["attempts"]), 0, "отступление — не попытка:")
	eq(float(r["report"]["rest"]["P01"]), 20.0, "отряд устаёт как после миссии:")
	check(r["report"]["traumas"].is_empty(), "без ран")


func test_locked_action_refused() -> void:
	var c := content()
	c.characters["P01"]["stages"]["slave"]["tags"].erase("Импровизация")
	var s := _run()
	s.missions["MS03"] = {"status": "open", "attempts": 0}
	var sid := _arrive(c, s, "MS03", ["P01"])
	var r := MissionResolver.resolve(c, s, sid, "MS03_debris")
	check(not r["ok"], "закрытое действие не выполнить")


func test_combat_stage_runs() -> void:
	var c := content()
	var s := _run(3)
	s.missions["MS03"] = {"status": "open", "attempts": 0}
	var sid := _arrive(c, s, "MS03", ["P01"])
	var r := MissionResolver.resolve(c, s, sid, "MS03_fight")
	check(r["ok"], "бой прошёл")
	var rep: Dictionary = r["report"]
	eq(rep["combats"].size(), 1, "один автобой:")
	check(Array(rep["combats"][0]["rounds"]).size() >= 2, "в автобое сыграно не меньше двух раундов")
	check(rep["stages"][1].has("combat"), "второй этап — бой")


func test_rest_and_tick() -> void:
	var c := content()
	var s := _run()
	var sid := _arrive(c, s, "MS02", ["P01"])
	s = MissionResolver.resolve(c, s, sid, "MS02_lay_low")["state"]
	check(MissionFlow.busy_reason(c, s, "P01").begins_with("отдыхает"), "Санни отдыхает")
	var ev := MissionFlow.tick(c, s, 25.0)
	eq(MissionFlow.busy_reason(c, s, "P01"), "", "отдохнул:")
	check(ev.any(func(e: Dictionary) -> bool: return e["kind"] == "rested"), "событие «отдохнул»")


func test_save_roundtrip() -> void:
	var c := content()
	var s := _run()
	MissionFlow.launch(c, s, "MS02", ["P01"])
	MissionFlow.tick(c, s, 3.5)
	var s2 := RunState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	eq(s2.mode, "missions", "режим:")
	eq(s2.clock, 3.5, "часы:")
	eq(s2.squads.size(), 1, "отряд в пути сохранился:")
	eq(MissionFlow.busy_reason(c, s2, "P01"), "на миссии", "Санни всё ещё на миссии:")


func test_death_is_permanent_and_game_over_when_nobody_left() -> void:
	var c := content()
	var s := _run()
	EffectApplier.add_card(c, s, "P09")
	var entries: Array = []
	TurnResolver._kill(c, s, "P01", entries)
	check(not s.game_over, "Санни погиб, но Шолар жив — игра идёт")
	check(not MissionFlow.heroes(c, s).has("P01"), "погибший уходит из состава")
	TurnResolver._kill(c, s, "P09", entries)
	check(s.game_over, "героев не осталось — конец")


func test_forecast_words_and_combine() -> void:
	eq(MissionForecast.word(10), "Безнадёжно", "")
	eq(MissionForecast.word(60), "Неясно", "")
	eq(MissionForecast.word(90), "Уверенно", "")
	eq(MissionForecast.combine(["ok", "ok"]), "success", "ok+ok:")
	eq(MissionForecast.combine(["ok", "partial"]), "success", "ok+partial:")
	eq(MissionForecast.combine(["ok", "fail"]), "failure", "ok+fail — провал короткой миссии:")
	eq(MissionForecast.combine(["ok", "ok", "fail"]), "partial", "ok+ok+fail — с потерями:")
	eq(MissionForecast.combine(["partial", "partial"]), "partial", "partial+partial:")
	eq(MissionForecast.combine(["partial", "fail", "fail"]), "failure", "partial+fail+fail:")
	eq(MissionForecast.combine(["partial"]), "partial", "один частичный:")


func test_forecast_blur_and_scout() -> void:
	var c := content()
	var s := _run()
	s.missions["MS03"] = {"status": "open", "attempts": 0}
	var f := MissionForecast.mission_forecast(c, s, "MS03", ["P01"])
	check(str(f["word"]) != "", "прогноз есть")
	check(str(f["risk_word"]) != "", "риск есть")
	EffectApplier.add_card(c, s, "P09")   # Шолар: Выслеживание — разведчик
	var f2 := MissionForecast.mission_forecast(c, s, "MS03", ["P01", "P09"])
	check(not f2["blurred"], "с разведчиком прогноз чёткий")


## Честность прогноза: доля успехов (успех + ½ частичного) близка к обещанному значению.
func test_forecast_is_honest() -> void:
	var c := content()
	for pair: Array in [["MS02", "MS02_watch"], ["MS02", "MS02_scholar"], ["MS03", "MS03_fight"], ["MS03", "MS03_debris"]]:
		var mid: String = pair[0]
		var aid: String = pair[1]
		var s0 := _run(1)
		s0.missions[mid] = {"status": "open", "attempts": 0}
		var fc := MissionForecast.action_forecast(c, s0, mid, MissionFlow.action(c, mid, aid), ["P01"], true)
		var score := 0.0
		var n := 300
		for i in n:
			var s := _run(1000 + i)
			s.missions[mid] = {"status": "open", "attempts": 0}
			var sid := _arrive(c, s, mid, ["P01"])
			var rep: Dictionary = MissionResolver.resolve(c, s, sid, aid)["report"]
			score += {"success": 1.0, "partial": 0.5}.get(rep["outcome"], 0.0)
		var real := int(round(100.0 * score / n))
		print("   [прогноз] %s/%s: обещано %d (%s), на деле %d" % [mid, aid, int(fc["value"]), fc["word"], real])
		check(absi(real - int(fc["value"])) <= 15, "%s/%s: прогноз %d, на деле %d" % [mid, aid, int(fc["value"]), real])


## Бот играет миссии главы: отправляет свободных героев, ждёт прибытия, выбирает действие
## с лучшим прогнозом (или отступает, если всё безнадёжно). Игра не должна застревать.
func _bot(c: Content, seed_value: int) -> Dictionary:
	var s := MissionFlow.new_run(c, seed_value)
	var steps := 0
	var attempts := 0
	while steps < 400 and not s.game_over:
		steps += 1
		var open := MissionFlow.open_missions(s)
		if open.is_empty() and s.squads.is_empty():
			break
		for mid: String in open:
			var free := MissionFlow.free_heroes(c, s)
			var mx := int(c.missions[mid]["squad"]["max"])
			var team := free.slice(0, mini(mx, free.size()))
			if MissionFlow.can_launch(c, s, mid, team) == "":
				MissionFlow.launch(c, s, mid, team)
		MissionFlow.tick(c, s, 1.0)
		for sq: Dictionary in s.squads.duplicate():
			if sq["phase"] != "arrived":
				continue
			var best := ""
			var best_v := -1
			var retreat := ""
			for e: Dictionary in MissionFlow.actions_for(c, s, sq["mission"], sq["heroes"]):
				var a: Dictionary = e["action"]
				if bool(a.get("retreat", false)):
					retreat = str(a["id"])
				elif e["available"]:
					var v := int(MissionForecast.action_forecast(c, s, sq["mission"], a, sq["heroes"], true)["value"])
					if v > best_v:
						best_v = v
						best = str(a["id"])
			var pick := best if best_v >= 20 or retreat == "" else retreat
			var r := MissionResolver.resolve(c, s, int(sq["id"]), pick)
			if not r["ok"]:
				return {"stuck": true, "error": r["error"]}
			s = r["state"]
			attempts += 1
	var done := 0
	for mid: String in s.missions:
		if s.missions[mid]["status"] == "done":
			done += 1
	return {"stuck": steps >= 400, "over": s.game_over, "done": done, "attempts": attempts, "clock": s.clock,
		"story_done": s.missions.get("MS03", {}).get("status", "") == "done"}


func test_mission_simulation() -> void:
	var c := content()
	var n := 200
	var finished := 0
	var over := 0
	var total_attempts := 0
	var total_clock := 0.0
	for i in n:
		var r := _bot(c, 5000 + i)
		check(not r.get("stuck", false), "бот застрял (сид %d): %s" % [5000 + i, r.get("error", "")])
		if r.get("story_done", false):
			finished += 1
		if r.get("over", false):
			over += 1
		total_attempts += int(r.get("attempts", 0))
		total_clock += float(r.get("clock", 0.0))
	print("   [миссии] прохождений: %d, сюжет главы пройден: %d, гибель всех героев: %d" % [n, finished, over])
	print("   [миссии] попыток миссий в среднем: %.1f, игрового времени: %.0f с" % [float(total_attempts) / n, total_clock / n])
	check(finished >= n * 0.8, "сюжет пробных миссий проходится в большинстве прохождений")
