class_name StoryRules
extends RefCounted
## Сюжетные окна (docs/16 §9е): вступление к главе — data/story.json, ключ — id главы.
## Показывается один раз: при новой игре (глава nightmare) и при переходе в следующую главу.


## Страницы, которые надо показать сейчас (пусто — нечего).
static func pending(content: Content, state: RunState) -> Array:
	if state == null or seen(state, state.chapter):
		return []
	return Array(content.story.get(state.chapter, {}).get("pages", []))


static func seen(state: RunState, chapter: String) -> bool:
	return Array(state.flags.get("story_seen", [])).has(chapter)


static func mark_seen(state: RunState, chapter: String) -> void:
	var arr: Array = state.flags.get("story_seen", [])
	if not arr.has(chapter):
		arr.append(chapter)
	state.flags["story_seen"] = arr


## Позиции концов слов: сколько символов показать после каждого следующего слова.
static func word_ends(text: String) -> Array:
	var out: Array = []
	var in_word := false
	for i in text.length():
		var ch := text[i]
		var gap := ch == " " or ch == "\n"
		if gap and in_word:
			out.append(i)
		in_word = not gap
	if in_word:
		out.append(text.length())
	return out
