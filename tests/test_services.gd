extends TestCase
## Ф10 (docs/16 §9): услуги торговца — лечение, заточка, починка.


func _run() -> RunState:
	var c := content()
	var s := MissionFlow.new_run(c, 21)
	s.resources["shards"] = 50
	return s


func test_heal() -> void:
	var c := content()
	var s := _run()
	s.character("P01")["traumas"] = ["T03", "T02"]
	eq(ServiceRules.heal_price(c, "T03"), 10, "тяжёлая травма — 10:")
	eq(ServiceRules.heal_price(c, "T02"), 5, "лёгкая — 5:")
	eq(ServiceRules.perform(c, s, "nightmare_trader", "heal", "P01", "T03"), "", "лечение прошло:")
	check(not Array(s.character("P01")["traumas"]).has("T03"), "перелом снят")
	eq(int(s.resources["shards"]), 40, "осколки списаны:")
	s.resources["shards"] = 2
	check(ServiceRules.perform(c, s, "nightmare_trader", "heal", "P01", "T02").contains("Не хватает"), "без осколков не лечат")


func test_sharpen_and_unwear() -> void:
	var c := content()
	var s := _run()
	var card := ""
	for id: String in c.enhancements:
		if not Array(c.enhancements[id].get("bonuses", [])).is_empty() and Array(c.enhancements[id]["bonuses"][0].get("tags", [])).is_empty():
			card = id
			break
	check(card != "", "нашлось усиление с бонусом без условий")
	EffectApplier.add_card(c, s, card)
	check(ServiceRules.perform(c, s, "nightmare_trader", "sharpen", card).contains("не умеют"), "у менялы Кошмара заточки нет")
	eq(ServiceRules.perform(c, s, "academy_store", "sharpen", card), "", "в лавке Академии — есть:")
	var st: String = c.enhancements[card]["bonuses"][0]["stat"]
	var r := StatResolver.resolve(c, s, "P01", [card], {"tags": []}, {"tags": []})
	check(Array(r["parts"]).any(func(p: Dictionary) -> bool: return str(p["source"]).begins_with("Заточка") and p["stat"] == st), "заточка даёт +1 в проверке")
	s.chapter = "shore"
	check(not ServiceRules.sharpened(s, card), "в новой главе заточка сходит")
	s.wear[card] = 31
	eq(ServiceRules.perform(c, s, "nightmare_trader", "unwear", card), "", "починка:")
	eq(WearRules.current(s, card), WearRules.START, "износ сброшен:")
	var s2 := RunState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	eq(s2.sharpened, s.sharpened, "заточка сохраняется:")
