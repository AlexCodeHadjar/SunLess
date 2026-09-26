extends TestCase
## Бой «Столкновение» (автобой миссий): ранги, теги, симбиозы, конфликты, поле, раунды, итог.

const LARVAE := {"enemies": ["M01", "M01"], "field": "F_05"}          # MS03 «Личинки Горного Короля»
const KING := {"enemies": ["M02"], "field": "F_03", "kind": "boss"}     # MS05 «Горный Король»
const AURO := {"enemies": ["H_AURO"], "field": "F_04"}                 # MS09 «Последние слова Героя»
const PACK := {"enemies": ["M01", "M01", "M01"], "field": "F_01"}      # стая в узком проходе


func _state(c: Content, stage: String = "slave") -> RunState:
	var s := MissionFlow.new_run(c, 7)
	s.characters["P01"]["stage"] = stage
	return s


func _session(c: Content, s: RunState, spec: Dictionary, enh: Array = [], support: Array = []) -> CombatSession:
	for e: String in enh:
		EffectApplier.add_card(c, s, e)
	var cs := CombatSession.create_for_mission(c, s, "T", spec, "P01", enh, support, {"id": "T", "tags": ["combat"]}, {"id": "T_a", "tags": []})
	cs.round_no = 1
	return cs


func test_data_valid() -> void:
	var c := content()
	for e in ContentValidator.validate(c):
		check(false, e)
	check(c.combat_tags.size() >= 200, "тегов не меньше 200: %d" % c.combat_tags.size())
	check(c.synergies.size() >= 40, "симбиозов не меньше 40")
	check(c.conflicts.size() >= 50, "конфликтов не меньше 50")
	for tid: String in c.tactics:
		check(not c.tactics[tid].has("mana"), "приём %s без маны — маны в игре нет" % tid)


func test_chance_is_clamped() -> void:
	var c := content()
	var cs := _session(c, _state(c), KING)
	var ch := int(cs.ledger({})["chance"])
	check(ch >= CombatSession.CHANCE_MIN and ch <= CombatSession.CHANCE_MAX, "шанс в пределах 5–95: %d" % ch)
	# бой до 2 побед из 3: p²(3 − 2p)
	var fight := CombatSession.fight_chance(ch)
	check(fight <= 0.15, "Санни-раб против Тирана почти без шансов: раунд %d%%, бой %.0f%%" % [ch, fight * 100])


func test_even_fight_is_reasonable() -> void:
	var c := content()
	var led := _session(c, _state(c), LARVAE, ["U01"]).ledger({})
	check(int(led["chance"]) >= 20 and int(led["chance"]) <= 80, "бой с личинками — не приговор: %d" % int(led["chance"]))


func test_conflict_chain_vs_soft_body() -> void:
	var c := content()
	var names: Array = []
	for l: Dictionary in _session(c, _state(c), LARVAE, ["U01"]).ledger({})["links"]:
		names.append(str(l["tags"]))
	check(str(names).contains("Цепь") and str(names).contains("Мягкое тело"), "конфликт Цепь ⟷ Мягкое тело: %s" % str(names))


func test_synergy_shadow_in_darkness() -> void:
	var c := content()
	var cs := _session(c, _state(c, "sleeper"), AURO)
	cs.field = c.fields["F_07"]  # собор: Тьма
	var found := false
	for l: Dictionary in cs.ledger({})["links"]:
		if l["type"] == "synergy" and l["side"] == "hero" and Array(l["tags"]).has("Тень") and Array(l["tags"]).has("Тьма"):
			found = true
	check(found, "Тень + Тьма → «Дитя ночи»")


func test_narrow_pass_limits_pack() -> void:
	var c := content()
	var led := _session(c, _state(c), PACK).ledger({})
	var base_step: Dictionary = led["enemy_steps"][0]
	check(float(base_step["value"]) <= 200.1, "в узком проходе считаются только двое: %.1f" % float(base_step["value"]))


