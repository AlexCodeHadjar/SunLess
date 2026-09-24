extends TestCase
## Формула шанса, смерть, износ, травмы (контрольные примеры из файлов 02 и 04).


func test_chance_examples() -> void:
	var cases := [
		[{"power": 4, "will": 6, "cunning": 5}, {"power": 3, "will": 7, "cunning": 6}, 95],
		[{"power": 5, "will": 5}, {"power": 3, "will": 5, "cunning": 6}, 80],
		[{"cunning": 7}, {"power": 3, "will": 5, "cunning": 6}, 85],
		[{"power": 9, "will": 8}, {"power": 3, "will": 5, "cunning": 6}, 47],
		[{"power": 5, "will": 5}, {"power": 9, "will": 3}, 85],
		[{}, {"power": 1}, 100],
		[{"will": 6}, {"will": -2}, 0],
		[{"will": 6}, {"will": 6}, 100],
	]
	for c: Array in cases:
		eq(ChanceCalculator.compute(c[1], c[0]), c[2], "req %s / stats %s:" % [c[0], c[1]])


func test_chance_labels() -> void:
	eq(ChanceCalculator.label(0), "Невозможно")
	eq(ChanceCalculator.label(19), "Очень низкий")
	eq(ChanceCalculator.label(20), "Низкий")
	eq(ChanceCalculator.label(45), "Средний")
	eq(ChanceCalculator.label(70), "Высокий")
	eq(ChanceCalculator.label(90), "Почти гарантированный")
	eq(ChanceCalculator.label(100), "Гарантировано")


func test_death_chance_table() -> void:
	var expected := {0: 0, 1: 0, 2: 0, 3: 15, 4: 35, 5: 55, 6: 75, 7: 95, 8: 100, 9: 100}
	for n: int in expected:
		eq(TraumaRules.death_chance(n), expected[n], "травм %d:" % n)


func test_t09_not_counted() -> void:
	eq(TraumaRules.counted(["T01", "T09", "T02"]), 2)


func test_wear_progression() -> void:
	var s := RunState.new()
	s.wear["U01"] = WearRules.START
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var expected := 1
	for i in 30:
		var w := WearRules.roll(s, "U01", rng)
		eq(w["before"], expected, "шаг %d:" % i)
		check(w["broken"] == (int(w["roll"]) <= int(w["before"])), "поломка должна совпадать с броском")
		if w["broken"]:
			return
		expected = mini(100, expected + 5)
		s.wear["U01"] = w["after"]
	check(false, "за 30 использований усиление обязано сломаться (износ дошёл бы до 100%)")


func test_wear_exemptions() -> void:
	var c := content()
	var s := RunState.new()
	s.arc = "nightmare"
	check(not WearRules.wears(c, s, "U02"), "Колокольчик не изнашивается в Первом Кошмаре")
	s.arc = "academy"
	check(WearRules.wears(c, s, "U02"), "после Кошмара Колокольчик изнашивается")
	check(not WearRules.wears(c, s, "K01"), "знания не изнашиваются")
	check(WearRules.wears(c, s, "U01"), "обычное оружие изнашивается")


func test_trauma_pick_excludes_owned_and_scripted() -> void:
	var c := content()
	var rng := RandomNumberGenerator.new()
	for seed_value in 50:
		rng.seed = seed_value
		var t := TraumaRules.pick(c, "all", ["T02"], rng)
		check(t != "T02", "уже имеющаяся травма не выдаётся")
		check(t != "T07" and t != "T09", "T07 и T09 только сценарием")
	rng.seed = 1
	var phys := TraumaRules.pick(c, "physical", [], rng)
	eq(c.traumas[phys]["category"], "physical", "пул физических:")
	# Все физические уже есть — берём из общего пула.
	var fallback := TraumaRules.pick(c, "physical", ["T02", "T03", "T08", "T10"], rng)
	check(fallback != "" and c.traumas[fallback]["category"] != "physical", "запасной пул — любые другие")


func test_soften() -> void:
	var c := content()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var soft := TraumaRules.soften(c, "T10", [], rng)
	eq(c.traumas[soft]["severity"], "heavy", "критическая → тяжёлая:")
	eq(TraumaRules.soften(c, "T02", [], rng), "", "лёгкая смягчается до «нет травмы»:")
