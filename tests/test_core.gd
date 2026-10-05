extends TestCase
## Ядро души (CoreRules, docs/23): осколки → уровни (+1 к характеристике на выбор), полное ядро → испытание души,
## победа → новый ранг (враги этого ранга равны), +1 ко всем характеристикам.


func _run(c: Content) -> RunState:
	var s := MissionFlow.new_run(c, 31, "shore")
	s.party_at = "shelter"
	s.resources["shards"] = 200
	return s


func test_absorb_and_pick() -> void:
	var c := content()
	var s := _run(c)
	var before := int(s.resources["shards"])
	var r := CoreRules.absorb(c, s, "P01")
	check(r["ok"], "впитал: %s" % r["error"])
	eq(int(s.resources["shards"]), before - CoreRules.COST[0][0], "осколки ушли в ядро:")
	eq(CoreRules.level(s, "P01"), 1, "уровень ядра:")
	eq(CoreRules.pending(s, "P01"), 1, "ждёт выбора характеристики:")
	var will0 := int(StatResolver.sheet(c, s, "P01", [])["will"]["total"])
	check(CoreRules.pick(c, s, "P01", "will")["ok"], "выбрал Волю")
	eq(int(StatResolver.sheet(c, s, "P01", [])["will"]["total"]), will0 + 1, "Воля +1:")
	eq(CoreRules.pending(s, "P01"), 0, "выбор сделан:")
	s.resources["shards"] = 0
	check(not CoreRules.absorb(c, s, "P01")["ok"], "без осколков не впитать")


func test_full_core_opens_trial_and_rank() -> void:
	var c := content()
	var s := _run(c)
	for i in CoreRules.LEVELS:
		check(CoreRules.absorb(c, s, "P01")["ok"], "уровень %d" % (i + 1))
	check(CoreRules.full(s, "P01"), "ядро полно")
	check(not CoreRules.absorb(c, s, "P01")["ok"], "дальше — только испытание")
	var mid := CoreRules.trial_id(c, s, "P01")
	eq(str(s.missions.get(mid, {}).get("status", "")), "open", "испытание открыто:")
	eq(FigureRules.reach(c, s, mid), 0, "испытание приходит к фигуре:")
	eq(MissionFlow.place_of(c, s, mid), s.party_at, "на карте — у фигуры:")
	var r0 := CoreRules.rank(c, s, "P01")
	EffectApplier.apply(c, s, {"cmd": "core_rank", "character": "P01"}, "P01", RandomNumberGenerator.new())
	eq(CoreRules.rank(c, s, "P01"), r0 + 1, "новый ранг:")
	eq(CoreRules.level(s, "P01"), 0, "ядро нового ранга — с нуля:")
	var cs := CombatSession.create_for_mission(c, s, "T", {"enemies": ["M01"], "field": "F_05"}, "P01", [], [], {"tags": []}, {"tags": []})
	eq(cs.hero_rank(), r0 + 1, "в бою — новый ранг:")


func test_trials_exist() -> void:
	var c := content()
	for ch: String in ["nightmare", "academy", "shore", "tree", "dark_city", "city"]:
		for cid: String in ["P01", "P02", "P03"]:
			for t in [1, 2]:
				var mid := "TR%d_%s_%s" % [t, ch, cid]
				check(c.missions.has(mid) and MissionFlow.chapter_of(c, mid) == ch, "испытание %s в своей главе" % mid)
