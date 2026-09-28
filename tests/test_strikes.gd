extends TestCase
## Удары вместо броска (docs/16 §9е п.7): запас силы, оружие, броня, окружение, победа по доле потерь.

const LARVAE := {"enemies": ["M01", "M01"], "field": "F_05"}
const SCAV := {"enemies": ["M03"], "field": "F_08"}


func _session(c: Content, spec: Dictionary, hero: String = "P01", enh: Array = [], support: Array = []) -> CombatSession:
	var s := MissionFlow.new_run(c, 5)
	s.chapter = "academy"
	for e: String in enh + support + [hero]:
		if not s.owns(e):
			EffectApplier.add_card(c, s, e)
	s.character(hero)["pocket"] = enh.duplicate()
	var cs := CombatSession.create_for_mission(c, s, "T", spec, hero, enh, support, {"id": "T", "tags": ["combat"]}, {"id": "T_a", "tags": []})
	return cs


func test_weapons() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 5)
	eq(str(Strikes.hero_weapon(c, s, "P01")["id"]), "Кинжал", "у Санни — кинжал:")
	EffectApplier.add_card(c, s, "U07")
	s.character("P01")["pocket"] = ["U07"]
	eq(str(Strikes.hero_weapon(c, s, "P01")["id"]), "Меч", "Лазурный Клинок в кармашке — меч:")
	eq(str(Strikes.enemy_weapon(c, c.enemies["M03"])["id"]) != "", true, "у врага есть природное оружие:")
	for w: Dictionary in c.weapons["weapons"]:
		check(c.combat_tags.has(str(w["id"])), "оружие %s — тег" % w["id"])


func test_armor_and_pierce() -> void:
	var c := content()
	var dagger := Strikes.weapon(c, "Кинжал")
	var hammer := Strikes.weapon(c, "Тяжёлое оружие")
	check(Strikes.dmg_mult(c, dagger, ["Панцирь"]) < Strikes.dmg_mult(c, dagger, ["Мягкое тело"]), "кинжал плох против панциря и хорош против мягкого тела")
	check(Strikes.dmg_mult(c, hammer, ["Панцирь"]) > Strikes.dmg_mult(c, hammer, []), "тяжёлое оружие проламывает панцирь")


func test_round_exchange() -> void:
	var c := content()
	var cs := _session(c, SCAV, "P02", [], ["P03", "P04"])
	cs.begin_round()
	var rec := cs.play_round()
	check(not Array(rec["strikes"]).is_empty(), "в раунде есть удары")
	var sides := {}
	for st: Dictionary in rec["strikes"]:
		sides[st["side"]] = true
		check(float(st["dmg"]) >= 0.0 and (bool(st["hit"]) or float(st["dmg"]) == 0.0), "промах — без урона")
	check(sides.has("hero") and sides.has("enemy"), "бьют обе стороны")
	check(float(cs.pool["hero"]) <= float(cs.pool_max["hero"]) and float(cs.pool["enemy"]) < float(cs.pool_max["enemy"]), "урон отнимает запас")
	var heroes := {}
	for st2: Dictionary in rec["strikes"]:
		if st2["side"] == "hero":
			heroes[int(st2["idx"])] = true
	eq(heroes.size(), 3, "бьёт каждый герой отряда:")


func test_outcome_by_share() -> void:
	var c := content()
	for seed_value in 25:
		var cs := _session(c, LARVAE, "P01", ["U01"])
		cs.state.rng_state = 7919 * (seed_value + 1)
		cs.rng.state = cs.state.rng_state
		cs.auto_play()
		check(cs.finished and cs.rounds_log.size() <= Strikes.ROUNDS, "не больше трёх раундов")
		if float(cs.pool["enemy"]) <= 0.0:
			eq(cs.outcome, "win", "враг без силы — победа сразу:")
		elif float(cs.pool["hero"]) <= 0.0:
			check(cs.outcome != "win", "отряд без силы — поражение")
		else:
			eq(cs.outcome == "win", cs.share_left("hero") > cs.share_left("enemy"), "победа — у кого осталась большая доля:")


func test_odds_honest() -> void:
	var c := content()
	var cs0 := _session(c, LARVAE, "P01", ["U01"])
	cs0.round_no = 1
	var odds := cs0.fight_odds(cs0.ledger({}))
	var wins := 0
	var n := 200
	for i in n:
		var cs := _session(c, LARVAE, "P01", ["U01"])
		cs.rng.state = 104729 * (i + 1)
		cs.auto_play()
		if cs.outcome == "win":
			wins += 1
	var real := 100.0 * wins / n
	print("   [удары] личинки: прогноз %.0f%%, на деле %.0f%%" % [odds * 100.0, real])
	check(absf(real - odds * 100.0) <= 15.0, "прогноз боя честен: %.0f против %.0f" % [odds * 100.0, real])
