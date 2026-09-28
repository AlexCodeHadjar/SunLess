extends TestCase
## Воспоминания-добыча (LootRules, docs/16 §11.3): уровень источника, выбор 1 из 3, очередь выборов.


func _shore() -> RunState:
	return MissionFlow.new_run(content(), 41, "shore")


func test_source_tiers() -> void:
	var c := content()
	eq(LootRules.tier_of(c, ["M06"]), "weak", "многоножки — слабые:")
	eq(LootRules.tier_of(c, ["M03"]), "mid", "падальщик — средний:")
	eq(LootRules.tier_of(c, ["M07"]), "strong", "черви — сильные:")
	eq(LootRules.tier_of(c, ["M04"]), "strong", "центурион (элита) — сильный:")
	eq(LootRules.tier_of(c, ["M02"]), "boss", "босс:")
	eq(LootRules.tier_of(c, ["M03", "M03"]), "strong", "два падальщика — сильный бой:")


func test_options_respect_tiers() -> void:
	var c := content()
	var s := _shore()
	var rng := RandomNumberGenerator.new()
	var legendary_seen := false
	for i in 200:
		rng.seed = i
		for tier: String in ["weak", "mid", "strong", "boss"]:
			var opts := LootRules.options(c, s, tier, rng)
			eq(opts.size(), 3, "три карты (%s):" % tier)
			var uniq := {}
			for id: String in opts:
				uniq[id] = true
				var r := str(c.enhancements[id]["rarity"])
				check(bool(c.enhancements[id].get("loot", false)), "%s — добыча" % id)
				check(Dictionary(c.loot["tiers"][tier]).has(r), "%s: %s допустима для %s" % [id, r, tier])
				if r == "legendary":
					legendary_seen = true
					check(tier == "boss", "легендарные — только с боссов и сюжета")
			eq(uniq.size(), 3, "карты не повторяются:")
	check(legendary_seen, "с боссов легендарные выпадают")
	# карты, что уже есть у игрока, не предлагаются
	for id: String in c.enhancements:
		if bool(c.enhancements[id].get("loot", false)) and str(c.enhancements[id]["rarity"]) == "common":
			EffectApplier.add_card(c, s, id)
	rng.seed = 5
	for id: String in LootRules.options(c, s, "weak", rng):
		check(not s.owns(id), "уже взятое не предлагается: %s" % id)


func test_chance_and_chapters() -> void:
	var c := content()
	var s := _shore()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var hits := 0
	for i in 2000:
		if LootRules.roll_fight(c, s, "RS02", ["M06"], rng) != "":
			hits += 1
	check(absf(hits / 2000.0 - 0.15) < 0.03, "слабая тварь — около 15%%: %.1f%%" % (hits / 20.0))
	var n := MissionFlow.new_run(c, 41)
	eq(LootRules.roll_fight(c, n, "MS03", ["M01"], rng), "", "в обучении добычи нет:")
	# проклятая миссия — чаще
	MissionFlow.open(c, s, "RS02", true)
	s.missions["RS02"]["mods"] = ["cursed"]
	hits = 0
	for i in 2000:
		if LootRules.roll_fight(c, s, "RS02", ["M06"], rng) != "":
			hits += 1
	check(hits / 2000.0 > 0.25, "проклятая — чаще: %.1f%%" % (hits / 20.0))


func test_story_offer_queue_and_take() -> void:
	var c := content()
	var s := _shore()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	check(str(c.missions["SH28"].get("memory", "")) == "boss", "ключевая миссия обещает Воспоминание")
	var p1 := LootRules.offer(c, s, "SH28", "", rng)
	eq(str(p1["tier"]), "boss", "по миссии — всегда:")
	var p2 := LootRules.offer(c, s, "RS02", "weak", rng)
	eq(LootRules.queue(s).size(), 2, "выборы ждут в очереди:")
	eq(LootRules.pending(s)["mission"], "SH28", "первым — первый:")
	eq(LootRules.offer(c, s, "RS01", "", rng), {}, "без выпадения и без memory — ничего:")
	var pick := str(p1["options"][1])
	LootRules.take(c, s, pick)
	check(s.owns(pick), "карта взята")
	for other: String in p1["options"]:
		if other != pick:
			check(not s.owns(other), "остальные рассыпались")
	eq(LootRules.pending(s)["mission"], "RS02", "следующий выбор:")
	var sh := int(s.resources["shards"])
	LootRules.take(c, s, "")
	check(LootRules.pending(s).is_empty(), "распылили — очередь пуста")
	eq(int(s.resources["shards"]), sh + int(c.loot.get("dust", 5)), "распылить — +5 осколков:")
	check(p2.size() > 0, "второй выбор был")
	var s2 := RunState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check(LootRules.pending(s2).is_empty(), "сохранение без хвостов")
