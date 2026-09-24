extends TestCase
## Данные проходят проверку; проверка ловит испорченные данные.


func test_data_is_valid() -> void:
	var errors := ContentValidator.validate(content())
	for e in errors:
		check(false, e)


func test_validator_catches_broken_event() -> void:
	var c := content()
	var ev: Dictionary = c.events["E03"].duplicate(true)
	ev["options"].pop_back()
	ev["options"][0]["story"] = true
	ev["next"] = "E999"
	c.events["E03"] = ev
	var errors := ContentValidator.validate(c)
	var joined := "\n".join(errors)
	check(joined.contains("ровно 3"), "должна быть ошибка про 3 варианта")
	check(joined.contains("сюжетных вариантов 2"), "должна быть ошибка про два сюжетных варианта")
	check(joined.contains("E999"), "должна быть ошибка про несуществующее событие")


func test_validator_catches_wearing_story_requirement() -> void:
	var c := content()
	c.enhancements["U02"].erase("wear_exempt_arcs")
	var joined := "\n".join(ContentValidator.validate(c))
	check(joined.contains("изнашиваемую карту U02"), "сюжетный E09 не может требовать изнашиваемый Колокольчик")


func test_stat_resolver_basics() -> void:
	var c := content()
	var s := EventFlow.new_run(c, 1)
	var ev: Dictionary = c.events["E03"]
	var o := c.option("E03", "E03_1")
	var r := StatResolver.resolve(c, s, "P01", [], ev, o)
	eq(r["totals"], {"power": 3, "will": 5, "cunning": 6}, "Санни-раб:")
	EffectApplier.add_card(c, s, "U01")
	r = StatResolver.resolve(c, s, "P01", ["U01"], ev, o)
	eq(r["totals"]["power"], 5, "с U01 Сила:")
	eq(r["totals"]["cunning"], 7, "U01 даёт +1 Хитрость в выживании:")
	s.characters["P01"]["traumas"].append("T02")
	r = StatResolver.resolve(c, s, "P01", ["U01"], ev, o)
	eq(r["totals"]["power"], 4, "с Рваной раной:")


func test_trait_by_tag() -> void:
	var c := content()
	var s := EventFlow.new_run(c, 1)
	var r := StatResolver.resolve(c, s, "P01", [], c.events["E09"], c.option("E09", "E09_2"))
	eq(r["totals"]["cunning"], 7, "«Дитя Теней» +1 в приманке:")
