extends TestCase
## Пошаговый бой «Схватка» (docs/24, Ф1): строй, очередь, удары, состояния, сдвиги, трупы, крупные, грань,
## психика, засада, отступление, итог, бои ИИ против ИИ.


func _run(c: Content) -> RunState:
	var s := MissionFlow.new_run(c, 41, "shore")
	for cid: String in ["P02", "P03", "P04"]:
		EffectApplier.add_card(c, s, cid)
	return s


func _sk(c: Content, s: RunState, heroes: Array, enemies: Array, extra: Dictionary = {}) -> Skirmish:
	var spec := {"heroes": heroes, "enemies": enemies, "field": "F_17"}
	spec.merge(extra, true)
	return Skirmish.create(c, s, spec)


func _ev(evs: Array, kind: String) -> Array:
	return evs.filter(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == kind)


func test_build_and_formation() -> void:
	var c := content()
	var s := _run(c)
	var sk := _sk(c, s, ["P01", "P02", "P03"], ["M03", "M03"])
	var hs := sk.living("hero")
	eq(hs.size(), 3, "героев в строю:")
	eq(sk.by_uid("h0").card, "P01", "строй по порядку:")
	eq([sk.by_uid("h0").pos, sk.by_uid("h1").pos, sk.by_uid("h2").pos], [1, 2, 3], "позиции героев:")
	var n := sk.by_uid("h1")
	var sh := StatResolver.sheet(c, sk.state, "P02", MissionFlow.pocket(sk.state, "P02"))
	eq(n.hp_max, SkBuild.HP_BASE + SkBuild.HP_POWER * int(sh["power"]["total"]) + int(sh["will"]["total"]), "здоровье из Силы и Воли:")
	eq(n.crit, SkBuild.CRIT_BASE + int(sh["cunning"]["total"]), "крит из Хитрости:")
	var e := sk.by_uid("e0")
	eq(e.hp_max, 14, "Падальщик: здоровье обычного врага:")
	check(is_equal_approx(e.prot, 0.25), "Панцирь — защита 25%")
	eq([e.pos, sk.by_uid("e1").pos], [1, 2], "позиции врагов:")
	var sk2 := _sk(c, s, ["P01"], ["M02", "M01", "M01", "M01"])
	var king := sk2.by_uid("e0")
	eq(king.size, 2, "Гигант — две позиции:")
	check(king.occupies(1) and king.occupies(2), "Горный Король стоит на 1–2")
	eq(sk2.by_uid("e1").pos, 3, "за ним — позиция 3:")
	eq(sk2.living("enemy").size(), 3, "четвёртому врагу нет места в строю:")


func test_turn_order() -> void:
	var c := content()
	var s := _run(c)
	var sk := _sk(c, s, ["P01", "P02", "P03", "P04"], ["M03", "M03", "M04"])
	var f := sk.turn()
	check(f != null, "первый ход есть")
	var order: Array = _ev(sk.log, "queue")[0]["order"]
	eq(order.size(), 7, "ходят все:")
	var prev := 999
	for uid: String in order:
		var x := sk.by_uid(uid)
		check(x.init <= prev, "очередь по скорости раунда")
		prev = x.init
		check(x.init >= x.speed + 1 and x.init <= x.speed + 8 + x.first_strike, "скорость + бросок 1–8 (%s)" % x.name)


func test_positions_and_targets() -> void:
	var c := content()
	var s := _run(c)
	var sk := _sk(c, s, ["P02", "P03", "P01"], ["M03", "M03", "M04"])
	var nephis := sk.by_uid("h0")
	var w: Dictionary = nephis.skills[0]
	eq(sk.usable_why(nephis, w), "", "Нефис бьёт с позиции 1:")
	eq(sk.targets(nephis, w), ["e0", "e1"], "удар оружием ближнего боя — по позициям 1–2:")
	SkFormation.move(sk.fighters, nephis, 3)
	eq(nephis.pos, 3, "сдвинута назад на позицию 3:")
	if not Array(w.get("from", [])).has(3):
		check(sk.usable_why(nephis, w) != "", "с позиции 3 мечом не достать")
	# скрытного не выбрать целью, пока есть другие
	SkStatus.add(sk.by_uid("e0"), {"type": "stealth", "turns": 2})
	var fr := sk.by_uid("h1")
	SkFormation.move(sk.fighters, fr, -5)
	var claws: Dictionary = sk.by_uid("e1").skills[0]
	check(not sk.targets(sk.by_uid("e1"), claws).is_empty(), "у врага есть цели")
	var hero_hit := {"id": "TEST", "side": "enemy", "from": [1, 2, 3, 4], "to": [1, 2], "acc": 90, "mult": 1.0}
	check(not sk.targets(fr, hero_hit).has("e0"), "скрытный враг — не цель, пока есть другие")


