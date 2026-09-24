extends TestCase
## Бой «Столкновение»: ранги, теги, симбиозы, конфликты, поле, раунды, итог.


func _state(c: Content, stage: String = "slave") -> RunState:
	var s := EventFlow.new_run(c, 7)
	s.characters["P01"]["stage"] = stage
	return s


func _open(s: RunState, eid: String) -> void:
	s.events[eid] = {"status": "active", "done_options": [], "spawned_week": 1}


func _session(c: Content, s: RunState, eid: String, oid: String, enh: Array = []) -> CombatSession:
	for e: String in enh:
		EffectApplier.add_card(c, s, e)
	_open(s, eid)
	var cs := CombatSession.create(c, s, eid, oid, {"character": "P01", "enhancements": enh})
	cs.round_no = 1
	return cs


func test_data_valid() -> void:
	var c := content()
	for e in ContentValidator.validate(c):
		check(false, e)
	check(c.combat_tags.size() >= 200, "тегов не меньше 200: %d" % c.combat_tags.size())
	check(c.synergies.size() >= 40, "симбиозов не меньше 40")
	check(c.conflicts.size() >= 50, "конфликтов не меньше 50")


func test_chance_is_clamped() -> void:
	var c := content()
	var s := _state(c)
	var cs := _session(c, s, "E05", "E05_2")
	var ch := int(cs.ledger({})["chance"])
	check(ch >= CombatSession.CHANCE_MIN and ch <= CombatSession.CHANCE_MAX, "шанс в пределах 5–95: %d" % ch)
	# бой до 2 побед из 3: p²(3 − 2p)
	var p := ch / 100.0
	var fight := p * p * (3.0 - 2.0 * p)
	check(fight <= 0.15, "Санни-раб против Тирана почти без шансов: раунд %d%%, бой %.0f%%" % [ch, fight * 100])


func test_even_fight_is_reasonable() -> void:
	var c := content()
	var s := _state(c)
	var cs := _session(c, s, "E03", "E03_1", ["U01"])
	var led := cs.ledger({})
	check(int(led["chance"]) >= 20 and int(led["chance"]) <= 80, "бой с личинками — не приговор: %d" % int(led["chance"]))


func test_conflict_chain_vs_soft_body() -> void:
	var c := content()
	var s := _state(c)
	var cs := _session(c, s, "E03", "E03_1", ["U01"])
	var names: Array = []
	for l: Dictionary in cs.ledger({})["links"]:
		names.append(str(l["tags"]))
	check(str(names).contains("Цепь") and str(names).contains("Мягкое тело"), "конфликт Цепь ⟷ Мягкое тело: %s" % str(names))


func test_synergy_shadow_in_darkness() -> void:
	var c := content()
	var s := _state(c, "sleeper")
	var cs := _session(c, s, "E09", "E09_1")
	cs.field = c.fields["F_07"]  # собор: Тьма
	var found := false
	for l: Dictionary in cs.ledger({})["links"]:
		if l["type"] == "synergy" and l["side"] == "hero" and Array(l["tags"]).has("Тень") and Array(l["tags"]).has("Тьма"):
			found = true
	check(found, "Тень + Тьма → «Дитя ночи»")


func test_narrow_pass_limits_pack() -> void:
	var c := content()
	var s := _state(c)
	_open(s, "RE_HUNT")
	var cs := CombatSession.create(c, s, "RE_HUNT", "RE_HUNT_1", {"character": "P01", "enhancements": []})
	cs.round_no = 1
	var led := cs.ledger({})
	var base_step: Dictionary = led["enemy_steps"][0]
	check(float(base_step["value"]) <= 200.1, "в узком проходе считаются только двое: %.1f" % float(base_step["value"]))


func test_tactic_bonus_raises_chance() -> void:
	var c := content()
	var s := _state(c)
	var cs := _session(c, s, "E03", "E03_1", ["U01"])
	var base := int(cs.ledger({})["chance"])
	var boosted := int(cs.ledger(c.tactics["X_ALL_IN"])["chance"])
	check(boosted > base, "«Всё или ничего» повышает шанс: %d → %d" % [base, boosted])


func test_full_combat_and_finish() -> void:
	var c := content()
	var wins := 0
	var losses := 0
	for seed_value in 40:
		var s := _state(c)
		s.rng_seed = seed_value
		s.rng_state = seed_value * 104729
		EffectApplier.add_card(c, s, "U01")
		_open(s, "E03")
		var cs := CombatSession.create(c, s, "E03", "E03_1", {"character": "P01", "enhancements": ["U01"]})
		var guard := 0
		while not cs.finished and guard < 5:
			cs.begin_round()
			cs.play_round(cs.hand[0] if not cs.hand.is_empty() else "")
			guard += 1
		check(cs.finished, "бой завершается не позже 3 раундов")
		check(cs.rounds_log.size() <= 3, "раундов не больше трёх")
		var r := cs.finish()
		var ns: RunState = r["state"]
		if cs.outcome == "win":
			wins += 1
			check(ns.is_option_done("E03", "E03_1"), "победа — вариант выполнен")
			check(int(ns.resources["shards"]) > 10, "добыча: осколки душ")
		elif cs.outcome == "loss":
			losses += 1
			check(ns.is_event_active("E03"), "поражение — событие остаётся")
			check(Array(ns.characters["P01"]["traumas"]).size() >= 1, "проигранный раунд — травма")
		if cs.outcome == "death":
			check(ns.game_over, "смерть в бою — конец прохождения")
		else:
			eq(ns.week, 2, "бой — это ход:")
	check(wins > 0 and losses > 0, "у боя с личинками есть оба исхода (%d/%d)" % [wins, losses])


func test_retreat_keeps_wounds() -> void:
	var c := content()
	var s := _state(c)
	_open(s, "E03")
	var cs := CombatSession.create(c, s, "E03", "E03_1", {"character": "P01", "enhancements": []})
	cs.session_wounds = 1
	cs.retreat()
	var ns: RunState = cs.finish()["state"]
	eq(int(ns.enemy_wounds.get("E03", 0)), 1, "раны врага сохранились:")
	check(bool(ns.enemy_alert.get("E03", false)), "враг насторожен после отступления")
	check(ns.is_event_active("E03"), "событие остаётся")


func test_option_adds_ally_to_combat() -> void:
	var c := content()
	var s := _state(c)
	EffectApplier.add_card(c, s, "P08")
	var rng := RandomNumberGenerator.new()
	EffectApplier.apply(c, s, {"cmd": "combat_mod", "event": "E05", "allies": ["P08"]}, "P01", rng)
	_open(s, "E05")
	var cs := CombatSession.create(c, s, "E05", "E05_2", {"character": "P01", "enhancements": []})
	check(cs.allies.has("P08"), "Ауро в бою как союзник")
	cs.round_no = 1
	check(cs.available_tactics().has("X_ALLY"), "с союзником доступен приём «Плечом к плечу»")


func test_combat_option_blocked_in_turn_resolver() -> void:
	var c := content()
	var s := _state(c)
	_open(s, "E03")
	var r := TurnResolver.resolve(c, s, "E03", "E03_1", {"character": "P01", "enhancements": []})
	check(not r["ok"], "бой не разрешается обычной проверкой")
