extends TestCase
## Ф11 (docs/16 §9): Натиск Кошмара — приходит по часам, не отбит — последствия, отбит — доверие.


func _academy() -> RunState:
	var c := content()
	var s := MissionFlow.new_run(c, 21)
	for cid: String in ["P02", "P03"]:
		EffectApplier.add_card(c, s, cid)
	s.chapter = "academy"
	for mid: String in ["MA12", "MA13", "MA14"]:
		s.missions[mid] = {"status": "done", "attempts": 0}
	return s


func test_arrives() -> void:
	var c := content()
	var s := _academy()
	var cfg := OnslaughtRules.config(c, "academy")
	check(not cfg.is_empty(), "у Академии есть натиск")
	var none := _academy()
	none.missions.erase("MA14")
	MissionFlow.tick(c, none, 1.0)
	MissionFlow.tick(c, none, 400.0)
	eq(OnslaughtRules.active(c, none), "", "до %d миссий главы натиска нет:" % int(cfg["first_after"]))
	MissionFlow.tick(c, s, 1.0)
	check(OnslaughtRules.next_at(s) > s.clock, "натиск назначен")
	var ev := MissionFlow.tick(c, s, OnslaughtRules.next_at(s) - s.clock + 0.1)
	var mid := OnslaughtRules.active(c, s)
	check(mid != "", "натиск пришёл")
	check(ev.any(func(e: Dictionary) -> bool: return e["kind"] == "onslaught"), "событие для карты")
	check(MissionFlow.expires_in(c, s, mid) > 0.0, "у натиска срок")


func test_expire_and_reward() -> void:
	var c := content()
	var s := _academy()
	s.resources["shards"] = 10
	MissionFlow.open(c, s, "NA01")
	MissionFlow.tick(c, s, float(c.missions["NA01"]["expires"]) + 1.0)
	eq(str(s.missions["NA01"]["status"]), "expired", "не ответили — ушло:")
	eq(int(s.resources["shards"]), 7, "потеряно 3 осколка:")
	check(PanicRules.value(s, "P01") > 0, "герои встревожены")
	# отбили — доверие
	var s2 := _academy()
	var m: Dictionary = c.missions["NA01"]
	var out := OnslaughtRules.reward(c, s2, m, ["P01", "P02"], "success")
	check(not out.is_empty() and TrustRules.value(s2, "P01", "P02") == OnslaughtRules.TRUST_BONUS, "отбили натиск — доверие +1")
	check(OnslaughtRules.reward(c, s2, c.missions["MA12"], ["P01", "P02"], "success").is_empty(), "обычная миссия — без этого")
