extends TestCase
## Бродячие боссы (WanderRules, docs/22): появляются в свой день на открытом месте в стороне от игрока, стоят 2–3 дня
## и уходят на другое место (событие уходит вместе с ними), ждут фигуру, если она пришла; побеждённый — уходит навсегда.


func _shore(seed_value: int) -> RunState:
	var c := content()
	var s := MissionFlow.new_run(c, seed_value, "shore")
	EffectApplier.add_card(c, s, "P02")
	for lid: String in MapRules.config(c, "shore").get("places", {}):
		TravelRules.visit(s, lid)
	s.party_at = "shelter"
	return s


func _nights(c: Content, s: RunState, n: int) -> void:
	for i in n:
		DayRules.end_day(c, s)


func test_data() -> void:
	var c := content()
	var list: Array = c.wanderers.get("list", [])
	eq(list.size(), 4, "боссов:")
	var chapters := {}
	for w: Dictionary in list:
		chapters[str(w["chapter"])] = true
		check(c.enemies.has(str(w["enemy"])), "противник босса %s есть" % w["id"])
		eq(str(c.enemies[str(w["enemy"])].get("kind", "")), "boss", "противник — босс (%s):" % w["id"])
		var rw: Dictionary = c.enhancements.get(str(w["reward"]), {})
		check(not rw.is_empty() and str(rw.get("rarity", "")) == "legendary" and not bool(rw.get("loot", true)),
			"награда %s — легендарная и не из общей добычи" % w["reward"])
		check((w["haunts"] as Array).size() >= 4, "у %s хватает мест: %d" % [w["id"], (w["haunts"] as Array).size()])
		for lid: String in w["haunts"]:
			var mid := "%s_%s" % [w["id"], lid]
			check(c.missions.has(mid) and str(c.missions[mid].get("wander", "")) == str(w["id"]), "событие %s есть" % mid)
	eq(chapters.size(), 4, "по боссу на главу:")


func test_appears_away_from_player() -> void:
	var c := content()
	var s := _shore(81)
	var w: Dictionary = WanderRules.defs(c, "shore")[0]
	eq(WanderRules.active(c, s), [], "в начале главы босса нет:")
	_nights(c, s, int(w["appear_day"]))
	var act := WanderRules.active(c, s)
	eq(act.size(), 1, "в свой день босс появился:")
	if act.is_empty():
		return
	var at := str(act[0]["at"])
	check(at != s.party_at, "не у фигуры")
	check(not WanderRules.story_route(c, s).has(at), "не на сюжете и не на пути к нему")
	eq(str(s.missions.get(str(act[0]["mid"]), {}).get("status", "")), "open", "событие босса открыто:")
	for mid: String in MissionFlow.open_missions(s):
		if str(c.missions[mid].get("location", "")) == at:
			check(WanderRules.is_wander(c, mid), "на месте босса нет других событий: %s" % mid)
	check(not (DayPlanner.options(c, s)["today"] as Array).has(str(act[0]["mid"])), "босс — не «дело на сегодня»")
	var quests := QuestRules.list(c, s)
	check(quests.any(func(e: Dictionary) -> bool: return str(e["kind"]) == "boss"), "босс — в заданиях")


func test_moves_and_takes_event_along() -> void:
	var c := content()
	var s := _shore(82)
	var w: Dictionary = WanderRules.defs(c, "shore")[0]
	_nights(c, s, int(w["appear_day"]))
	var first: Dictionary = WanderRules.active(c, s)[0]
	var moved := false
	for i in 6:
		DayRules.end_day(c, s)
		var now: Array = WanderRules.active(c, s)
		if not now.is_empty() and str(now[0]["at"]) != str(first["at"]):
			moved = true
			check(not s.missions.has(str(first["mid"])), "событие на старом месте ушло вместе с боссом")
			eq(str(s.missions.get(str(now[0]["mid"]), {}).get("status", "")), "open", "на новом месте — событие:")
			break
	check(moved, "через 2–3 дня босс уходит на другое место")


func test_waits_for_figure_and_leaves_when_beaten() -> void:
	var c := content()
	var s := _shore(83)
	var w: Dictionary = WanderRules.defs(c, "shore")[0]
	_nights(c, s, int(w["appear_day"]))
	var a: Dictionary = WanderRules.active(c, s)[0]
	s.party_at = str(a["at"])
	_nights(c, s, 4)
	eq(str(WanderRules.active(c, s)[0]["at"]), str(a["at"]), "фигура пришла — босс ждёт её:")
	s.missions[str(a["mid"])]["status"] = "done"
	_nights(c, s, 6)
	eq(WanderRules.active(c, s), [], "побеждённый босс ушёл из главы навсегда:")


func test_not_in_other_chapters() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 84, "academy")
	_nights(c, s, 6)
	eq(WanderRules.active(c, s), [], "в Академии бродячих боссов нет:")