func test_strike_numbers() -> void:
	var c := content()
	var s := _run(c)
	var sk := _sk(c, s, ["P02"], ["M03"])
	var a := sk.by_uid("h0")
	var t := sk.by_uid("e0")
	var w: Dictionary = a.skills[0]
	var pv := SkStrike.preview(sk, a, w, t)
	check(int(pv["hit"]) >= SkStrike.HIT_MIN and int(pv["hit"]) <= SkStrike.HIT_MAX, "шанс попадания 5–95%%: %d" % int(pv["hit"]))
	check(int(pv["min"]) >= 1 and int(pv["max"]) >= int(pv["min"]), "разброс урона: %d–%d" % [int(pv["min"]), int(pv["max"])])
	var p0 := t.prot
	t.prot = 0.0
	var pv2 := SkStrike.preview(sk, a, w, t)
	t.prot = p0
	check(int(pv2["max"]) > int(pv["max"]), "Панцирь снижает урон: %d < %d" % [int(pv["max"]), int(pv2["max"])])
	var x := SkFighter.new()
	var y := SkFighter.new()
	x.rank = 1
	check(is_equal_approx(SkStrike.rank_k(x, y), SkStrike.RANK_UP), "старший ранг бьёт сильнее")
	check(is_equal_approx(SkStrike.rank_k(y, x), SkStrike.RANK_DOWN), "младший — слабее")
	for i in 200:
		var r := SkStrike.roll(sk, pv)
		if bool(r["hit"]):
			var d := int(r["dmg"])
			if bool(r["crit"]):
				eq(d, int(floor(int(pv["max"]) * SkStrike.CRIT_MULT)), "крит — полуторный наибольший урон:")
			else:
				check(d >= int(pv["min"]) and d <= int(pv["max"]), "урон в разбросе: %d" % d)


func test_statuses() -> void:
	var c := content()
	var s := _run(c)
	var sk := _sk(c, s, ["P02", "P03"], ["M03", "H_GOLEM"])
	var crab := sk.by_uid("e0")
	var hp0 := crab.hp
	sk.apply_effect(sk.by_uid("h0"), crab, {"type": "bleed", "power": 2, "turns": 3})
	sk.apply_effect(sk.by_uid("h0"), crab, {"type": "bleed", "power": 1, "turns": 3})
	check(sk._start_turn(crab), "с кровотечением ходит")
	eq(crab.hp, hp0 - 3, "кровотечения складываются:")
	check(not SkStatus.add(sk.by_uid("e1"), {"type": "bleed", "power": 2, "turns": 3}), "Конструкт не кровоточит")
	sk.apply_effect(sk.by_uid("h0"), crab, {"type": "stun"})
	check(not sk._start_turn(crab), "оглушённый пропускает ход")
	check(SkStatus.resist(crab, "stun") >= int(crab.res["stun"]) + SkStatus.STUN_GUARD, "после оглушения — стойкость к нему")
	# защита: удар по подзащитному принимает защитник
	var cassie := sk.by_uid("h1")
	var nephis := sk.by_uid("h0")
	sk.apply_effect(nephis, cassie, {"type": "guard", "turns": 2})
	eq(sk._guarded(cassie, []), nephis, "удар по Касси принимает Нефис:")
	# контратака
	SkStatus.add(nephis, {"type": "riposte", "turns": 2})
	nephis.hp = 999
	nephis.hp_max = 999
	var claws: Dictionary = crab.skills[0]
	SkStatus.remove(crab, "stun")
	var ev := sk.act(crab, str(claws["id"]), "h0")
	check(not _ev(ev, "riposte").is_empty(), "Нефис отвечает контратакой")


func test_moves_and_large() -> void:
	var c := content()
	var s := _run(c)
	var sk := _sk(c, s, ["P02"], ["M03", "M01", "M04"])
	var e0 := sk.by_uid("e0")
	sk.apply_effect(sk.by_uid("h0"), e0, {"type": "push", "n": 1})
	eq([e0.pos, sk.by_uid("e1").pos], [2, 1], "отброс назад на 1:")
	sk.apply_effect(sk.by_uid("h0"), sk.by_uid("e2"), {"type": "pull", "n": 2})
	eq(sk.by_uid("e2").pos, 1, "притянут на позицию 1:")
	var sk2 := _sk(c, s, ["P02"], ["M02", "M01"])
	var larva := sk2.by_uid("e1")
	SkFormation.move(sk2.fighters, larva, -1)
	eq([larva.pos, sk2.by_uid("e0").pos], [1, 2], "крупный сдвинут назад, занимает 2–3:")
	check(sk2.by_uid("e0").occupies(3), "Горный Король на 2–3")


