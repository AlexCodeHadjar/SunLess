extends TestCase
## Задания справа (QuestRules, docs/20): сюжет главы с местом и путём, побочные линии колоды, угрозы, «сюжет ждёт».


func test_story_entry_with_place() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 51, "shore")
	check(QuestRules.goal(c, s) != "", "у главы есть цель")
	var list := QuestRules.list(c, s)
	check(not list.is_empty() and str(list[0]["kind"]) == "story", "первым — сюжет: %s" % str(list))
	var e: Dictionary = list[0]
	check(str(e["place"]) != "" and str(e["place_name"]) != "", "у сюжета есть место")
	check(str(e["line"]) != "" and not str(e["line"]).contains("{"), "понятно, что делать: %s" % e["line"])
	if str(e["place"]) == s.party_at:
		check(str(e["line"]).begins_with("Здесь"), "событие у фигуры — «здесь»")


func test_far_story_shows_steps() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 52, "shore")
	_reveal(c, s)
	var story: Dictionary = QuestRules.list(c, s)[0]
	var far := ""
	for lid: String in MapRules.config(c, "shore").get("places", {}):
		if c.locations.has(lid) and TravelRules.distance(c, s, lid) >= 2 and lid != str(story["place"]):
			far = lid
			break
	s.party_at = far
	var e: Dictionary = QuestRules.entry(c, s, str(story["id"]))
	check(int(e["steps"]) >= 1, "сюжет вдали — шагов до него %d" % int(e["steps"]))
	check(str(e["line"]).contains(str(e["place_name"])), "в строке — куда идти: %s" % e["line"])
	eq(int(e["steps"]), FigureRules.reach(c, s, str(story["id"])), "шаги — как у фигуры:")


func test_side_chain_named() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 53, "shore")
	MissionFlow.open(c, s, "SC01", true)
	var found := {}
	for e: Dictionary in QuestRules.list(c, s):
		if str(e["id"]) == "SC01":
			found = e
	check(not found.is_empty(), "цепочка колоды — в заданиях")
	eq(str(found.get("kind", "")), "side", "побочная линия:")
	eq(str(found.get("group", "")), "Песнь глубин", "с именем линии:")
	# случайные встречи — не задания
	MissionFlow.open(c, s, "RS05", true)
	check(not QuestRules.list(c, s).any(func(e: Dictionary) -> bool: return str(e["id"]) == "RS05"), "случайная встреча — не задание")


func test_story_wait() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 54, "city")
	for mid: String in c.missions:
		if MissionFlow.chapter_of(c, mid) == "city" and str(c.missions[mid].get("type", "")) == "story" and mid < "CS04":
			s.missions[mid] = {"status": "done"}
	for mid2: String in MissionFlow.open_missions(s):
		if str(c.missions[mid2].get("type", "")) == "story":
			s.missions[mid2]["status"] = "done"
	var list := QuestRules.list(c, s)
	check(not list.is_empty() and str(list[0]["id"]) == "wait", "нет открытого сюжета — «Сюжет ждёт»: %s" % str(list.slice(0, 1)))
	if not list.is_empty():
		check(str(list[0]["line"]).contains("Врата"), "ждёт Врат: %s" % list[0]["line"])


func _reveal(c: Content, s: RunState) -> void:
	for lid: String in MapRules.config(c, s.chapter).get("places", {}):
		TravelRules.visit(s, lid)
