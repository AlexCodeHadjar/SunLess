extends TestCase
## «Схватка», фаза 2 (docs/24 §5): свои навыки героев, оружие, карты способностей и усиления, Эхо, Отражение,
## состояния SunLess (жетоны Уклон и Панцирь, Приманка, Предвидение, Ослепление, Страх, Горение), цена и условия.

const EFFECTS := ["bleed", "poison", "burn", "stun", "mark", "guard", "riposte", "stealth", "buff", "debuff", "push", "pull",
	"heal", "heal_pct", "psyche", "dodge", "block", "taunt", "foresight", "blind", "fear", "sure", "empower", "ignite",
	"steady", "cleanse", "unstealth", "unstealth_all", "remove_buffs", "reveal", "swap", "extra_turn", "summon", "light_ward"]


func _run(c: Content) -> RunState:
	var s := MissionFlow.new_run(c, 77, "shore")
	for cid: String in ["P02", "P03", "P04", "P08", "P09", "P10"]:
		EffectApplier.add_card(c, s, cid)
	return s


func _give(c: Content, s: RunState, cid: String, pocket: Array, abilities: Array = []) -> void:
	for card: String in pocket:
		if not s.owns(card):
			EffectApplier.add_card(c, s, card)
	s.character(cid)["pocket"] = pocket.duplicate()
	s.character(cid)["abilities"] = abilities.duplicate()


func _ids(f: SkFighter) -> Array:
	return f.skills.map(func(x: Dictionary) -> String: return str(x["id"]))


func _ev(evs: Array, kind: String) -> Array:
	return evs.filter(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == kind)


func test_data_covers_heroes_and_cards() -> void:
	var c := content()
	var d := c.skirmish
	for cid: String in c.characters:
		eq(Array(d.get("heroes", {}).get(cid, [])).size(), 2, "свои навыки %s:" % cid)
	for card: String in c.enhancements:
		check(d.get("cards", {}).has(card), "навык карты %s" % card)
	for aid: String in c.abilities:
		check(d.get("cards", {}).has(aid), "навык способности %s" % aid)
	for id: String in d.get("skills", {}):
		var s := SkBuild.skill(c, id)
		for p: int in s.get("from", []) + s.get("to", []):
			check(p >= 1 and p <= 4, "%s: позиции 1–4" % id)
		check(str(s.get("side", "")) in ["enemy", "ally", "self"], "%s: сторона навыка" % id)
		for e: Dictionary in s.get("effects", []):
			check(EFFECTS.has(str(e["type"])), "%s: известный эффект %s" % [id, e["type"]])
	for card2: String in d.get("echoes", {}):
		check(c.enemies.has(str(d["echoes"][card2]["base"])), "Эхо %s: существо есть" % card2)


func test_hero_kit() -> void:
	var c := content()
	var s := _run(c)
	_give(c, s, "P01", ["U02", "K05"], ["A01", "A02"])
	var f := SkBuild.hero(c, s, "P01")
	var ids := _ids(f)
	for id: String in ["H_P01_1", "H_P01_2", "C_U02", "C_K05", "C_A01", "C_A02", "STEP", "PASS"]:
		check(ids.has(id), "у Санни есть навык %s" % id)
	check(ids.any(func(x: String) -> bool: return x.begins_with("W_")), "без карты-оружия — своё оружие")
	check(str(f.skill("C_U02").get("card", "")) == "U02", "у навыка карты — её id (для кнопки)")
	_give(c, s, "P01", ["L08", "L07"])
	var f2 := SkBuild.hero(c, s, "P01")
	var ids2 := _ids(f2)
	check(ids2.has("C_L08") and not ids2.any(func(x: String) -> bool: return x.begins_with("W_")), "карта-оружие заменяет своё оружие")
	eq(f2.dmg, SkBuild.skill(c, "C_L08")["dmg"], "свои навыки бьют оружием из кармашка:")
	check(f2.prot >= 0.10, "Панцирный наруч — защита 10%")


