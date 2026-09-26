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


func test_state_events() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 21)
	check(not TutorialRules.state_events(c, s).has("trauma"), "травм нет — нет события")
	s.character("P01")["traumas"] = ["T02"]
	check(TutorialRules.state_events(c, s).has("trauma"), "первая травма — событие")
	check(not TutorialRules.state_events(c, s).has("camp"), "лагерь в Кошмаре не подсказываем")
	s.chapter = "academy"
	check(TutorialRules.state_events(c, s).has("camp"), "в Академии — подсказка про лагерь")


func test_hint_events_exist() -> void:
	var c := content()
	var known := ["map", "brief", "launch", "arrival", "report", "trauma", "rest", "shop", "fork", "cost", "expires", "exclusive",
		"boss", "sky_eclipse", "sky_blood_moon", "academy_start", "trust", "bond", "panic", "growth", "camp", "journal", "onslaught", "psyche"]
	for hid: String in c.tutorial:
		check(known.has(str(c.tutorial[hid]["event"])), "событие подсказки %s известно" % hid)
