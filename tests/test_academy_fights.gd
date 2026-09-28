extends TestCase
## Академия (docs/16 §9е п.6): спарринги с персонажами без грани и смерти, смотр — бой двух персонажей со стороны.


func _arrive(c: Content, s: RunState, mid: String, heroes: Array) -> int:
	s.missions[mid] = {"status": "open", "attempts": 0}
	var r := MissionFlow.launch(c, s, mid, heroes)
	check(r["ok"], "%s: отряд ушёл (%s)" % [mid, r.get("error", "")])
	MissionFlow.tick(c, s, 40.0)
	return int(r["squad"]["id"])


func test_spar_has_no_edge() -> void:
	var c := content()
	var lost := 0
	for i in 30:
		var s := MissionFlow.new_run(c, 700 + i)
		s.chapter = "academy"
		var sid := _arrive(c, s, "SA06", ["P01"])
		var r := MissionResolver.resolve_through(c, s, sid, "SA06_fight")
		check(r["ok"], "ход прошёл")
		var ns: RunState = r["state"]
		check(ns.is_alive("P01") and not EdgeRules.on_edge(ns, "P01"), "спарринг не ставит на грань и не убивает")
		if Array(r["report"]["combats"])[0]["outcome"] != "win":
			lost += 1
	check(lost > 0, "Нефис на тренировке бывает сильнее (проигрышей %d из 30)" % lost)


func test_watch_stage() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 42)
	s.chapter = "academy"
	var before := s.to_dict()
	var sid := _arrive(c, s, "RA07", ["P01"])
	var r := MissionResolver.resolve_through(c, s, sid, "RA07_watch")
	check(r["ok"], "смотр прошёл")
	var rep: Dictionary = r["report"]
	check(Array(rep["combats"]).size() == 1 and bool(rep["combats"][0].get("watch", false)), "бой смотра записан для просмотра")
	check(str(rep["stages"][0]["outcome"]) == "ok" and Dictionary(rep["stages"][0]).has("combat"), "смотр — всегда удачный этап с кнопкой «Смотреть бой»")
	var ns: RunState = r["state"]
	check(not ns.owns("P04"), "герой смотра не попадает в коллекцию")
	check(not EdgeRules.on_edge(ns, "P01"), "зрители ничем не рискуют")
	var replay := MissionResolver.replay_session(c, rep["combats"][0]["setup"])
	replay.auto_play()
	eq(replay.outcome, rep["combats"][0]["outcome"], "просмотр совпадает:")
	var fc := MissionForecast.action_forecast(c, MissionFlow.new_run(c, 1), "RA07", MissionFlow.action(c, "RA07", "RA07_watch"), ["P01"], true)
	check(float(fc["risk"]) < 0.5, "прогноз не пугает смотром")
	var _unused := before


func test_ma16_duel_watched() -> void:
	var c := content()
	for a: Dictionary in c.missions["MA16"]["actions"]:
		check(Array(a["stages"]).any(func(st: Dictionary) -> bool: return st.has("watch")), "в MA16 поединок Нефис и Кастера — смотр (%s)" % a["id"])
