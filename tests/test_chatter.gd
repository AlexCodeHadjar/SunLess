extends TestCase
## Мысли и реплики героев над картами (ChatterRules, data/chatter.json): данные целы, говорят только те, кто в отряде,
## реплики привязаны к месту, сюжету и Воспоминаниям в кармашках, общие фразы редки.

const KNOWN := ["nightmare", "academy", "shore", "tree", "dark_city", "city", "night", "dawn", "storm", "blood_moon", "day",
	"dusk", "ash_storm", "morning", "midday", "place", "story", "after_win", "after_loss", "after_night", "move", "water", "idle",
	"low", "high", "edge", "pocket", "knows", "skill", "worn", "no_pocket", "wander"]


func _known(c: Content, t: String) -> bool:
	if KNOWN.has(t):
		return true
	if t.begins_with("at:"):
		return c.locations.has(t.substr(3)) or c.shops.has(t.substr(3))
	if t.begins_with("story:") or t.begins_with("done:"):
		return c.missions.has(t.get_slice(":", 1))
	if t.begins_with("with:"):
		return c.characters.has(t.substr(5))
	if t.begins_with("pocket@"):
		return c.characters.has(t.substr(7))
	return false


func test_data() -> void:
	var c := content()
	var lines: Array = c.chatter.get("lines", [])
	var dialogs: Array = c.chatter.get("dialogs", [])
	check(lines.size() >= 120, "реплик хватает: %d" % lines.size())
	check(dialogs.size() >= 20, "диалогов хватает: %d" % dialogs.size())
	var tied := 0
	for l: Dictionary in lines:
		var h := str(l["hero"])
		check(h == "*" or c.characters.has(h), "герой реплики %s есть: %s" % [l["id"], h])
		check(ChatterRules.KINDS.has(str(l["kind"])), "вид реплики %s" % l["id"])
		for t: String in l["when"]:
			check(_known(c, t), "тег %s у %s известен" % [t, l["id"]])
		if (l["when"] as Array).any(func(t: String) -> bool: return t.begins_with("at:") or t.begins_with("story") \
				or t.begins_with("done:") or t in ["pocket", "knows", "skill", "worn", "no_pocket", "place"]):
			tied += 1
	check(tied * 2 > lines.size(), "больше половины реплик — о месте, сюжете и Воспоминаниях: %d из %d" % [tied, lines.size()])
	for d: Dictionary in dialogs:
		for t: String in d["when"]:
			check(_known(c, t), "тег %s у %s известен" % [t, d["id"]])
		for l: Array in d["lines"]:
			check((d["heroes"] as Array).has(l[0]), "в диалоге %s говорят его герои" % d["id"])
	var st: Dictionary = c.chatter.get("settings", {})
	check(float((st.get("every", [0, 0]) as Array)[0]) >= 45.0, "реплики редкие: не чаще раза в 45 с")


func test_only_present_heroes_speak() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 31, "shore")
	var rng := RandomNumberGenerator.new()
	for i in 80:
		rng.seed = i
		var r := ChatterRules.pick(c, s, ["P01"], [], false, [], rng)
		check(not r.is_empty(), "Санни есть что сказать")
		for l: Array in r["lines"]:
			eq(str(l[0]), "P01", "говорит только тот, кто в отряде:")
			check(not str(l[2]).contains("{"), "подстановки заполнены: %s" % l[2])