func test_stealth_strike_and_tokens() -> void:
	var c := content()
	var s := _run(c)
	var sk := Skirmish.create(c, s, {"heroes": ["P01", "P02"], "enemies": ["M03", "M03"]})
	var sunny := sk.by_uid("h0")
	var crab := sk.by_uid("e0")
	var hit: Dictionary = sunny.skill("H_P01_1")
	check(sunny.has_status("stealth"), "Скрытность: Санни начинает бой в тени")
	SkStatus.remove(sunny, "stealth")
	var plain := SkStrike.preview(sk, sunny, hit, crab)
	SkStatus.add(sunny, {"type": "stealth", "turns": 2})
	var hidden := SkStrike.preview(sk, sunny, hit, crab)
	eq(int(hidden["crit"]), 100, "удар из тени — верный крит:")
	check(int(hidden["max"]) > int(plain["max"]), "из тени — сильнее")
	# Панцирь (жетон): удар вполовину и жетон тратится
	var nephis := sk.by_uid("h1")
	nephis.hp = 999
	nephis.hp_max = 999
	SkStatus.add(nephis, {"type": "block", "charges": 1})
	SkStatus.add(nephis, {"type": "sure", "turns": 2, "crit": 0})
	var claws: Dictionary = crab.skills[0]
	SkStatus.add(crab, {"type": "sure", "turns": 2})
	var ev := sk._strike(crab, claws, nephis)
	check(not _ev(ev, "block").is_empty(), "Панцирь принял удар")
	check(not nephis.has_status("block"), "жетон Панциря потрачен")
	check(not crab.has_status("sure"), "верный удар потрачен")
	SkStatus.add(nephis, {"type": "dodge", "charges": 2})
	sk._strike(crab, claws, nephis)
	eq(int(nephis.status("dodge").get("charges", 0)), 1, "жетон Уклона тратится на удар:")


func test_taunt_foresight_blind() -> void:
	var c := content()
	var s := _run(c)
	var sk := Skirmish.create(c, s, {"heroes": ["P03", "P02"], "enemies": ["M03"]})
	var crab := sk.by_uid("e0")
	var claws: Dictionary = crab.skills[0]
	eq(sk.targets(crab, claws).size(), 2, "без Приманки — обе цели:")
	sk.apply_effect(sk.by_uid("h1"), sk.by_uid("h1"), {"type": "taunt", "turns": 2})
	eq(sk.targets(crab, claws), ["h1"], "Приманка: бьют только Нефис:")
	var cassie := sk.by_uid("h0")
	var before := int(SkStrike.preview(sk, crab, claws, cassie)["hit"])
	SkStatus.add(crab, {"type": "foresight", "turns": 2})
	check(int(SkStrike.preview(sk, crab, claws, cassie)["hit"]) <= before - SkStrike.FORESIGHT or before <= SkStrike.HIT_MIN + SkStrike.FORESIGHT,
		"Предвидение: от врага уклоняться легче")
	check(not SkStatus.add(cassie, {"type": "blind", "turns": 2}), "Касси (Слепота) не ослепить")
	SkStatus.add(crab, {"type": "blind", "turns": 2})
	check(SkStatus.mod(crab, "acc") <= SkStatus.BLIND, "ослеплённый мажет")


func test_extra_turn_cost_and_conditions() -> void:
	var c := content()
	var s := _run(c)
	_give(c, s, "P04", [], ["A05"])
	_give(c, s, "P02", [], ["A03"])
	_give(c, s, "P01", [], ["A02"])
	var sk := Skirmish.create(c, s, {"heroes": ["P04", "P02", "P01"], "enemies": ["M03", "M03"], "light": "bright"})
	var caster := sk.by_uid("h0")
	sk.act(caster, "C_A05", caster.uid)
	eq(sk.turn(), caster, "«Рывок»: Кастер сразу ходит ещё раз:")
	check(sk.usable_why(caster, caster.skill("C_A05")) != "", "«Рывок» — раз за бой")
	var nephis := sk.by_uid("h1")
	var p0 := PsycheRules.psyche(sk.state, "P02")
	nephis.hp = 5
	sk.act(nephis, "C_A03", nephis.uid)
	check(PsycheRules.psyche(sk.state, "P02") < p0, "Бессмертное Пламя — цена: Боль (психика)")
	check(nephis.hp > 5 and nephis.has_status("ignite"), "пламя лечит, удары поджигают")
	var sunny := sk.by_uid("h2")
	check(sk.usable_why(sunny, sunny.skill("C_A02")) != "", "«Тень крепнет» — не при ярком свете")
	# «Первая кровь» — только в первом раунде или первым в раунде
	sk.round_no = 3
	sk.first_uid = "e0"
	check(sk.usable_why(caster, caster.skill("H_P04_2")) != "", "«Первая кровь» — только первым ударом")
	sk.first_uid = caster.uid
	eq(sk.usable_why(caster, caster.skill("H_P04_2")), "", "первым в раунде — можно:")


