extends TestCase
## «Схватка» в мире игры (docs/24 §8, Ф5): переключатель, пауза миссии на боевом этапе и продолжение, бой ИИ у бота,
## свет от неба и поля, засада, тренировка без грани, раны до ночи, бот проходит Берег в режиме «Схватки».


func _run(seed_value: int = 3) -> RunState:
	var s := MissionFlow.new_run(content(), seed_value)
	s.flags["combat"] = "skirmish"
	s.missions["MS03"] = {"status": "open", "attempts": 0}
	return s


func _arrive(c: Content, s: RunState, mid: String, heroes: Array) -> int:
	var r := MissionFlow.launch(c, s, mid, heroes)
	check(r["ok"], "отряд должен уйти: %s" % r.get("error", ""))
	return int(r["squad"]["id"])


func test_switch() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 1)
	check(not SkirmishRules.enabled(c, s), "по умолчанию — «Столкновение»")
	s.flags["combat"] = "skirmish"
	check(SkirmishRules.enabled(c, s), "флаг включает «Схватку»")


func test_pause_and_resume() -> void:
	var c := content()
	var s := _run()
	var sid := _arrive(c, s, "MS03", ["P01"])
	var r := MissionResolver.resolve(c, s, sid, "MS03_fight", true)
	if r["ok"] and r.has("fork"):   # «Подход» — затем развилка: идти дальше
		r = MissionResolver.resume(c, r["state"], sid, str(r["fork"]["options"][0]["id"]))
	check(r["ok"] and r.has("skirmish"), "боевой этап — пауза для игрока")
	if not r.has("skirmish"):
		return
	var spec: Dictionary = r["skirmish"]
	eq(spec["heroes"], ["P01"], "строй — отряд:")
	eq(str(MissionFlow.squad(r["state"], sid)["phase"]), "combat", "отряд в бою:")
	check(not MissionResolver.resolve(c, r["state"], sid, "MS03_fight", true)["ok"], "пока бой — другое действие не выбрать")
	# игрок сыграл бой (здесь — ИИ за героя) — миссия продолжается
	var sk := Skirmish.create(c, r["state"], spec)
	sk.auto(900)
	var r2 := MissionResolver.resume_combat(c, sk.state, sid, SkirmishRules.summary(sk, sk.finish()))
	check(r2["ok"] and not r2.has("skirmish"), "после боя миссия идёт дальше")
	var rep: Dictionary = r2["report"]
	eq(rep["combats"].size(), 1, "бой записан в отчёт:")
	check(bool(rep["combats"][0].get("skirmish", false)), "это «Схватка»")
	check(rep["stages"].size() >= 2, "этапы после боя пройдены")
	check(str(rep["outcome"]) != "", "миссия завершилась")


func test_bot_plays_skirmish() -> void:
	var c := content()
	var s := _run(5)
	var sid := _arrive(c, s, "MS03", ["P01"])
	var r := MissionResolver.resolve_through(c, s, sid, "MS03_fight")
	check(r["ok"] and not r.has("skirmish"), "без игрока «Схватку» играет ИИ")
	check(bool(r["report"]["combats"][0].get("skirmish", false)), "бой — «Схватка»")
	var hp_known: bool = r["state"].character("P01").has("hp") or not r["state"].is_alive("P01")
	check(hp_known or str(r["report"]["combats"][0]["outcome"]) == "win", "раны записаны (или бой без ран)")


func test_light_and_ambush() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 2, "shore")
	s.flags["figure_half"] = 0
	var sky := Atmosphere.sky(c, s)
	var lt := SkirmishRules.light(c, s, "F_17")
	if sky == "day":
		eq(lt, "bright" if str(DayRules.phase(c, s).get("id", "")) != "dawn" else "dim", "день, утро — ярко:")
		s.flags["figure_half"] = 1
		eq(SkirmishRules.light(c, s, "F_17"), "dim", "после полудня — тускло:")
	var base := SkirmishRules.LIGHTS.find(SkirmishRules.light(c, s, "F_17"))
	var cave := SkirmishRules.LIGHTS.find(SkirmishRules.light(c, s, "F_21"))
	check(cave == mini(3, base + 1), "в пещере на ступень темнее")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	eq(SkirmishRules.ambush(c, s, ["P01"], ["M03"], "dim", {"combat": {"ambush": "enemy"}}, rng), "enemies", "«зайти со спины» — враги застигнуты:")
	var counts := {"": 0, "heroes": 0, "enemies": 0}
	for i in 400:
		counts[SkirmishRules.ambush(c, s, ["P01"], ["M06"], "dark", {}, rng)] += 1
	check(counts["heroes"] > counts["enemies"], "во тьме и с Засадой у врагов застигают чаще отряд: %s" % str(counts))


func test_spar_and_night_heal() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 4, "shore")
	EffectApplier.add_card(c, s, "P02")
	var sk := Skirmish.create(c, s, {"heroes": ["P02"], "enemies": ["M03"], "spar": true})
	var n := sk.by_uid("h0")
	sk.hurt(n, 999, sk.by_uid("e0"), "hit")
	eq(sk.outcome, "loss", "тренировка — до первой грани:")
	check(not EdgeRules.on_edge(sk.state, "P02") and n.hp == 1, "в тренировке на грань не падают")
	s.character("P02")["hp"] = 3
	var mx := SkBuild.hero(c, s, "P02").hp_max
	SkirmishRules.night_heal(c, s)
	eq(int(s.character("P02").get("hp", mx)), mini(mx, 3 + int(ceil(mx * SkirmishRules.NIGHT_HEAL))), "ночь — половина здоровья:")
	SkirmishRules.night_heal(c, s)
	check(not s.character("P02").has("hp"), "вторая ночь — здоров")


func test_bot_through_shore() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 77, "shore")
	s.flags["combat"] = "skirmish"
	for i in 600:
		var r := AutoPlay.step(c, s)
		check(str(r["error"]) == "", "бот без ошибок: %s" % r["error"])
		s = r["state"]
		if bool(r.get("finished", false)) or s.game_over:
			break
	var fights: int = s.missions.values().filter(func(m: Dictionary) -> bool: return str(m.get("status", "")) == "done").size()
	check(fights > 0, "бот проходит события в режиме «Схватки»")
	print("   [схватка в мире] дней: %d, пройдено событий: %d, глава: %s, живы: %s" % [s.day, fights, s.chapter, str(MissionFlow.heroes(c, s))])