func test_tactic_bonus_raises_chance() -> void:
	var c := content()
	var cs := _session(c, _state(c), LARVAE, ["U01"])
	var base := int(cs.ledger({})["chance"])
	var boosted := int(cs.ledger(c.tactics["X_ALL_IN"])["chance"])
	check(boosted > base, "«Всё или ничего» повышает шанс: %d → %d" % [base, boosted])


func test_auto_combat_ends_and_has_both_outcomes() -> void:
	var c := content()
	var wins := 0
	var losses := 0
	for seed_value in 40:
		var s := _state(c)
		s.rng_seed = seed_value
		s.rng_state = seed_value * 104729
		var cs := _session(c, s, LARVAE, ["U01"])
		cs.round_no = 0
		cs.auto_play()
		check(cs.finished, "автобой завершается")
		check(cs.rounds_log.size() <= 3, "раундов не больше трёх")
		if cs.outcome == "win":
			wins += 1
		elif cs.outcome == "loss":
			losses += 1
			eq(cs.enemy_wins, 2, "проигрыш — две проигранные схватки:")
	check(wins > 0 and losses > 0, "у боя с личинками есть оба исхода (%d/%d)" % [wins, losses])


func test_mission_combat_loot_and_wounds() -> void:
	var c := content()
	var won := false
	var wounded := false
	for seed_value in 60:
		var s := MissionFlow.new_run(c, 300 + seed_value)
		s.missions["MS03"] = {"status": "open", "attempts": 0}
		var r := MissionFlow.launch(c, s, "MS03", ["P01"])
		MissionFlow.tick(c, s, 20.0)
		var res := MissionResolver.resolve_through(c, s, int(r["squad"]["id"]), "MS03_fight")
		var rep: Dictionary = res["report"]
		var ns: RunState = res["state"]
		if rep["combats"].is_empty():
			continue
		var cb: Dictionary = rep["combats"][0]
		if cb["outcome"] == "win":
			won = true
			check(int(ns.resources["shards"]) > 10, "победа — добыча: осколки душ")
			eq(int(ns.enemy_wounds.get("MS03", 0)), 0, "после победы раны врага забыты:")
		elif int(ns.enemy_wounds.get("MS03", 0)) > 0:
			wounded = true
	check(won, "в миссии бывают победы")
	check(wounded, "раны врага сохраняются до следующей попытки")


func test_squad_support_becomes_ally() -> void:
	var c := content()
	var s := _state(c)
	EffectApplier.add_card(c, s, "P08")
	var cs := _session(c, s, KING, [], ["P08"])
	check(cs.allies.has("P08"), "Ауро в бою как союзник")
	check(cs.available_tactics().has("X_ALLY"), "с союзником доступен приём «Плечом к плечу»")


func test_enemy_intent_chosen_and_negated() -> void:
	var c := content()
	var cs := _session(c, _state(c), LARVAE)
	cs.round_no = 0
	cs.begin_round()
	check(not cs.intent.is_empty(), "враг выбрал намерение")
	# Смертельный взгляд гасится Слепотой
	cs.intent = c.enemy_abilities["EA_GAZE"].duplicate(true)
	var with_gaze := float(cs.ledger({})["hero"])
	cs.hero_extra_tags = ["Слепота"]
	var blind := float(cs.ledger({})["hero"])
	check(blind > with_gaze, "Слепота гасит взгляд: %.0f → %.0f" % [with_gaze, blind])


func test_feint_cancels_intent() -> void:
	var c := content()
	var cs := _session(c, _state(c), KING)
	cs.intent = c.enemy_abilities["EA_CHARGE"].duplicate(true)
	var plain := float(cs.ledger({})["enemy"])
	var feint := float(cs.ledger(c.tactics["X_FEINT"])["enemy"])
	check(feint < plain, "Финт сбивает натиск: %.0f → %.0f" % [plain, feint])
