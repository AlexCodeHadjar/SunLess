extends TestCase
## Ф9 (docs/16 §5–7): доверие, связки героев, паника и реакции по тегам.


func _run() -> RunState:
	var c := content()
	var s := MissionFlow.new_run(c, 21)
	s.chapter = "academy"   # живой отряд и рост работают с Академии (TutorialRules.UNLOCK)
	for cid: String in ["P02", "P03", "P04", "P09", "P10"]:
		EffectApplier.add_card(c, s, cid)
	MissionFlow.open(c, s, "MS02")
	return s


func test_trust_basics() -> void:
	var c := content()
	var s := _run()
	eq(TrustRules.key("P03", "P01"), TrustRules.key("P01", "P03"), "пара симметрична:")
	TrustRules.change(c, s, "P01", "P03", 9, "тест")
	eq(TrustRules.value(s, "P03", "P01"), TrustRules.MAX, "не выше +5:")
	var e := EffectApplier.apply(c, s, {"cmd": "adjust_trust", "a": "P01", "b": "P09", "value": -4, "text": "ложь"}, "P01", RandomNumberGenerator.new())
	eq(TrustRules.value(s, "P01", "P09"), -4, "команда сюжета adjust_trust:")
	check(str(e).contains("ложь"), "причина в записи")
	var top := TrustRules.top(c, s, "P01")
	eq(top["positive"][0]["hero"], "P03", "лучшее доверие Санни — Касси:")
	eq(top["negative"][0]["hero"], "P09", "худшее — Шолар:")
	var s2 := RunState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	eq(TrustRules.value(s2, "P01", "P09"), -4, "доверие сохраняется:")


func test_low_trust_refuses() -> void:
	var c := content()
	var s := _run()
	s.missions["MS03"] = {"status": "open", "attempts": 0}
	TrustRules.change(c, s, "P01", "P10", -3, "тест")
	check(MissionFlow.can_launch(c, s, "MS03", ["P01", "P10"]).contains("не пойдёт"), "при доверии −3 вместе не идут")
	check(MissionFlow.can_launch(c, s, "MS03", ["P01", "P09"]) == "", "с другим — можно")


func test_trust_grows_after_success() -> void:
	var c := content()
	var s := _run()
	s.missions["MS03"] = {"status": "open", "attempts": 0}
	var r := MissionFlow.launch(c, s, "MS03", ["P02", "P04"])
	MissionFlow.tick(c, s, 20.0)
	var res := MissionResolver.resolve_through(c, s, int(r["squad"]["id"]), "MS03_fight")
	var ns: RunState = res["state"]
	var d: int = {"success": 1, "partial": 1, "failure": -1}[res["report"]["outcome"]]
	# после миссии возможна ссора соперников (−1) — доверие не выше ожидаемого
	check(TrustRules.value(ns, "P02", "P04") <= d and TrustRules.value(ns, "P02", "P04") >= d - 1, "доверие пары изменилось по исходу")


func test_requires_trust() -> void:
	var c := content()
	var s := _run()
	var a := {"id": "x", "label": "Вместе", "requires_trust": {"min": 3, "pair": ["P01", "P03"]}, "stages": [{"name": "э", "auto": true}]}
	c.missions["MS02"]["actions"].append(a)
	var find := func(heroes: Array) -> Dictionary:
		return MissionFlow.actions_for(c, s, "MS02", heroes).filter(func(e: Dictionary) -> bool: return e["action"]["id"] == "x")[0]
	check(not find.call(["P01", "P03"])["available"], "доверия мало — закрыто")
	TrustRules.change(c, s, "P01", "P03", 3, "тест")
	check(find.call(["P01", "P03"])["available"], "доверие 3 — открыто")
	c.missions["MS02"]["actions"].pop_back()


func test_bonds() -> void:
	var c := content()
	var s := _run()
	check(not MissionFlow.has_scout(c, s, ["P01"]), "один Санни — не разведчик")
	check(MissionFlow.has_scout(c, s, ["P01", "P03"]), "Тень и Оракул раскрывают скрытое")
	var m: Dictionary = c.missions["MS02"]
	var a: Dictionary = m["actions"][0]
	var st: Dictionary = a["stages"][0]
	var alone := MissionForecast.stage_actor(c, s, m, a, st, ["P01"])
	var parts := BondRules.check_parts(c, s, ["P01", "P03"], "P01", ["social"])
	check(parts.any(func(p: Dictionary) -> bool: return p["stat"] == "cunning"), "связка даёт Санни +1 Хитрость")
	check(int(alone["chance"]) >= 0, "прогноз считается")
	var quarrel := false
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 30:
		if not BondRules.quarrels(c, s, ["P02", "P04"], rng).is_empty():
			quarrel = true
	check(quarrel, "соперники иногда ссорятся")
	var cs := CombatSession.create_for_mission(c, s, "T", {"enemies": ["M01"], "field": "F_05"}, "P01", [], ["P02"], {"tags": []}, {"tags": []})
	cs.round_no = 1
	check(Array(cs.ledger({})["hero_steps"]).any(func(x: Dictionary) -> bool: return str(x["label"]).contains("Тень и Звезда")), "связка в бою")


func test_panic() -> void:
	var c := content()
	var s := _run()
	PsycheRules.change(c, s, "P01", -40, "тест")
	eq(PsycheRules.psyche(s, "P01"), 74, "Хладнокровие: психика теряется медленнее (×0,65):")
	PsycheRules.change(c, s, "P09", -40, "тест")
	var before := PsycheRules.value(s, "P09")
	MissionFlow.tick(c, s, 40.0)
	check(PsycheRules.value(s, "P09") < before, "на отдыхе психика восстанавливается")
	# Гордыня в панике не отступает
	s.missions["MS03"] = {"status": "open", "attempts": 0}
	var r := MissionFlow.launch(c, s, "MS03", ["P04"])
	MissionFlow.tick(c, s, 20.0)
	s.character("P04")["psy"] = {"state": "panic", "origin": "mission"}
	var ret: Dictionary = MissionFlow.actions_for(c, s, "MS03", ["P04"]).filter(func(e: Dictionary) -> bool: return e["action"]["id"] == "MS03_retreat")[0]
	check(not ret["available"] and str(ret["reason"]).contains("не отступит"), "Кастер в панике не отступает")
	# Трус в панике сбегает
	var s3 := _run()
	s3.missions["MS03"] = {"status": "open", "attempts": 0}
	var r3 := MissionFlow.launch(c, s3, "MS03", ["P01", "P10"])
	MissionFlow.tick(c, s3, 20.0)
	s3.character("P10")["psy"] = {"state": "panic", "origin": "mission"}
	var res := MissionResolver.resolve_through(c, s3, int(r3["squad"]["id"]), "MS03_wait")
	check(str(res["report"]["entries"]).contains("сбегает"), "Шифти сбежал")
	check(TrustRules.value(res["state"], "P01", "P10") < 0, "бегство бьёт по доверию")
	var _unused := r
