extends TestCase
## «Схватка», фаза 3 (docs/24 §6): враги — особые навыки, состав строя, двойной ход и фазы боссов, свои состояния
## SunLess у врагов (Очарование, Захват, Кошмарный шёпот, Разъедание, Ярость), призыв, пожирание трупов, бегство.


func _run(c: Content) -> RunState:
	var s := MissionFlow.new_run(c, 91, "shore")
	for cid: String in ["P02", "P03", "P04"]:
		EffectApplier.add_card(c, s, cid)
	return s


func _ev(evs: Array, kind: String) -> Array:
	return evs.filter(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == kind)


func test_every_enemy_fights() -> void:
	var c := content()
	for eid: String in c.enemies:
		for i in 3:
			var s := MissionFlow.new_run(c, 500 + i, "shore")
			for cid: String in ["P02", "P03", "P04"]:
				EffectApplier.add_card(c, s, cid)
			var sk := Skirmish.create(c, s, {"heroes": ["P01", "P02", "P03", "P04"], "enemies": [eid], "pack": true,
				"mirror": "P01" if eid.begins_with("MT") else ""})
			var out := sk.auto(900)
			check(out in ["win", "loss", "retreat"], "бой с %s окончен: %s" % [eid, out])
			check(_ev(sk.log, "error").is_empty(), "бой с %s без невозможных ходов" % eid)


func test_packs() -> void:
	var c := content()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	eq(SkPack.fill(c, ["M03"], rng), ["M03", "M03"], "одиночка — пара:")
	var horde := SkPack.fill(c, ["M33"], rng)
	check(horde.size() >= 3 and horde.size() <= 4 and horde.all(func(x: String) -> bool: return x == "M33"), "стая — 3–4: %s" % str(horde))
	eq(SkPack.fill(c, ["M04"], rng), ["M04", "M03", "M03"], "элита со свитой:")
	eq(SkPack.fill(c, ["M02"], rng), ["M02", "M01", "M01"], "Горный Король (2 позиции) с приспешниками:")
	eq(SkPack.fill(c, ["M03", "M03", "M03"], rng).size(), 3, "полный строй не меняется:")


func test_boss_double_turn_and_phase() -> void:
	var c := content()
	var s := _run(c)
	var sk := Skirmish.create(c, s, {"heroes": ["P01", "P02"], "enemies": ["M02"]})
	sk.turn()
	var order: Array = _ev(sk.log, "queue")[0]["order"]
	var king := sk.by_uid("e0")
	eq(king.actions, 2, "у крупного босса два хода:")
	sk.queue.clear()
	sk._begin_round()
	eq(sk.queue.count("e0"), 2, "в очереди раунда — дважды:")
	check(order.size() >= 3, "очередь собрана")
	check(king.skill("X_CRUSH").is_empty(), "до фазы — без «Раздавить»")
	var ev := sk.hurt(king, int(king.hp_max * 0.6), sk.by_uid("h0"), "hit")
	check(not _ev(ev, "phase").is_empty() and not king.skill("X_CRUSH").is_empty(), "половина здоровья — новая фаза и навык")


func test_charm_grab_acid_whisper() -> void:
	var c := content()
	var s := _run(c)
	var sk := Skirmish.create(c, s, {"heroes": ["P02", "P04"], "enemies": ["M09", "M03"]})
	var nephis := sk.by_uid("h0")
	var caster := sk.by_uid("h1")
	var grabber := sk.by_uid("e0")
	# Очарование: в свой ход бьёт своего, удар снимает
	sk.apply_effect(grabber, caster, {"type": "charm", "turns": 2})
	check(not sk._start_turn(caster), "очарованный не ходит сам")
	check(not _ev(sk.log, "charmed").is_empty(), "очарованный бьёт своих")
	check(not caster.has_status("charm"), "очарование прошло")
	# Захват: не шагнуть и не сдвинуть; сильный удар по захватчику отпускает
	sk.apply_effect(grabber, nephis, {"type": "grab", "turns": 3})
	check(sk.usable_why(nephis, nephis.skill("STEP")) != "", "схваченный не шагает")
	var p := nephis.pos
	sk.apply_effect(grabber, nephis, {"type": "push", "n": 1})
	eq(nephis.pos, p, "схваченного не сдвинуть:")
	sk.hurt(grabber, grabber.hp_max / 4 + 1, nephis, "hit")
	check(not nephis.has_status("grab"), "сильный удар по захватчику — отпустил")
	# Разъедание: до трёх, защита −30%
	var crab := sk.by_uid("e1")
	for i in 5:
		sk.apply_effect(nephis, crab, {"type": "acid"})
	check(is_equal_approx(SkStatus.mod(crab, "prot"), SkStatus.ACID * 3), "Разъедание — не больше трёх")
	# Кошмарный шёпот: психика в начале хода
	sk.apply_effect(grabber, nephis, {"type": "whisper", "power": 5, "turns": 2})
	var p0 := PsycheRules.psyche(sk.state, "P02")
	sk._start_turn(nephis)
	check(PsycheRules.psyche(sk.state, "P02") < p0, "шёпот бьёт по психике")


func test_summon_devour_flee_rage() -> void:
	var c := content()
	var s := _run(c)
	var sk := Skirmish.create(c, s, {"heroes": ["P02"], "enemies": ["M26", "M03"]})
	var lord := sk.by_uid("e0")
	var n0 := sk.living("enemy").size()
	sk.apply_effect(lord, lord, {"type": "summon_enemy", "id": "M27", "n": 2})
	eq(sk.living("enemy").size(), n0 + 2, "Повелитель поднял двоих:")
	sk.apply_effect(lord, lord, {"type": "summon_enemy", "id": "M27", "n": 1})
	eq(sk.living("enemy").size(), n0 + 2, "в строю нет места:")
	# пожирание трупа
	var sk2 := Skirmish.create(c, s, {"heroes": ["P02"], "enemies": ["M03", "M03"]})
	var a := sk2.by_uid("e0")
	var b := sk2.by_uid("e1")
	sk2.hurt(a, 999, sk2.by_uid("h0"), "hit")
	b.hp = 3
	eq(sk2.usable_why(b, b.skill("X_DEVOUR")), "", "раненый Падальщик рядом с трупом может пожрать:")
	sk2.act(b, "X_DEVOUR", b.uid)
	check(b.hp > 3 and a.removed, "пожрал падаль — подлечился, трупа нет")
	# бегство
	var fled := false
	for i in 40:
		var sk3 := Skirmish.create(c, MissionFlow.new_run(c, 700 + i, "shore"), {"heroes": ["P01"], "enemies": ["M33", "M33"]})
		var w := sk3.by_uid("e0")
		w.hp = 1
		sk3._start_turn(w)
		if w.removed:
			fled = true
			break
	check(fled, "раненая тварь из Стаи бежит")
	# Ярость: удар копит злость
	var sk4 := Skirmish.create(c, s, {"heroes": ["P02"], "enemies": ["M15"]})
	var fiend := sk4.by_uid("e0")
	check(fiend.rage, "Кровавый Изверг — Ярость")
	sk4.hurt(fiend, 1, sk4.by_uid("h0"), "hit")
	check(SkStatus.mod(fiend, "dmg") > 0.0, "получил удар — злее")
