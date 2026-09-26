extends TestCase
## Ф11 (docs/16 §9): разбор после миссии, бестиарий, журнал слухов.


func _run() -> RunState:
	var c := content()
	var s := MissionFlow.new_run(c, 21)
	for cid: String in ["P02", "P03", "P04"]:
		EffectApplier.add_card(c, s, cid)
	MissionFlow.open(c, s, "MS02")
	return s


func test_debrief_lines() -> void:
	var c := content()
	var s := _run()
	s.missions["MS03"] = {"status": "open", "attempts": 0}
	var r := MissionFlow.launch(c, s, "MS03", ["P02", "P04"])
	MissionFlow.tick(c, s, 20.0)
	var res := MissionResolver.resolve_through(c, s, int(r["squad"]["id"]), "MS03_fight")
	var lines := MissionDebrief.lines(res["report"])
	check(not lines.is_empty() and lines.size() <= MissionDebrief.MAX_LINES, "разбор: 1–3 строки (%d)" % lines.size())
	check(lines.any(func(l: Dictionary) -> bool: return str(l["text"]).contains("раунды")), "бой в разборе: счёт раундов")
	# проверка: не хватило — с числами
	var rep := {"stages": [{"name": "Подъём", "outcome": "fail", "why": {"kind": "check", "stat": "will", "have": 6, "need": 9, "help": {}, "hurt": {"source": "Перелом", "value": -1}}}]}
	var l2 := MissionDebrief.lines(rep)
	eq(str(l2[0]["text"]), "«Подъём»: не хватило: Воля 6 из 9 (Перелом -1)", "строка провала:")
	check(not bool(l2[0]["good"]), "провал — красным")


func test_check_why() -> void:
	var c := content()
	var s := _run()
	var m: Dictionary = c.missions["MS02"]
	var a: Dictionary = m["actions"][0]
	var st: Dictionary = a["stages"][0]
	var w := MissionDebrief.check_why(c, s, m, a, st, ["P01"], "P01")
	if Dictionary(st.get("req", {})).is_empty():
		check(w.is_empty(), "без требований — нечего разбирать")
	else:
		check(int(w["need"]) > 0 and w["stat"] in ["power", "will", "cunning"], "разбор проверки: характеристика и числа")


func test_bestiary_and_rumors() -> void:
	var c := content()
	var s := _run()
	s.missions["MS03"] = {"status": "open", "attempts": 0}
	var r := MissionFlow.launch(c, s, "MS03", ["P02", "P04"])
	MissionFlow.tick(c, s, 20.0)
	var res := MissionResolver.resolve_through(c, s, int(r["squad"]["id"]), "MS03_fight")
	var ns: RunState = res["state"]
	var best := JournalRules.bestiary(ns)
	check(not best.is_empty(), "после боя враг в бестиарии")
	for eid: String in best:
		check(int(best[eid]["fights"]) >= 1, "бой записан")
		if int(best[eid]["wins"]) > 0:
			eq(Array(best[eid]["tags"]).size(), Array(c.enemies[eid].get("tags", [])).size(), "победа раскрывает все теги %s:" % eid)
	# слух, чей тег проявился, подтверждается
	var m: Dictionary = c.missions["MS03"]
	var shown := JournalRules.shown_tags(c, m, res["report"], ["P02", "P04"], ns)
	var rs: Array = m.get("rumors", [])
	for i in rs.size():
		eq(JournalRules.confirmed(ns, "MS03", i), shown.has(str(rs[i]["tag"])), "слух %d подтверждён ровно когда тег проявился:" % i)
	var s2 := RunState.from_dict(JSON.parse_string(JSON.stringify(ns.to_dict())))
	eq(s2.journal, ns.journal, "журнал сохраняется:")
