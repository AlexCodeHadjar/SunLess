extends TestCase
## Сюжетные окна (docs/16 §9е): вступление к каждой главе, показ один раз, проявление по словам.


func test_every_chapter_has_story() -> void:
	var c := content()
	for pair: Array in DevPanel.chapters(c):
		var pages: Array = c.story.get(pair[0], {}).get("pages", [])
		check(not pages.is_empty(), "у главы %s есть сюжетное окно" % pair[0])


func test_pending_once() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 5)
	check(not StoryRules.pending(c, s).is_empty(), "новая игра начинается со вступления")
	StoryRules.mark_seen(s, s.chapter)
	check(StoryRules.pending(c, s).is_empty(), "увиденное второй раз не показывается")
	MissionFlow.start_chapter(c, s, "academy")
	check(not StoryRules.pending(c, s).is_empty(), "новая глава — своё окно")
	var s2 := RunState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check(StoryRules.seen(s2, "nightmare"), "отметка сохраняется")


func test_word_ends() -> void:
	eq(StoryRules.word_ends("Он  спит.\nСон"), [2, 9, 13], "концы слов:")
	eq(StoryRules.word_ends(""), [], "пустой текст:")
