extends TestCase
## Ф12: обучение — механики по главам и подсказки по первому событию.


func test_unlock_by_chapter() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 21)
	eq(s.chapter, "nightmare", "начинаем в Кошмаре:")
	for mech: String in ["trust", "bonds", "panic", "growth", "camp"]:
		check(not TutorialRules.enabled(s, mech), "в Кошмаре нет: %s" % mech)
	PsycheRules.change(c, s, "P01", -50, "тест")
	eq(PsycheRules.psyche(s, "P01"), PsycheRules.MAX, "психика в Кошмаре не тратится:")
	s.chapter = "academy"
	for mech: String in ["trust", "bonds", "panic", "growth", "camp"]:
		check(TutorialRules.enabled(s, mech), "в Академии есть: %s" % mech)
	s.chapter = "shore"
	check(TutorialRules.enabled(s, "panic"), "дальше — тоже")


func test_hints_once() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 21)
	check(c.tutorial.size() >= 20, "подсказок хватает")
	var h := TutorialRules.take(c, s, "map")
	check(not h.is_empty() and str(h["title"]) != "", "подсказка к карте")
	check(TutorialRules.take(c, s, "map").is_empty(), "второй раз — нет")
	check(TutorialRules.take(c, s, "trust").is_empty(), "подсказка Академии в Кошмаре не показывается")
	s.chapter = "academy"
	check(not TutorialRules.take(c, s, "trust").is_empty(), "в Академии — показывается")
	var s2 := RunState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check(TutorialRules.seen(s2, "T01_map"), "показанные сохраняются")


## Начало поздней главы из режима разработчика: обучение прошлых глав не всплывает, своё — остаётся.
func test_dev_skip_before() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 21)
	eq(TutorialRules.skip_before(c, s), 0, "в Кошмаре ничего не пропускаем:")
	s.chapter = "academy"
	TutorialRules.skip_before(c, s)
	check(TutorialRules.seen(s, "T01_map"), "Академия: базовый цикл Кошмара уже знаком")
	check(not TutorialRules.seen(s, "T40_day"), "Академия: про день подсказка остаётся")
	check(not TutorialRules.take(c, s, "trust").is_empty(), "Академия: свои подсказки показываются")
	var s2 := MissionFlow.new_run(c, 22)
	s2.chapter = "tree"
	check(TutorialRules.skip_before(c, s2) > 30, "Древо: прошлого обучения много — всё отмечено")
	for ev: String in ["map", "trust", "day", "figure", "tide", "traces"]:
		check(TutorialRules.take(c, s2, ev).is_empty(), "Древо: подсказки «%s» прошлых глав нет" % ev)
	var own := 0
	for hid: String in c.tutorial:
		if str(c.tutorial[hid].get("chapter", "")) == "tree" and not TutorialRules.seen(s2, hid):
			own += 1
	check(own >= 5, "Древо: свои подсказки остаются")


func test_state_events() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 21)
	check(not TutorialRules.state_events(c, s).has("edge"), "никто не на грани — нет события")
	s.character("P01")["edge"] = true
	check(TutorialRules.state_events(c, s).has("edge"), "первый герой на грани — событие")
	check(not TutorialRules.state_events(c, s).has("camp"), "лагерь в Кошмаре не подсказываем")
	s.chapter = "academy"
	check(TutorialRules.state_events(c, s).has("camp"), "в Академии — подсказка про лагерь")


func test_hint_events_exist() -> void:
	var c := content()
	var known := ["map", "brief", "launch", "arrival", "report", "edge", "rest", "shop", "fork", "cost", "expires", "exclusive",
		"boss", "sky_eclipse", "sky_blood_moon", "academy_start", "trust", "bond", "panic", "growth", "camp", "journal", "onslaught", "psyche", "tide", "memory",
		"day", "phase", "travel", "camp_place", "tasks", "planner", "emerge", "fatigue", "far",
		"breach_signal", "breach", "swarm", "repair", "gate_omen", "gate_open", "wave", "panic", "scar",
		"mover", "hunters", "zone_charm", "zone_wrath", "territory", "ash_storm", "fragile", "water", "tribute", "rubble",
		"figure", "figure_drag", "figure_camp", "figure_far", "figure_half", "figure_wait", "shatter", "traces", "event_place", "quests", "wanderer", "combat_squad", "tray"]
	for hid: String in c.tutorial:
		check(known.has(str(c.tutorial[hid]["event"])), "событие подсказки %s известно" % hid)
