extends TestCase
## Инструменты разработчика: бот доходит до начала главы, точку можно сохранить и загрузить.


func test_to_chapter() -> void:
	var c := content()
	for ch: String in ["nightmare", "academy", "shore"]:
		var r := AutoPlay.to_chapter(c, ch, 11)
		check(r["ok"], "бот дошёл до главы %s: %s" % [ch, r["error"]])
		if r["ok"]:
			var s: RunState = r["state"]
			eq(s.chapter, ch, "глава в состоянии:")
			check(not s.game_over and not MissionFlow.open_missions(s).is_empty(), "глава %s открыта, есть миссии" % ch)
			check(s.squads.is_empty(), "глава %s — с чистого листа, без отрядов в пути" % ch)


func test_chapters_listed() -> void:
	var ids: Array = DevPanel.chapters(content()).map(func(p: Array) -> String: return p[0])
	eq(ids, ["nightmare", "academy", "shore"], "главы по порядку:")


func test_point_roundtrip() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 3)
	var slot := DevPanel.save_point(s)
	var r: Dictionary = SaveService.load_state(c, slot)
	check(r["ok"], "точка загружается")
	SaveService.delete_save(slot)
	check(not SaveService.has_save(slot), "точка удаляется")
