extends TestCase
## Психика (docs/16 §9г): шкала 100 → 0, кризис — паника или подъём духа, влияние на проверки, бой,
## поступки героев в кризисе, конец кризиса, облик и новые теги характера.


func _run() -> RunState:
	var c := content()
	var s := MissionFlow.new_run(c, 21)
	s.chapter = "shore"
	for cid: String in ["P02", "P03", "P09", "P10"]:
		EffectApplier.add_card(c, s, cid)
	return s


func _rng(seed_v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r


func test_scale_and_crisis() -> void:
	var c := content()
	var s := _run()
	eq(PsycheRules.psyche(s, "P09"), 100, "начинаем с полной психикой:")
	PsycheRules.change(c, s, "P09", -30, "тест")
	eq(PsycheRules.psyche(s, "P09"), 61, "Хрупкая психика: потеря ×1,3:")
	var out := PsycheRules.change(c, s, "P09", -200, "тест", ["P09"], _rng(1))
	check(PsycheRules.crisis(s, "P09") in ["panic", "uplift"], "на нуле — кризис")
	check(out.any(func(e: Dictionary) -> bool: return e["kind"] == "crisis" and str(e.get("quote", "")) != ""), "запись кризиса с репликой")
	# в подъёме духа психика не падает
	var s2 := _run()
	s2.character("P02")["psy"] = {"state": "uplift", "origin": "mission"}
	var v := PsycheRules.value(s2, "P02")
	PsycheRules.change(c, s2, "P02", -50, "тест")
	eq(PsycheRules.value(s2, "P02"), v, "подъём духа — иммунитет к потере:")


func test_uplift_chance() -> void:
	var c := content()
	var s := _run()
	var shifty := PsycheRules.uplift_chance(c, s, "P10", [])
	var nephis := PsycheRules.uplift_chance(c, s, "P02", [])
	check(nephis > 40 and shifty <= 10, "характер решает: Нефис %d%%, Шифти %d%%" % [nephis, shifty])
	TrustRules.change(c, s, "P02", "P03", 4, "тест")
	check(PsycheRules.uplift_chance(c, s, "P02", ["P02", "P03"]) > nephis, "доверие в отряде повышает шанс подъёма")
	s.character("P02")["traumas"] = ["T02", "T03"]
	check(PsycheRules.uplift_chance(c, s, "P02", []) < nephis, "травмы понижают шанс подъёма")
	# статистика кризисов: Нефис чаще поднимается, Шифти чаще паникует
	var up := {"P02": 0, "P10": 0}
	for i in 300:
		for cid: String in ["P02", "P10"]:
			var s3 := _run()
			PsycheRules.change(c, s3, cid, -300, "тест", [cid], _rng(i * 7 + cid.hash()))
			if PsycheRules.crisis(s3, cid) == "uplift":
				up[cid] += 1
	check(up["P02"] > up["P10"] * 3, "Нефис поднимается чаще Шифти (%d против %d из 300)" % [up["P02"], up["P10"]])


func test_effects_on_checks_and_combat() -> void:
	var c := content()
	var s := _run()
	var totals := {"power": 10, "will": 10, "cunning": 10}
	s.character("P09")["psy"] = {"state": "panic", "origin": "mission"}
	var parts := PsycheRules.check_parts(c, s, "P09", totals)
	eq(parts.size(), 3, "паника — по всем трём характеристикам:")
	eq(int(parts[0]["value"]), -3, "паника −30%:")
	s.character("P09")["psy"] = {"state": "uplift", "origin": "mission"}
	eq(int(PsycheRules.check_parts(c, s, "P09", totals)[0]["value"]), 5, "подъём +50%:")
	# бой: шаг ledger
	s.character("P02")["psy"] = {"state": "uplift", "origin": "mission"}
	var cs := CombatSession.create_for_mission(c, s, "T", {"enemies": ["M03"], "field": "F_08"}, "P02", [], [], {"tags": []}, {"tags": []})
	cs.round_no = 1
	var step: Array = Array(cs.ledger({})["hero_steps"]).filter(func(x: Dictionary) -> bool: return x["label"] == "Подъём духа")
	check(step.size() == 1 and is_equal_approx(float(step[0]["pct"]), 0.5), "в бою подъём духа +50%")
	# Ярость в панике в бою почти не слабеет; Трус сбегает; Гордыня не отступает
	check(is_equal_approx(PsycheRules.mult(c, s, "P09", true), PsycheRules.UPLIFT_MULT), "множитель подъёма")
	s.character("P10")["psy"] = {"state": "panic", "origin": "mission"}
	check(PsycheRules.flees(c, s, "P10"), "Трус в панике сбегает")


func test_acts() -> void:
	var c := content()
	var kinds := {}
	for i in 200:
		var s := _run()
		s.character("P10")["psy"] = {"state": "panic", "origin": "mission"}
		s.character("P02")["psy"] = {"state": "uplift", "origin": "mission"}
		var r := _rng(i)
		for e: Dictionary in PsycheRules.act(c, s, "P10", ["P10", "P03", "P09"], r) + PsycheRules.act(c, s, "P02", ["P02", "P03"], r):
			if e["kind"] == "psy_act":
				kinds[e["act"]] = int(kinds.get(e["act"], 0)) + 1
	for k: String in ["despair", "blame", "rally", "bond", "insight"]:
		check(int(kinds.get(k, 0)) > 0, "поступок «%s» случается (%d)" % [k, int(kinds.get(k, 0))])
	# отчаяние Паникёра бьёт по отряду
	var s2 := _run()
	s2.character("P10")["psy"] = {"state": "panic", "origin": "mission"}
	var hit := false
	for i in 40:
		var before := PsycheRules.psyche(s2, "P03")
		for e2: Dictionary in PsycheRules.act(c, s2, "P10", ["P10", "P03"], _rng(1000 + i)):
			if e2.get("act", "") == "despair" and PsycheRules.psyche(s2, "P03") < before:
				hit = true
	check(hit, "слова отчаяния снижают психику других")


func test_reset_and_mission() -> void:
	var c := content()
	var s := _run()
	s.character("P02")["psy"] = {"state": "panic", "origin": "combat"}
	check(not PsycheRules.reset(s, "P02", "mission"), "боевой кризис не снимается концом события раньше боя")
	check(PsycheRules.reset(s, "P02", "combat"), "…а концом боя — снимается")
	eq(PsycheRules.psyche(s, "P02"), PsycheRules.PANIC_AFTER, "после паники психика:")
	# миссия целиком: кризис снимается к концу, отчёт хранит кризисы
	var seen := 0
	for i in 60:
		var s2 := _run()
		s2.character("P10")["panic"] = 95
		s2.character("P09")["panic"] = 95
		s2.missions["SH21"] = {"status": "open", "attempts": 0}
		var r := MissionFlow.launch(c, s2, "SH21", ["P01", "P10"])
		if not r["ok"]:
			continue
		MissionFlow.tick(c, s2, 20.0)
		s2.rng_state = i * 31
		var res := MissionResolver.resolve_through(c, s2, int(r["squad"]["id"]), "SH21_fight")
		var ns: RunState = res["state"]
		seen += Array(res["report"].get("crises", [])).size()
		for cid: String in ["P01", "P10"]:
			check(PsycheRules.crisis(ns, cid) == "", "после миссии кризиса нет")
	check(seen > 0, "на тяжёлой миссии с измотанным отрядом кризисы случаются (%d)" % seen)


func test_tags_and_nightmare() -> void:
	var c := content()
	for t: String in ["Стойкость", "Хрупкая психика", "Вдохновитель", "Паникёр", "Оптимист", "Мрачность"]:
		check(c.combat_tags.has(t), "тег характера «%s»" % t)
	check(MissionFlow.hero_tags(c, _run(), "P02").has("Вдохновитель"), "Нефис — вдохновитель")
	var s := MissionFlow.new_run(c, 3)
	PsycheRules.change(c, s, "P01", -100, "тест")
	eq(PsycheRules.crisis(s, "P01"), "", "в Кошмаре психика не работает (обучение):")
	check(c.psyche_lines.has("panic") and c.psyche_lines.has("rally"), "реплики героев загружены")
