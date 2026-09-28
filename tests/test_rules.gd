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
	s.chapter = "nightmare"
	check(not WearRules.wears(c, s, "U02"), "Колокольчик не изнашивается в Первом Кошмаре")
	s.chapter = "academy"
	check(WearRules.wears(c, s, "U02"), "после Кошмара Колокольчик изнашивается")
	check(not WearRules.wears(c, s, "K01"), "знания не изнашиваются")
	check(WearRules.wears(c, s, "U01"), "обычное оружие изнашивается")
