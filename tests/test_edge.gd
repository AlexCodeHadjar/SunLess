extends TestCase
## Грань смерти (docs/16 §9е): поражение ставит на грань, поражение на грани — бросок смерти;
## лагерь и удачная миссия снимают грань.


func _run() -> RunState:
	return MissionFlow.new_run(content(), 9)


func test_defeat_puts_on_edge_then_rolls() -> void:
	var c := content()
	var s := _run()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var res := {}
	var ent: Array = []
	EdgeRules.defeat(c, s, "P01", [], rng, res, ent)
	check(EdgeRules.on_edge(s, "P01") and s.is_alive("P01"), "первое поражение — на грань, без броска")
	check(not res.has("death"), "броска смерти нет")
	var died := 0
	for i in 400:
		var s2 := s.copy()
		rng.seed = 100 + i
		var r2 := {}
		EdgeRules.defeat(c, s2, "P01", [], rng, r2, [])
		check(r2.has("death"), "на грани — бросок")
		if not s2.is_alive("P01"):
			died += 1
	var expect := EdgeRules.death_chance(c, s, "P01")
	check(abs(100.0 * died / 400.0 - expect) < 7.0, "смертей около %d%%: %.0f%%" % [expect, 100.0 * died / 400.0])


func test_modifiers() -> void:
	var c := content()
	var s := _run()
	eq(EdgeRules.death_chance(c, s, "P01"), EdgeRules.DEATH, "Санни без поправок:")
	EffectApplier.add_card(c, s, "P02")
	check(EdgeRules.death_chance(c, s, "P02") < EdgeRules.DEATH, "Стойкость снижает шанс смерти")
	s.character("P01")["abilities"].append("A07")
	eq(EdgeRules.death_chance(c, s, "P01"), int(EdgeRules.DEATH / 2.0), "Плетение Крови — вдвое ниже:")
	eq(EdgeRules.death_chance(c, s, "P01", 15), int((EdgeRules.DEATH + 15) / 2.0), "жестокий удар прибавляет:")


func test_shield_once_per_event() -> void:
	var c := content()
	var s := _run()
	EffectApplier.add_card(c, s, "U16")
	var rng := RandomNumberGenerator.new()
	var shielded := {}
	EdgeRules.defeat(c, s, "P01", ["U16"], rng, {}, [], shielded)
	check(not EdgeRules.on_edge(s, "P01"), "доспех принимает первое поражение события")
	EdgeRules.defeat(c, s, "P01", ["U16"], rng, {}, [], shielded)
	check(EdgeRules.on_edge(s, "P01"), "второе — уже на грань")


func test_recover() -> void:
	var c := content()
	var s := _run()
	s.character("P01")["edge"] = true
	var ent: Array = []
	EdgeRules.recover(c, s, "P01", "тест", ent)
	check(not EdgeRules.on_edge(s, "P01") and ent.size() == 1, "грань снята, запись есть")
	eq(EffectApplier.apply(c, s, {"cmd": "edge", "target": "P01"}, "P01", null).size(), 1, "сюжет ставит на грань:")
	check(EdgeRules.on_edge(s, "P01"), "на грани")
	EffectApplier.apply(c, s, {"cmd": "recover", "target": "P01"}, "P01", null)
	check(not EdgeRules.on_edge(s, "P01"), "сюжет снимает грань")
	var s2 := RunState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	s.character("P01")["edge"] = true
	var s3 := RunState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check(not EdgeRules.on_edge(s2, "P01") and EdgeRules.on_edge(s3, "P01"), "грань сохраняется")


func test_success_clears_edge() -> void:
	var c := content()
	var s := _run()
	s.character("P01")["edge"] = true
	MissionFlow.launch(c, s, "MS01", ["P01"])
	MissionFlow.tick(c, s, 30.0)
	var sq: Dictionary = s.squads[0]
	var r := MissionResolver.resolve(c, s, int(sq["id"]), "MS01_accept")
	check(r["ok"], "ход прошёл")
	if str(r["report"]["outcome"]) == "success":
		check(not EdgeRules.on_edge(r["state"], "P01"), "удачная миссия снимает грань")


func test_combat_edge_penalty() -> void:
	var c := content()
	var s := _run()
	var cs := CombatSession.create_for_mission(c, s, "T", {"enemies": ["M01"], "field": "F_05"}, "P01", [], [], {"id": "T", "tags": ["combat"]}, {"id": "T_a", "tags": []})
	var plain := float(cs.ledger({})["hero"])
	cs.state.character("P01")["edge"] = true
	var weak := float(cs.ledger({})["hero"])
	check(weak < plain, "на грани в бою слабее: %.0f → %.0f" % [plain, weak])


func test_no_traumas_left() -> void:
	var c := content()
	check(not ("traumas" in c), "травм в данных нет")
	for mid: String in c.missions:
		check(not c.missions[mid].has("trauma_pool"), "%s без пула травм" % mid)
