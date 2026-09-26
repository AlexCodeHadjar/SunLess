extends TestCase
## Ф10 (docs/16 §8): опыт тегов, «Опытный», эволюции и мутации, их эффекты.


func _run() -> RunState:
	var c := content()
	var s := MissionFlow.new_run(c, 21)
	s.chapter = "academy"   # живой отряд и рост работают с Академии (TutorialRules.UNLOCK)
	for cid: String in ["P02", "P03", "P04", "P09", "P10"]:
		EffectApplier.add_card(c, s, cid)
	MissionFlow.open(c, s, "MS02")
	return s


func _grow(s: RunState, cid: String, tag: String, kind: String) -> void:
	var ch := s.character(cid)
	var bag: Dictionary = ch.get("tag_xp", {})
	bag[tag] = GrowthRules.EVOLVE
	ch["tag_xp"] = bag
	var g: Dictionary = ch.get("growth", {})
	g[tag] = kind
	ch["growth"] = g


func test_data() -> void:
	var c := content()
	check(c.tag_growth.size() >= 20, "в данных есть рост для основных тегов")
	for tag: String in c.tag_growth:
		check(str(c.tag_growth[tag]["evo"].get("name", "")) != "" and str(c.tag_growth[tag]["mut"].get("name", "")) != "", "у «%s» есть эволюция и мутация" % tag)


func test_xp_and_evolution() -> void:
	var c := content()
	var s := _run()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var run := {}
	GrowthRules.mark(run, "P01", "Скрытность", 1.0)
	GrowthRules.mark(run, "P01", "Скрытность", 0.5)
	eq(float(run["tag_xp"]["P01"]["Скрытность"]), 1.0, "за миссию — лучшее участие:")
	var total := 0
	var kinds := {"evo": 0, "mut": 0}
	for i in 400:
		var s2 := _run()
		var got: Array = []
		for k in 6:
			var r := {}
			GrowthRules.mark(r, "P01", "Скрытность", 1.0)
			got.append_array(GrowthRules.apply(c, s2, r, ["P01"], "failure", rng))
		var st := GrowthRules.stage(s2, "P01", "Скрытность")
		if st in ["evo", "mut"]:
			kinds[st] += 1
			total += 1
		if i == 0:
			check(got.any(func(e: Dictionary) -> bool: return str(e["text"]).contains("опытный")), "на 3 опыта — «опытный»")
	eq(total, 400, "на 6 опыта тег всегда развивается:")
	check(kinds["mut"] > 50 and kinds["mut"] < 120, "мутация — около 20%% (%d из 400)" % kinds["mut"])
	var _u := s


func test_veteran_check() -> void:
	var c := content()
	var s := _run()
	var before := GrowthRules.check_parts(c, s, "P01", ["stealth"], [])
	check(before.is_empty(), "без опыта прибавок нет")
	s.character("P01")["tag_xp"] = {"Скрытность": 3.0}
	var after := GrowthRules.check_parts(c, s, "P01", ["stealth"], [])
	check(after.size() == 1 and int(after[0]["value"]) == 1, "опытный: +1 в скрытности")
	check(GrowthRules.check_parts(c, s, "P01", ["social"], []).is_empty(), "в общении — нет")