## Без намёков на игру (решение владельца 03.10): ни цифр, ни «кармашков», ни заданий в кавычках.
func test_no_game_words() -> void:
	var c := content()
	var bad := ["кармаш", "навык", "бонус", "%", "миссия", "задани", "фигур", "каменный я"]
	var texts: Array = []
	for l: Dictionary in c.chatter["lines"]:
		texts.append(str(l["text"]))
	for d: Dictionary in c.chatter["dialogs"]:
		for x: Array in d["lines"]:
			texts.append(str(x[1]))
	for t: String in texts:
		for w: String in bad:
			check(not t.to_lower().contains(w), "без игровых слов «%s»: %s" % [w, t])
		check(not t.contains("{story}") and not t.contains("{skill_text"), "без названий заданий и описаний свойств: %s" % t)
	# польза Воспоминания — словами, без цифр
	for k: String in c.enhancements:
		var u := ChatterRules.use_phrase(c, k)
		check(u != "" and not u.contains("+") and not u.contains("%") and not u.is_valid_int(), "польза словами: %s" % u)
		for ch in "0123456789":
			check(not u.contains(ch), "без цифр: %s" % u)


func test_place_and_story() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 33, "shore")
	s.party_at = "coral_maze"
	var sc := ChatterRules.scene(c, s, ["P01"])
	check((sc["tags"] as Array).has("at:coral_maze"), "место фигуры — в тегах")
	check((sc["tags"] as Array).has("story"), "сюжетное событие главы открыто")
	var story_ids: Array = []
	for l: Dictionary in c.chatter["lines"]:
		if (l["when"] as Array).any(func(t: String) -> bool: return t.begins_with("story")):
			story_ids.append(str(l["id"]))
	var rng := RandomNumberGenerator.new()
	var place := 0
	var story := 0
	for i in 200:
		rng.seed = 1000 + i
		var r := ChatterRules.pick(c, s, ["P01"], [], false, [], rng)
		if str(r["lines"][0][2]).contains("Багровый лабиринт"):
			place += 1
		if story_ids.has(str(r["id"])):
			story += 1
		check(not str(r["lines"][0][2]).contains("+"), "без цифр: %s" % r["lines"][0][2])
	check(place >= 10, "о месте говорят часто: %d из 200" % place)
	check(story >= 5, "о сюжете тоже: %d из 200" % story)


func test_pocket_memory() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 35, "shore")
	var card := ""
	for k: String in c.enhancements:
		if not Dictionary(c.enhancements[k].get("memory", {})).is_empty():
			card = k
			break
	EffectApplier.add_card(c, s, card)
	var h := ChatterRules.hero(c, s, "P01")
	check((h["tags"] as Array).has("no_pocket"), "кармашек пуст, а Воспоминание свободно — no_pocket")
	s.character("P01")["pocket"] = [card]
	h = ChatterRules.hero(c, s, "P01")
	check((h["tags"] as Array).has("pocket") and (h["tags"] as Array).has("skill"), "в кармашке Воспоминание с навыком")
	var rng := RandomNumberGenerator.new()
	var about := 0
	for i in 200:
		rng.seed = 2000 + i
		var r := ChatterRules.pick(c, s, ["P01"], [], false, [], rng)
		for l: Array in r["lines"]:
			if str(l[2]).contains(c.card_name(card)) or str(l[2]).contains(str(c.enhancements[card]["memory"]["name"])):
				about += 1
	check(about >= 15, "о Воспоминании в кармашке говорят: %d из 200" % about)


func test_event_poke_and_recent() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 37, "shore")
	EffectApplier.add_card(c, s, "P02")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var r := ChatterRules.pick(c, s, ["P01", "P02"], ["after_win"], true, [], rng)
	check(not r.is_empty(), "после удачи есть что сказать")
	var ids: Array = []
	for l: Dictionary in c.chatter["lines"]:
		if (l["when"] as Array).has("after_win"):
			ids.append(str(l["id"]))
	for d: Dictionary in c.chatter["dialogs"]:
		if (d["when"] as Array).has("after_win"):
			ids.append(str(d["id"]))
	check(ids.has(str(r["id"])), "реплика — именно про удачу: %s" % r["id"])
	var recent: Array = ids.duplicate()
	eq(ChatterRules.pick(c, s, ["P01", "P02"], ["after_win"], true, recent, rng), {}, "недавние не повторяются:")
