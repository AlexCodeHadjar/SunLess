extends TestCase
## Старт «разбитое стекло» (StartRules, docs/16 §11.5): три старта с Берега, Санни всегда в отряде и уже Спящий с Тенью.


func test_three_starts() -> void:
	var c := content()
	var ids: Array = StartRules.list(c).map(func(s: Dictionary) -> String: return str(s["id"]))
	eq(ids, ["sunny", "nephis", "cassie"], "три осколка:")
	for st: Dictionary in StartRules.list(c):
		for card: String in Array(st["heroes"]) + Array(st["cards"]):
			check(c.card_kind(card) != "", "карта старта %s есть" % card)


func test_start_runs() -> void:
	var c := content()
	for id: String in ["sunny", "nephis", "cassie"]:
		var s := StartRules.new_run(c, 77, id)
		eq(s.chapter, "shore", "%s — с Берега:" % id)
		check(s.owns("P01"), "%s: Санни в отряде" % id)
		eq(str(s.character("P01")["stage"]), "sleeper", "%s: Санни — Спящий:" % id)
		check(Array(s.character("P01").get("abilities", [])).has("A01"), "%s: Тень с ним" % id)
		check(not MissionFlow.open_missions(s).is_empty(), "%s: есть что делать" % id)
	var n := StartRules.new_run(c, 78, "nephis")
	check(n.owns("P02") and n.owns("U14"), "Нефис и её уроки меча")
	check(TrustRules.value(n, "P01", "P02") >= 3, "Санни и Нефис доверяют друг другу")
	var k := StartRules.new_run(c, 79, "cassie")
	check(MissionFlow.has_scout(c, k, ["P01"]), "старт Касси: скрытое видно сразу")
	var sn := StartRules.new_run(c, 80, "sunny")
	check(not sn.owns("P02") and not sn.owns("P03"), "Санни — один")
	check(int(sn.resources["shards"]) < int(n.resources["shards"]), "у Санни осколков меньше")


func test_start_game_runs() -> void:
	var c := content()
	var s := StartRules.new_run(c, 81, "sunny")
	for i in 400:
		var r := AutoPlay.step(c, s)
		s = r["state"]
		eq(str(r["error"]), "", "бот играет со старта без ошибок:")
		if str(r["error"]) != "" or s.game_over or s.chapter != "shore":
			break
