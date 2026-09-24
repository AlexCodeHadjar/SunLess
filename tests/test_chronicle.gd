extends TestCase
## Свободный режим — «Хроника с якорями» на главе «Академия».


func _academy() -> Array:
	var c := content()
	var s := EventFlow.new_run(c, 7)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	s.characters["P01"]["stage"] = "sleeper"
	Chronicle.start_chapter(c, s, "academy", rng)
	s.week = s.chapter_start
	return [c, s, rng]


func test_start_chapter() -> void:
	var p := _academy()
	var s: RunState = p[1]
	eq(s.region, "academy", "регион:")
	eq(s.node, "medbay", "старт:")
	check(s.is_event_active("E12"), "E12 на карте")
	eq(Chronicle.weeks_left(p[0], s), 18, "отсчёт:")


func test_move_costs_weeks() -> void:
	var p := _academy()
	var c: Content = p[0]
	var s: RunState = p[1]
	var w := s.week
	var r := Chronicle.move(c, s, "dorm", p[2])
	check(r["ok"], "переход в соседнее место")
	eq(s.week, w + 1, "соседнее место — неделя:")
	var steps := Chronicle.path(c, s, "library").size()
	check(steps >= 2, "до библиотеки не меньше двух переходов")
	Chronicle.move(c, s, "library", p[2])
	eq(s.week, w + 1 + steps, "путь — неделя за шаг:")
	eq(s.node, "library", "герой в библиотеке:")


func test_events_open_only_here() -> void:
	var p := _academy()
	var c: Content = p[0]
	var s: RunState = p[1]
	check(Chronicle.can_open(c, s, "E12"), "E12 в медкрыле открывается")
	s.node = "gate"
	check(not Chronicle.can_open(c, s, "E12"), "из другого места E12 не открыть")


func test_final_place_locked() -> void:
	var p := _academy()
	var r := Chronicle.move(p[0], p[1], "capsules", p[2])
	check(not r["ok"], "зал капсул закрыт до срока")


func test_anchors_unlock_in_free_order() -> void:
	var p := _academy()
	var c: Content = p[0]
	var s: RunState = p[1]
	s.events["E12"]["status"] = "closed"
	Chronicle.unlock(c, s, p[2])
	check(s.is_event_active("E13"), "после E12 — E13")
	check(not s.is_event_active("E14"), "E14 ещё закрыт")
	s.events["E13"]["status"] = "closed"
	Chronicle.unlock(c, s, p[2])
	for eid: String in ["E14", "E15", "E16", "SA1"]:
		check(s.is_event_active(eid), "после E13 открыт %s" % eid)
	check(not s.is_event_active("E17"), "E17 ждёт уроков или срока")
	s.week = s.chapter_start + 14
	Chronicle.unlock(c, s, p[2])
	check(s.is_event_active("E17"), "за 4 недели до срока E17 открывается сам")


func test_final_at_deadline() -> void:
	var p := _academy()
	var c: Content = p[0]
	var s: RunState = p[1]
	s.week = s.chapter_start + 18
	Chronicle.unlock(c, s, p[2])
	check(s.is_event_active("E18"), "солнцестояние наступило")
	eq(str(s.events["E12"]["status"]), "missed", "незавершённое упущено:")
	eq(s.node, "capsules", "героя увели в зал капсул:")
	Chronicle.unlock(c, s, p[2])
	check(not s.events.has("E17"), "после финала новые якоря не появляются")


func test_rest_heals_light_trauma() -> void:
	var p := _academy()
	var c: Content = p[0]
	var s: RunState = p[1]
	Chronicle.move(c, s, "dorm", p[2])
	s.characters["P01"]["traumas"] = ["T02", "T03"]
	var w := s.week
	var r := Chronicle.rest(c, s, p[2])
	check(r["ok"], "отдых в лагере")
	eq(s.week, w + 1, "отдых — неделя:")
	check(not Array(s.characters["P01"]["traumas"]).has("T02"), "лёгкая травма снята")
	check(Array(s.characters["P01"]["traumas"]).has("T03"), "тяжёлая осталась")


func test_initiator_event_appears_here() -> void:
	var p := _academy()
	var c: Content = p[0]
	var s: RunState = p[1]
	EffectApplier.add_card(c, s, "I04")
	EventFlow.use_initiator(c, s, "I04", p[2])
	eq(Chronicle.event_node(c, s, "SE10"), "medbay", "кузнец появляется рядом с героем:")
