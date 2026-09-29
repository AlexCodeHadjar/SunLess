extends TestCase
## Ф4 миссий (docs/15): много героев, несколько отрядов сразу, магазин раз в 7 миссий, кармашки.

const SHOP := "academy_store"


func _run(seed_value: int = 7) -> RunState:
	var s := MissionFlow.new_run(content(), seed_value)
	check(ShopRules.shops_of(content(), s).is_empty(), "в Первом Кошмаре магазина нет")
	MissionFlow.open(content(), s, "MS02")
	s.chapter = "academy"   # торговцы — с Академии; миссии Кошмара остаются для проверок отрядов
	return s


func _items(s: RunState) -> Array:
	return Array(ShopRules.ensure(content(), s, SHOP)["items"]).map(func(it: Dictionary) -> String: return it["card"])


func test_shop_data() -> void:
	var c := content()
	check(c.shops.has(SHOP), "лавка Академии загружена")
	eq(ShopRules.shops_of(c, _run()), [SHOP], "в главе один магазин:")


func test_shop_roll() -> void:
	var c := content()
	var s := _run()
	var items := _items(s)
	eq(items.size(), int(c.shops[SHOP]["slots"]), "на витрине slots карт:")
	check(items.any(func(card: String) -> bool: return c.card_kind(card) == "character"), "хотя бы один персонаж")
	check(not items.has("P01"), "Санни не продаётся — он уже в отряде")
	eq(_items(_run()), items, "та же витрина при том же зерне:")
	var differs := false
	for seed_value in range(1, 12):
		if _items(_run(seed_value)) != items:
			differs = true
	check(differs, "у разных прохождений витрины разные")


func test_buy_character() -> void:
	var c := content()
	var s := _run()
	s.resources["shards"] = 0
	var hero := ""
	for card: String in _items(s):
		if c.card_kind(card) == "character":
			hero = card
	check(ShopRules.buy(c, s, SHOP, hero) != "", "без осколков не купить")
	s.resources["shards"] = 100
	var price := 0
	for it: Dictionary in ShopRules.ensure(c, s, SHOP)["items"]:
		if it["card"] == hero:
			price = int(it["price"])
	eq(ShopRules.buy(c, s, SHOP, hero), "", "покупка:")
	eq(int(s.resources["shards"]), 100 - price, "осколки списаны:")
	check(s.is_alive(hero), "новый герой жив и в коллекции")
	eq(MissionFlow.busy_reason(c, s, hero), "", "новый герой сразу свободен:")
	eq(MissionFlow.heroes(c, s).size(), 2, "героев двое:")
	check(ShopRules.buy(c, s, SHOP, hero) != "", "второй раз ту же карту не купить")
	check(ShopRules.buy(c, s, SHOP, "U14_нет") != "", "того, чего нет на прилавке, не купить")


func test_refresh_by_days() -> void:
	var c := content()
	var s := _run()
	var every := int(c.shops[SHOP]["refresh_every"])
	eq(ShopRules.days_to_refresh(c, s, SHOP), every, "до обновления %d дня:" % every)
	check(ShopRules.has_news(c, s, SHOP), "первый ассортимент — новый")
	ShopRules.mark_seen(c, s, SHOP)
	check(not ShopRules.has_news(c, s, SHOP), "после визита — не новый")
	var first := _items(s)
	s.day = every
	eq(_items(s), first, "в последний день витрина та же:")
	eq(ShopRules.days_to_refresh(c, s, SHOP), 1, "остался один день:")
	s.day = every + 1
	ShopRules.ensure(c, s, SHOP)
	eq(int(s.shops[SHOP]["gen"]), 1, "новый цикл дней — новое обновление:")
	check(ShopRules.has_news(c, s, SHOP), "новый товар подсвечен")
	check(Array(s.shops[SHOP]["items"]).all(func(it: Dictionary) -> bool: return not it["sold"]), "в новой витрине ничего не продано")


func test_dead_hero_not_sold() -> void:
	var c := content()
	var s := _run()
	EffectApplier.add_card(c, s, "P09")
	s.characters["P09"]["alive"] = false
	s.collection.erase("P09")
	check(not ShopRules.can_offer(c, s, "P09"), "погибшего героя не продают")
	for seed_value in range(1, 20):
		s.rng_seed = seed_value
		s.shops.clear()
		check(not _items(s).has("P09"), "погибший не появляется на витрине")


func test_one_mission_at_a_time() -> void:
	# отряд один (docs/16 §12): пока он на месте, второй выход не начать; решили — можно дальше
	var c := content()
	var s := _run(5)
	EffectApplier.add_card(c, s, "P09")
	s.missions["MS03"] = {"status": "open", "attempts": 0}
	var a := MissionFlow.launch(c, s, "MS02", ["P01"])
	check(a["ok"], "первый выход")
	check(MissionFlow.can_launch(c, s, "MS03", ["P09"]).contains("уже на миссии"), "второй — только после решения")
	var r1 := MissionResolver.resolve(c, s, int(a["squad"]["id"]), "MS02_lay_low")
	check(r1["ok"], "первый отряд отчитался")
	s = r1["state"]
	var b := MissionFlow.launch(c, s, "MS03", ["P09"])
	check(b["ok"], "теперь второй выход: %s" % b.get("error", ""))


func test_pocket_lock_on_mission() -> void:
	var c := content()
	var s := _run()
	EffectApplier.add_card(c, s, "P09")
	EffectApplier.add_card(c, s, "K02")
	s.characters["P01"]["pocket"] = ["K02"]
	eq(MissionFlow.pocket_owner(s, "K02"), "P01", "K02 у Санни:")
	eq(MissionFlow.pocket_lock(c, s, "P09", "K02"), "", "пока Санни дома — можно переложить")
	MissionFlow.launch(c, s, "MS02", ["P01"])
	check(MissionFlow.pocket_lock(c, s, "P01", "K02") != "", "кармашек героя на миссии не меняется")
	check(MissionFlow.pocket_lock(c, s, "P09", "K02") != "", "усиление, ушедшее с отрядом, не забрать")
	check(MissionFlow.hero_tags(c, s, "P01").has("Выслеживание"), "теги кармашка идут с героем")


func test_shop_save_roundtrip() -> void:
	var c := content()
	var s := _run()
	s.resources["shards"] = 50
	var card: String = _items(s)[0]
	eq(ShopRules.buy(c, s, SHOP, card), "", "покупка:")
	ShopRules.mark_seen(c, s, SHOP)
	var s2 := RunState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	eq(_items(s2), _items(s), "витрина сохранилась:")
	check(bool(s2.shops[SHOP]["items"][0]["sold"]), "продажа сохранилась")
	check(not ShopRules.has_news(c, s2, SHOP), "визит сохранился")
