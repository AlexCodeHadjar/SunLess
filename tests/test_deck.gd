extends TestCase
## Колода событий главы (DeckRules, docs/16 §11.4).


func _shore(seed_value: int = 17) -> RunState:
	return MissionFlow.new_run(content(), seed_value, "shore")


func _group(c: Content, name: String) -> Dictionary:
	for g: Dictionary in DeckRules.groups(c, "shore"):
		if str(g.get("name", "")) == name:
			return g
	return {}


func _picked_units(c: Content, deck: Array, g: Dictionary) -> Array:
	var out: Array = []
	for u: Variant in g.get("units", []):
		var d := DeckRules.unit(u)
		if deck.has(d["missions"][0]):
			out.append(d)
	return out


func test_deck_rolled_at_chapter_start() -> void:
	var c := content()
	var s := _shore()
	check(s.flags.get("deck", {}).has("shore"), "колода Берега вытянута при открытии главы")
	eq(DeckRules.roll(c, 17, "shore"), s.flags["deck"]["shore"], "одно зерно — одна колода:")
	var differ := false
	for sd in range(1, 20):
		if DeckRules.roll(c, sd, "shore") != DeckRules.roll(c, 17, "shore"):
			differ = true
	check(differ, "у разных зёрен колоды разные")
	check(DeckRules.groups(c, "nightmare").is_empty(), "у обучающей главы колоды нет")


func test_counts_units_and_chains() -> void:
	var c := content()
	var side := _group(c, "side")
	var rnd := _group(c, "random")
	var seen := {}
	for sd in 80:
		var deck := DeckRules.roll(c, 1000 + sd, "shore")
		var su := _picked_units(c, deck, side)
		eq(su.size(), 5, "побочных единиц 5 из 7:")
		eq(_picked_units(c, deck, rnd).size(), 6, "случайных 6 из 10:")
		check(su.any(func(d: Dictionary) -> bool: return d["chain"]), "хотя бы одна цепочка всегда (зерно %d)" % sd)
		# единица идёт целиком: пара-выбор и цепочки
		for u: Variant in side["units"]:
			var d := DeckRules.unit(u)
			var n: int = d["missions"].filter(func(x: String) -> bool: return deck.has(x)).size()
			check(n == 0 or n == d["missions"].size(), "%s — целиком или никак" % d["id"])
		for mid: String in deck:
			seen[mid] = true
	for g: Dictionary in [side, rnd]:
		for u: Variant in g["units"]:
			check(seen.has(DeckRules.unit(u)["missions"][0]), "единица %s когда-нибудь выпадает" % DeckRules.unit(u)["id"])


func test_open_respects_deck() -> void:
	var c := content()
	var s := _shore()
	var deck: Array = s.flags["deck"]["shore"]
	var out_id := ""
	var in_id := ""
	for u: Variant in _group(c, "random")["units"]:
		var mid := str(u)
		if deck.has(mid) and in_id == "":
			in_id = mid
		if not deck.has(mid) and out_id == "":
			out_id = mid
	eq(MissionFlow.open(c, s, out_id), [], "не выпавшая миссия не открывается:")
	check(not s.missions.has(out_id), "и не попадает в сохранение")
	check(not MissionFlow.open(c, s, in_id).is_empty(), "выпавшая открывается")
	check(not MissionFlow.open(c, s, out_id, true).is_empty(), "force — открыть всё равно")
	check(DeckRules.allowed(c, s, "SH20") and DeckRules.allowed(c, s, "NS01"), "сюжет и натиск — вне колоды")
	# доска слухов не намекает на то, чего в этом прохождении не будет
	for r: Dictionary in CampRules.rumors(c, s, 50):
		check(DeckRules.allowed(c, s, str(r["mission"])), "слух о не выпавшей %s" % r["mission"])


func test_spawn_random_skips_out_of_deck() -> void:
	var c := content()
	var s := _shore()
	s.flags["deck"]["shore"] = ["RS02"]   # из пула лабиринта выпала только вторая
	s.missions["SH21"] = {"status": "done"}   # место достигнуто
	var ev := MissionFlow.spawn_random(c, s, "coral_maze")
	eq(ev.size(), 1, "открыта одна:")
	check(s.missions.has("RS02") and not s.missions.has("RS01"), "RS01 пропущена, открыта RS02")
	eq(MissionFlow.spawn_random(c, s, "coral_maze"), [], "больше в пуле ничего нет:")


func test_chain_progress() -> void:
	var c := content()
	var s := _shore()
	s.flags["deck"]["shore"] = ["SC01", "SC02", "SC03"]
	for mid: String in ["SH19", "SH20", "SH21", "SH22"]:
		s.missions[mid] = {"status": "done"}
	MissionFlow.after_completion(c, s)
	eq(str(s.missions.get("SC01", {}).get("status", "")), "open", "после SH22 открыт голос из воды:")
	check(not s.missions.has("SC04"), "вторая цепочка не выпала — не открыта")
	s.missions["SC01"]["status"] = "done"
	MissionFlow.after_completion(c, s)
	eq(str(s.missions.get("SC02", {}).get("status", "")), "open", "за ним — затопленный алтарь:")
	eq(DeckRules.chain_info(c, "SC02"), {"name": "Песнь глубин", "index": 2, "total": 3}, "брифинг знает место в цепочке:")
	eq(DeckRules.chain_info(c, "SS01"), {}, "одиночная — не цепочка:")
	eq(str(c.missions["SC03"].get("memory", "")), "boss", "конец цепочки — Воспоминание всегда:")
	eq(str(c.missions["SC06"].get("memory", "")), "boss", "конец второй цепочки — тоже:")


func test_old_save_gets_deck() -> void:
	var c := content()
	var s := _shore(23)
	s.flags.erase("deck")
	DeckRules.allowed(c, s, "RS05")
	eq(s.flags.get("deck", {}).get("shore", []), DeckRules.roll(c, 23, "shore"), "колода тянется при первом обращении:")


func test_tide_spares_chain_links() -> void:
	var c := content()
	check(TideRules.washable(c, "RS05") and TideRules.washable(c, "SS04"), "случайные и побочные вода смывает")
	check(not TideRules.washable(c, "SC01") and not TideRules.washable(c, "SC03"), "звенья цепочки ждут отлива")
	check(not TideRules.washable(c, "SH20"), "сюжетные — тоже")
	check(float(c.missions["SC01"].get("expires", 0)) > 0.0 and float(c.missions["SC02"].get("expires", 0)) == 0.0,
		"срок — только у первого звена")