func test_echo() -> void:
	var c := content()
	var s := _run(c)
	_give(c, s, "P01", ["U12"])
	var sk := Skirmish.create(c, s, {"heroes": ["P01", "P02"], "enemies": ["M03"]})
	var echoes := sk.fighters.filter(func(x: SkFighter) -> bool: return x.echo)
	eq(echoes.size(), 1, "Эхо вышло в бой:")
	var ec: SkFighter = echoes[0]
	eq(ec.pos, 3, "в свободную позицию:")
	check(_ids(ec).has("ECHO_RECALL") and _ids(ec).size() == 5, "у Эха 2 навыка, «Отозвать», шаг и пропуск")
	sk.act(ec, "ECHO_RECALL", ec.uid)
	check(not ec.alive(), "Эхо отозвано")
	var sunny := sk.by_uid("h0")
	eq(sk.usable_why(sunny, sunny.skill("C_U12")), "", "карта снова призывает Эхо:")
	sk.act(sunny, "C_U12", sunny.uid)
	check(ec.alive(), "Эхо вернулось")
	check(sk.usable_why(sunny, sunny.skill("C_U12")) != "", "призыв — раз за бой")
	sk.hurt(ec, 999, sk.by_uid("e0"), "hit")
	check(ec.dead and not sk.state.owns("U12"), "погибшее Эхо — карта рассыпалась")
	check(not Array(sk.state.character("P01").get("pocket", [])).has("U12"), "и ушла из кармашка")


func test_mirror() -> void:
	var c := content()
	var s := _run(c)
	var sk := Skirmish.create(c, s, {"heroes": ["P01"], "enemies": ["MT1"], "mirror": "P01"})
	var m := sk.by_uid("e0")
	check(_ids(m).has("H_P01_1") and _ids(m).has("H_P01_2"), "Отражение бьёт навыками героя")


func test_full_kits_auto() -> void:
	var c := content()
	var n := 0
	var wins := 0
	var rounds := 0
	var comps := [[["P01", "P02", "P03"], ["M03", "M03"]], [["P01", "P02", "P03", "P04"], ["M04", "M03", "M03"]],
		[["P02", "P08", "P09", "P10"], ["M27", "M27", "M27"]], [["P01", "P03"], ["M09", "M12"]], [["P01"], ["MT1"]]]
	for i in 30:
		for comp: Array in comps:
			var s := _run(c)
			_give(c, s, "P01", ["U02", "L08", "U12"], ["A01", "A02", "A06", "A07"])
			_give(c, s, "P02", ["U14", "L12"], ["A03"])
			_give(c, s, "P03", ["K05", "L06"], ["A04"])
			_give(c, s, "P04", ["L13"], ["A05"])
			var sk := Skirmish.create(c, s, {"heroes": comp[0], "enemies": comp[1], "light": ["bright", "dusk", "dark"][i % 3],
				"mirror": "P01" if comp[1].has("MT1") else ""})
			var out := sk.auto(800)
			check(out in ["win", "loss", "retreat"], "бой окончен")
			check(_ev(sk.log, "error").is_empty(), "ИИ не делает невозможных ходов: %s" % str(_ev(sk.log, "error").slice(0, 1)))
			n += 1
			wins += 1 if out == "win" else 0
			rounds += sk.round_no
	print("   [схватка Ф2] боёв: %d, побед %d%%, раундов в среднем %.1f" % [n, int(100.0 * wins / n), float(rounds) / n])
