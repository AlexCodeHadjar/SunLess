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
	s.rest_until["P01"] = s.clock + 40.0
	s.character("P01")["traumas"] = ["T02", "T03"]
	s.character("P01")["panic"] = 40
	var out := CampRules.tick(c, s, 10.0)
	check(float(s.rest_until["P01"]) - s.clock <= 30.0 + 0.01, "отдых на койке идёт вдвое быстрее")
	check(PanicRules.value(s, "P01") < 40, "паника спадает")
	for i in 10:
		out.append_array(CampRules.tick(c, s, 10.0))
	check(not Array(s.character("P01")["traumas"]).has("T02"), "лёгкая рана прошла")
	check(Array(s.character("P01")["traumas"]).has("T03"), "перелом койка не лечит")
	check(out.any(func(e: Dictionary) -> bool: return str(e["text"]).contains("прошло")), "запись о лечении")
	var s2 := RunState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check(CampRules.in_bed(s2, "P01"), "лагерь сохраняется")
	# уход на миссию освобождает койку
	MissionFlow.open(c, s, "MS02")
	s.rest_until.clear()
	var r := MissionFlow.launch(c, s, "MS02", ["P09"])
	check(bool(r["ok"]), "отряд ушёл: %s" % r.get("error", ""))
	check(not CampRules.in_bed(s, "P09"), "койка освободилась")


func test_rumors() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 21)
	var rs := CampRules.rumors(c, s)
	check(not rs.is_empty(), "в начале главы есть слухи о будущих миссиях")
	for r: Dictionary in rs:
		check(not s.missions.has(r["mission"]), "слух — о ещё не открытой миссии")
		eq(MissionFlow.chapter_of(c, r["mission"]), s.chapter, "слух из текущей главы:")
