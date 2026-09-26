extends TestCase
## Ф8 (docs/16 §2–4): развилка на этапе, цена действия, миссия-выбор, устаревание, босс в несколько заходов, небо.


func _arrive(c: Content, s: RunState, mid: String, heroes: Array) -> int:
	if not s.missions.has(mid) or s.missions[mid]["status"] != "open":
		s.missions[mid] = {"status": "open", "attempts": 0, "opened_at": s.clock}
	var r := MissionFlow.launch(c, s, mid, heroes)
	check(r["ok"], "отряд ушёл: %s" % r.get("error", ""))
	MissionFlow.tick(c, s, 20.0)
	return int(r["squad"]["id"])


func test_fork_stops_and_resumes() -> void:
	var c := content()
	var seen := {"push": false, "debris": false, "back": false}
	for opt: String in seen:
		var s := MissionFlow.new_run(c, 11)
		var sid := _arrive(c, s, "MS03", ["P01"])
		var r := MissionResolver.resolve(c, s, sid, "MS03_fight")
		check(r["ok"] and r.has("fork"), "после подхода — развилка")
		s = r["state"]
		eq(MissionFlow.squad(s, sid)["phase"], "fork", "отряд ждёт решения:")
		eq(Array(r["report"]["stages"]).size(), 1, "пройден один этап:")
		check(not MissionResolver.resolve(c, s, sid, "MS03_fight")["ok"], "второй раз действие не выбрать")
		# сохранение посреди развилки
		s = RunState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
		var r2 := MissionResolver.resume(c, s, sid, opt)
		check(r2["ok"], "выбор %s принят" % opt)
		var rep: Dictionary = r2["report"]
		eq(Array(rep["forks"]).size(), 1, "развилка в отчёте:")
		check(MissionFlow.squad(r2["state"], sid).is_empty(), "отряд вернулся")
		match opt:
			"push":
				eq(Array(rep["stages"]).size(), 3, "продолжили — все три этапа:")
			"debris":
				eq(Array(rep["stages"]).size(), 2, "сменили путь — подход и обвал:")
				eq(str(rep["stages"][1]["name"]), "Обвал", "второй этап — из развилки:")
			"back":
				eq(rep["outcome"], "retreat", "отступили с добытым:")
				eq(r2["state"].missions["MS03"]["status"], "open", "миссия осталась:")
		seen[opt] = true


func test_sacrifice_guaranteed() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 3)
	EffectApplier.add_card(c, s, "U02")
	s.characters["P01"]["stage"] = "sleeper"
	var sid := _arrive(c, s, "MS09", ["P01"])
	var avail: Dictionary = MissionFlow.actions_for(c, s, "MS09", ["P01"]).filter(func(e: Dictionary) -> bool: return e["action"]["id"] == "MS09_throw_bell")[0]
	check(not avail["available"], "Колокольчик не в кармашке — бросить нечего")
	s.characters["P01"]["pocket"] = ["U02"]
	avail = MissionFlow.actions_for(c, s, "MS09", ["P01"]).filter(func(e: Dictionary) -> bool: return e["action"]["id"] == "MS09_throw_bell")[0]
	check(avail["available"], "в кармашке — можно отдать")
	var f := MissionForecast.action_forecast(c, s, "MS09", avail["action"], ["P01"], true)
	eq(f["word"], "Уверенно", "успех наверняка — «Уверенно»:")
	var r := MissionResolver.resolve(c, s, sid, "MS09_throw_bell")
	check(r["ok"], "действие с ценой")
	eq(r["report"]["outcome"], "success", "успех гарантирован:")
	check(not r["state"].owns("U02"), "Колокольчик отдан")


func test_exclusive_pair() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 5)
	MissionFlow.open(c, s, "SM02")
	MissionFlow.open(c, s, "SM03")
	var sid := _arrive(c, s, "SM02", ["P01"])
	var ns: RunState = s
	for i in 30:
		var r := MissionResolver.resolve(c, ns, sid, "SM02_carry")
		ns = r["state"]
		if r["report"]["outcome"] in ["success", "partial"]:
			break
		ns.rest_until.clear()
		sid = _arrive(c, ns, "SM02", ["P01"])
	eq(ns.missions["SM03"]["status"], "closed", "выполнили одну — вторая упущена:")


func test_expires() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 5)
	MissionFlow.open(c, s, "SM02")
	check(MissionFlow.expires_in(c, s, "SM02") > 100.0, "срок идёт")
	var ev := MissionFlow.tick(c, s, 151.0)
	eq(s.missions["SM02"]["status"], "expired", "не успели — ушла:")
	check(ev.any(func(e: Dictionary) -> bool: return e["kind"] == "expired"), "игроку сказано")
	check(not MissionFlow.open_missions(s).has("SM02"), "с карты убрана")


func test_boss_phases() -> void:
	var c := content()
	var advanced := false
	for seed_value in 80:
		var s := MissionFlow.new_run(c, 900 + seed_value)
		s.characters["P01"]["stage"] = "sunless"
		EffectApplier.add_card(c, s, "P08")
		var sid := _arrive(c, s, "MS05", ["P01", "P08"])
		eq(MissionFlow.boss_stage(s, c.missions["MS05"], c.missions["MS05"]["actions"][1]["stages"][0])["combat"]["field"], "F_03", "первый заход — у обрыва:")
		var r := MissionResolver.resolve(c, s, sid, "MS05_hold")
		if r["report"].has("boss_phase"):
			var ns: RunState = r["state"]
			eq(ns.missions["MS05"]["status"], "open", "после победы в первом заходе босс не добит:")
			eq(int(ns.missions["MS05"]["phase"]), 1, "второй заход:")
			eq(MissionFlow.boss_stage(ns, c.missions["MS05"], c.missions["MS05"]["actions"][1]["stages"][0])["combat"]["field"], "F_04", "поле сменилось:")
			eq(Atmosphere.story_sky(c, ns), "blood_moon", "небо второго захода:")
			advanced = true
			break
	check(advanced, "хоть раз первый заход выигран")


func test_sky_affects_checks() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 1)
	var night: Dictionary = StatResolver.resolve(c, s, "P01", [], {"tags": []}, {"tags": ["stealth"]})["totals"]
	s.clock = Atmosphere.DAY_CYCLE * 0.6
	var day: Dictionary = StatResolver.resolve(c, s, "P01", [], {"tags": []}, {"tags": ["stealth"]})["totals"]
	eq(int(night["cunning"]) - int(day["cunning"]), 1, "ночью скрытность +1 Хитрость:")
	var plain: Dictionary = StatResolver.resolve(c, s, "P01", [], {"tags": []}, {"tags": []})["totals"]
	var day_climb: Dictionary = StatResolver.resolve(c, s, "P01", [], {"tags": []}, {"tags": ["climb"]})["totals"]
	eq(int(day_climb["cunning"]), int(plain["cunning"]) + 1, "днём подъём +1 Хитрость:")


func test_sky_in_combat() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 1)
	var spec := {"enemies": ["M01", "M01"], "field": "F_05"}
	var cs := CombatSession.create_for_mission(c, s, "T", spec, "P01", [], [], {"tags": []}, {"tags": []})
	cs.round_no = 1
	var plain := float(cs.ledger({})["enemy"])
	MissionFlow.open(c, s, "MS05")
	var cs2 := CombatSession.create_for_mission(c, s, "T", spec, "P01", [], [], {"tags": []}, {"tags": []})
	cs2.round_no = 1
	check(float(cs2.ledger({})["enemy"]) > plain, "под кровавой луной враг сильнее")