func test_corpses() -> void:
	var c := content()
	var s := _run(c)
	var sk := _sk(c, s, ["P02"], ["M03", "M01", "M01"])
	var a := sk.by_uid("h0")
	var e0 := sk.by_uid("e0")
	var ev := sk.hurt(e0, 999, a, "hit")
	check(e0.corpse and not _ev(ev, "corpse").is_empty(), "убитый оставил труп")
	eq(e0.hp, int(ceil(14 * Skirmish.CORPSE_SHARE)), "здоровье трупа:")
	eq(sk.by_uid("e1").pos, 2, "труп держит место — задние не вышли вперёд:")
	eq(sk.living("enemy").size(), 2, "труп — не боец:")
	for i in Skirmish.CORPSE_ROUNDS:
		sk._end_round()
	check(e0.removed, "труп истлел")
	eq(sk.by_uid("e1").pos, 1, "строй сомкнулся:")
	sk.hurt(sk.by_uid("e1"), 999, null, "dot")
	check(sk.by_uid("e1").dead and not sk.by_uid("e1").corpse, "убитый кровотечением трупа не оставляет")
	var sk2 := _sk(c, s, ["P02"], ["M03", "M01"])
	sk2.hurt(sk2.by_uid("e0"), 999, null, "hit")
	sk2.hurt(sk2.by_uid("e0"), 999, null, "hit")
	check(sk2.by_uid("e0").removed, "труп можно добить")
	eq(sk2.by_uid("e1").pos, 1, "добитый труп освобождает место:")


func test_edge_and_death() -> void:
	var c := content()
	var s := _run(c)
	var sk := _sk(c, s, ["P02", "P03"], ["M03"])
	var n := sk.by_uid("h0")
	var ev := sk.hurt(n, n.hp, sk.by_uid("e0"), "hit")
	check(n.edge and EdgeRules.on_edge(sk.state, "P02"), "здоровье 0 — грань смерти")
	eq(n.hp, 0, "на грани здоровье 0:")
	check(not _ev(ev, "edge").is_empty(), "событие грани")
	eq(sk.outcome, "", "бой идёт, пока не все на грани:")
	var died := false
	for i in 80:
		var ev2 := sk.hurt(n, 3, sk.by_uid("e0"), "hit")
		check(not _ev(ev2, "survive").is_empty() or not _ev(ev2, "death").is_empty(), "удар по грани — бросок смерти")
		if n.dead:
			died = true
			break
	check(died and not sk.state.is_alive("P02"), "на грани герой может погибнуть")
	# щит карты: первое падение — 1 здоровья, не грань
	var s2 := _run(c)
	EffectApplier.add_card(c, s2, "U06")
	s2.character("P03")["pocket"] = ["U06"]
	var sk2 := _sk(c, s2, ["P03"], ["M03"])
	var cas := sk2.by_uid("h0")
	var ev3 := sk2.hurt(cas, cas.hp, null, "hit")
	check(not _ev(ev3, "shield").is_empty() and cas.hp == 1 and not cas.edge, "Саван Кукловода принял удар")


func test_rout_and_heal() -> void:
	var c := content()
	var s := _run(c)
	var sk := _sk(c, s, ["P02", "P03"], ["M03"])
	sk.hurt(sk.by_uid("h0"), 999, null, "hit")
	sk.heal(sk.by_uid("h0"), 5)
	check(not sk.by_uid("h0").edge and not EdgeRules.on_edge(sk.state, "P02"), "лечение снимает грань")
	check(sk.by_uid("h0").has_status("weak"), "после грани — слабость")
	sk.hurt(sk.by_uid("h0"), 999, null, "hit")
	sk.hurt(sk.by_uid("h1"), 999, null, "hit")
	sk._check_end()
	eq(sk.outcome, "loss", "все живые на грани — поражение:")