func test_effects() -> void:
	var c := content()
	var s := _run()
	# Эрудит: +1 Хитрость в знаниях
	_grow(s, "P09", "Разумный", "evo")
	check(GrowthRules.check_parts(c, s, "P09", ["knowledge"], []).any(func(p: Dictionary) -> bool: return p["source"] == "Эрудит"), "Эрудит в знаниях")
	# Сорвавший цепи: Раб → Свободный
	_grow(s, "P01", "Раб", "evo")
	var tags := MissionFlow.hero_tags(c, s, "P01")
	check(not tags.has("Раб") and tags.has("Свободный"), "тег Раб сменился на Свободный")
	# Лёд в венах: паника не выше 50
	_grow(s, "P01", "Хладнокровие", "evo")
	PanicRules.add(c, s, "P01", 200, "тест")
	eq(PanicRules.value(s, "P01"), 50, "паника упирается в 50:")
	# Бесчувственный: паники нет, связки не работают
	_grow(s, "P03", "Слабое тело", "mut")
	var s2 := _run()
	_grow(s2, "P01", "Хладнокровие", "mut")
	PanicRules.add(c, s2, "P01", 50, "тест")
	eq(PanicRules.value(s2, "P01"), 0, "Бесчувственный не паникует:")
	check(BondRules.active(c, s2, ["P01", "P03"]).is_empty(), "связка с Бесчувственным не работает")
	# Предвидение раскрывает скрытое
	var s3 := _run()
	check(not MissionFlow.has_scout(c, s3, ["P04"]), "Кастер не разведчик")
	_grow(s3, "P03", "Чутьё", "evo")
	check(MissionFlow.has_scout(c, s3, ["P03"]), "Предвидение раскрывает скрытое")
	# Отчаянная храбрость: Трус в панике не сбегает, а +3
	_grow(s3, "P10", "Трус", "mut")
	PanicRules.add(c, s3, "P10", 70, "тест")
	check(not PanicRules.flees(c, s3, "P10"), "храбрый Трус не сбегает")
	check(GrowthRules.check_parts(c, s3, "P10", [], []).filter(func(p: Dictionary) -> bool: return int(p["value"]) == 3).size() == 3, "+3 ко всему в панике")


func test_combat_steps() -> void:
	var c := content()
	var s := _run()
	_grow(s, "P04", "Первый удар", "mut")
	var r1 := GrowthRules.combat_steps(c, s, "P04", 1)
	var r3 := GrowthRules.combat_steps(c, s, "P04", 3)
	check(r1.any(func(g: Dictionary) -> bool: return is_equal_approx(float(g["pct"]), 0.25)), "Безрассудный: первый раунд +25%")
	check(r3.any(func(g: Dictionary) -> bool: return is_equal_approx(float(g["pct"]), -0.15)), "третий −15%")
	var cs := CombatSession.create_for_mission(c, s, "T", {"enemies": ["M01"], "field": "F_05"}, "P04", [], [], {"tags": []}, {"tags": []})
	cs.round_no = 1
	check(Array(cs.ledger({})["hero_steps"]).any(func(x: Dictionary) -> bool: return str(x["label"]) == "Безрассудный"), "шаг роста в бою")


func test_mission_gives_xp() -> void:
	var c := content()
	var s := _run()
	s.missions["MS03"] = {"status": "open", "attempts": 0}
	var r := MissionFlow.launch(c, s, "MS03", ["P02", "P04"])
	MissionFlow.tick(c, s, 20.0)
	var res := MissionResolver.resolve_through(c, s, int(r["squad"]["id"]), "MS03_fight")
	var ns: RunState = res["state"]
	var any := false
	for cid: String in ["P02", "P04"]:
		if not ns.character(cid).get("tag_xp", {}).is_empty():
			any = true
	check(any, "бой миссии даёт опыт тегам")
	var s2 := RunState.from_dict(JSON.parse_string(JSON.stringify(ns.to_dict())))
	eq(s2.character("P02").get("tag_xp", {}), ns.character("P02").get("tag_xp", {}), "опыт сохраняется:")


func test_death_save() -> void:
	var c := content()
	var s := _run()
	_grow(s, "P02", "Решимость", "evo")
	s.character("P02")["traumas"] = ["T03", "T04", "T06", "T08"]
	var rng := RandomNumberGenerator.new()
	var saved := false
	for i in 20:
		rng.seed = i
		var s2 := s.copy()
		var res := {"traumas": [], "death": {}}
		var ent: Array = []
		InjuryRules.give_traumas(c, s2, "P02", [], 1, "all", rng, res, ent)
		if s2.is_alive("P02") and bool(s2.character("P02").get("death_saved", false)):
			saved = true
	check(saved, "Несгибаемый один раз переживает бросок смерти")
