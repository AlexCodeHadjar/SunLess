extends TestCase
## Ф11 (docs/16 §9): Натиск Кошмара — приходит по дням, не отбит — последствия, отбит — доверие.


func _academy() -> RunState:
	var c := content()
	var s := MissionFlow.new_run(c, 21)
	for cid: String in ["P02", "P03"]:
		EffectApplier.add_card(c, s, cid)
	s.chapter = "academy"
	for mid: String in ["MA12", "MA13", "MA14"]:
		s.missions[mid] = {"status": "done", "attempts": 0}
	return s


func _shore() -> RunState:
	var c := content()
	var s := MissionFlow.new_run(c, 21, "shore")
	for cid: String in ["P02", "P03"]:
		EffectApplier.add_card(c, s, cid)
	for mid: String in ["SH19", "SH20"]:
		s.missions[mid] = {"status": "done", "attempts": 0}
	return s


func test_arrives() -> void:
	var c := content()
	# натиск — у Берега; в Академии его заменили прорывы (GateRules, test_gates)
	check(OnslaughtRules.config(c, "academy").is_empty(), "у Академии натиска нет — там прорывы")
	var s := _shore()
	var cfg := OnslaughtRules.config(c, "shore")
	check(not cfg.is_empty(), "у Берега есть натиск")
	var none := _shore()
	none.missions.erase("SH20")
	for i in 12:
		DayRules.end_day(c, none)
	eq(OnslaughtRules.active(c, none), "", "до %d миссий главы натиска нет:" % int(cfg["first_after"]))
	DayRules.end_day(c, s)
	check(OnslaughtRules.next_day(s) > s.day, "натиск назначен")
	var ev: Array = []
	for i in 8:
		ev.append_array(DayRules.end_day(c, s))
		if OnslaughtRules.active(c, s) != "":
			break
	var mid := OnslaughtRules.active(c, s)
	check(mid != "", "натиск пришёл")
	check(ev.any(func(e: Dictionary) -> bool: return e["kind"] == "onslaught"), "событие для карты")
	check(MissionFlow.expires_in(c, s, mid) > 0, "у натиска срок")


func test_expire_and_reward() -> void:
	var c := content()
	var s := _academy()
	s.resources["shards"] = 10
	MissionFlow.open(c, s, "NA01")
	s.flags["onslaught_day"] = 999
	for i in int(c.missions["NA01"]["expires"]):
		DayRules.end_day(c, s)
	eq(str(s.missions["NA01"]["status"]), "expired", "не ответили — ушло:")
	eq(int(s.resources["shards"]), 7, "потеряно 3 осколка:")
	check(PsycheRules.psyche(s, "P01") < PsycheRules.MAX, "психика героев задета")
	# отбили — доверие
	var s2 := _academy()
	var m: Dictionary = c.missions["NA01"]
	var out := OnslaughtRules.reward(c, s2, m, ["P01", "P02"], "success")
	check(not out.is_empty() and TrustRules.value(s2, "P01", "P02") == OnslaughtRules.TRUST_BONUS, "отбили натиск — доверие +1")
	check(OnslaughtRules.reward(c, s2, c.missions["MA12"], ["P01", "P02"], "success").is_empty(), "обычная миссия — без этого")
