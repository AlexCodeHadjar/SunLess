extends TestCase
## Ф10 (docs/16 §9): лагерь — койки, ускоренный отдых, лечение лёгких травм, доска слухов.


func test_beds() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 21)
	eq(CampRules.put(c, s, "P01"), "Лагерь откроется в Академии", "в Кошмаре лагеря нет:")
	s.chapter = "academy"
	for cid: String in ["P09", "P10"]:
		EffectApplier.add_card(c, s, cid)
	eq(CampRules.put(c, s, "P01"), "", "Санни на койке:")
	eq(CampRules.put(c, s, "P09"), "", "Шолар на койке:")
	check(CampRules.put(c, s, "P10").contains("заняты"), "третьему места нет")
	s.character("P01")["edge"] = true
	s.character("P01")["panic"] = 60
	var s2 := RunState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check(CampRules.in_bed(s2, "P01"), "лагерь сохраняется")
	# уход на миссию освобождает койку
	MissionFlow.open(c, s, "MS02")
	var r := MissionFlow.launch(c, s, "MS02", ["P09"])
	check(bool(r["ok"]), "отряд ушёл: %s" % r.get("error", ""))
	check(not CampRules.in_bed(s, "P09"), "койка освободилась")
	s.squads.clear()
	# ночь: на койке герой отлёживается — отходит от грани и отдыхает лучше
	var out := DayRules.end_day(c, s)
	check(not EdgeRules.on_edge(s, "P01"), "на койке герой отходит от грани за ночь")
	check(out.any(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "recover"), "запись об этом")
	check(PsycheRules.value(s, "P01") < 60, "психика восстановилась")
	check(CampRules.beds(s).is_empty(), "утром койки свободны")


func test_rumors() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 21)
	var rs := CampRules.rumors(c, s)
	check(not rs.is_empty(), "в начале главы есть слухи о будущих миссиях")
	for r: Dictionary in rs:
		check(not s.missions.has(r["mission"]), "слух — о ещё не открытой миссии")
		eq(MissionFlow.chapter_of(c, r["mission"]), s.chapter, "слух из текущей главы:")