func test_psyche() -> void:
	var c := content()
	var s := _run(c)
	var sk := _sk(c, s, ["P02", "P03"], ["M03"])
	check(TutorialRules.enabled(sk.state, "panic"), "психика работает на Берегу")
	var cas := sk.by_uid("h1")
	var before := PsycheRules.psyche(sk.state, "P03")
	sk.apply_effect(sk.by_uid("e0"), cas, {"type": "psyche", "value": -12})
	check(PsycheRules.psyche(sk.state, "P03") < before, "удар по рассудку снижает психику")
	var p1 := PsycheRules.psyche(sk.state, "P03")
	sk._on_crit(sk.by_uid("h0"), sk.by_uid("e0"))
	check(PsycheRules.psyche(sk.state, "P03") > p1, "крит товарища поднимает психику")
	sk.state.character("P03")["panic"] = 95
	var ev := sk.apply_effect(sk.by_uid("e0"), cas, {"type": "psyche", "value": -20})
	check(not _ev(ev, "crisis").is_empty(), "психика 0 — кризис")
	var r := sk.finish()
	eq(PsycheRules.crisis(r["state"], "P03"), "", "кризис боя кончается с боем:")


func test_ambush_and_retreat() -> void:
	var c := content()
	var s := _run(c)
	var sk := _sk(c, s, ["P02", "P03"], ["M03", "M03"], {"ambush": "enemies"})
	sk.turn()
	var order: Array = _ev(sk.log, "queue")[0]["order"]
	check(order.all(func(u: String) -> bool: return u.begins_with("h")), "застигнутые враги в первом раунде не ходят")
	var sk2 := _sk(c, s, ["P02", "P03"], ["M03", "M03"], {"ambush": "heroes"})
	sk2.turn()
	var o2: Array = _ev(sk2.log, "queue")[0]["order"]
	eq([str(o2[0]).left(1), str(o2[1]).left(1)], ["e", "e"], "застигнутые герои ходят после врагов:")
	var sk3 := _sk(c, s, ["P02"], ["M02"], {"no_retreat": true})
	eq(_ev(sk3.retreat(sk3.by_uid("h0")), "retreat_blocked").size(), 1, "от босса не уйти:")
	var sk4 := _sk(c, s, ["P02"], ["M03"])
	check(sk4.retreat_chance() <= Skirmish.RETREAT_BASE and sk4.retreat_chance() >= Skirmish.RETREAT_MIN, "шанс отступления")
	for i in 30:
		sk4.retreat(sk4.by_uid("h0"))
		if sk4.outcome != "":
			break
	eq(sk4.outcome, "retreat", "отряд отступил:")


func test_auto_battles() -> void:
	var c := content()
	var fights := [
		[["P01", "P02", "P03"], ["M03", "M03"]], [["P01", "P02", "P03"], ["M09", "M12", "M12"]],
		[["P01", "P02", "P03", "P04"], ["M04", "M03", "M03"]], [["P02", "P04"], ["M01", "M01", "M01", "M01"]],
		[["P01", "P02", "P03", "P04"], ["MW1"]], [["P01", "P02", "P03"], ["M27", "M27", "M27"]],
		[["P01"], ["M03"]], [["P02", "P03", "P04"], ["M02", "M01"]],
	]
	var stats := {"win": 0, "loss": 0, "retreat": 0}
	var rounds := 0
	var n := 0
	for seed_i in 25:
		for fi: Array in fights:
			var s := MissionFlow.new_run(c, 100 + seed_i, "shore")
			for cid: String in ["P02", "P03", "P04"]:
				EffectApplier.add_card(c, s, cid)
			var sk := Skirmish.create(c, s, {"heroes": fi[0], "enemies": fi[1], "light": ["bright", "dim", "dusk", "dark"][seed_i % 4]})
			var out := sk.auto(600)
			check(out in ["win", "loss", "retreat"], "бой окончен: %s против %s → %s" % [fi[0], fi[1], out])
			check(_ev(sk.log, "error").is_empty(), "ИИ не делает невозможных ходов")
			stats[out] = int(stats.get(out, 0)) + 1
			rounds += sk.round_no
			n += 1
			var r := sk.finish()
			for cid: String in fi[0]:
				if r["state"].is_alive(cid):
					check(r["state"].character(cid).has("hp"), "здоровье героя записано")
	var avg := float(rounds) / n
	print("   [схватка] боёв: %d, победы %d, поражения %d, отступления %d, раундов в среднем %.1f" % [n, stats["win"], stats["loss"], stats["retreat"], avg])
	check(avg >= 1.5 and avg <= 12.0, "бой длится разумно: %.1f раунда" % avg)
