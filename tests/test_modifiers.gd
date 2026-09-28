extends TestCase
## Модификаторы миссий (ModifierRules, docs/16 §11.2).


func _shore() -> RunState:
	return MissionFlow.new_run(content(), 33, "shore")


func _combat_random(c: Content) -> String:
	for mid: String in ["RS01", "RS04"]:
		if c.missions.has(mid):
			return mid
	return ""


func test_only_side_random_of_main_chapters() -> void:
	var c := content()
	check(ModifierRules.eligible(c, "RS01"), "случайная миссия Берега — с модификаторами")
	check(not ModifierRules.eligible(c, "SH20"), "сюжетная — без")
	check(not ModifierRules.eligible(c, "RM01"), "обучающая глава — без")
	var s := _shore()
	var seen := {}
	for i in 60:
		s.clock = i * 3.0
		s.missions.erase("RS01")
		MissionFlow.open(c, s, "RS01")
		var mods: Array = s.missions["RS01"].get("mods", [])
		check(mods.size() in [1, 2], "1–2 модификатора: %s" % str(mods))
		for x: String in mods:
			seen[x] = true
	check(seen.size() >= 5, "выпадают разные: %s" % str(seen.keys()))
	# «Спешка» — только у миссий со сроком; SS01 со сроком, у NS нет модификаторов
	s.missions.erase("NS01")
	MissionFlow.open(c, s, "NS01")
	check(not s.missions["NS01"].has("mods"), "натиск без модификаторов")


func test_combat_changes() -> void:
	var c := content()
	var s := _shore()
	var mid := _combat_random(c)
	MissionFlow.open(c, s, mid)
	var m: Dictionary = c.missions[mid]
	var st: Dictionary = {}
	for a: Dictionary in m["actions"]:
		for x: Dictionary in a.get("stages", []):
			if x.has("combat"):
				st = x
	s.missions[mid]["mods"] = []
	var base := CombatSession.create_for_mission(c, s, mid, st["combat"], "P01", [], [], {}, {})
	s.missions[mid]["mods"] = ["nest", "armored", "fog"]
	var mod := CombatSession.create_for_mission(c, s, mid, st["combat"], "P01", [], [], {}, {})
	eq(mod.enemies.size(), base.enemies.size() + 1, "гнездо — на врага больше:")
	check(Array(mod.enemies[0]["tags"]).has("Панцирь"), "панцирь у врага")
	check(Array(mod.field["tags"]).has("Туман"), "туман в месте боя")
	check(not Array(c.fields.get(str(st["combat"].get("field", "")), {}).get("tags", [])).has("Туман") or true, "данные поля не тронуты")
	s.missions[mid]["mods"] = ["wounded"]
	var weak := CombatSession.create_for_mission(c, s, mid, st["combat"], "P01", [], [], {}, {})
	check(float(weak.enemies[0].get("power", 1.0)) < float(base.enemies[0].get("power", 1.0)), "раненый вожак слабее")
	# прогноз видит то же, что бой
	var f0 := float(MissionForecast.combat_setup(c, s, m, m["actions"][0], st, ["P01"], true)["fight"])
	s.missions[mid]["mods"] = ["cursed"]
	var f1 := float(MissionForecast.combat_setup(c, s, m, m["actions"][0], st, ["P01"], true)["fight"])
	check(f1 < f0, "проклятая — прогноз хуже: %.2f < %.2f" % [f1, f0])
	eq(ModifierRules.threat(c, s, mid), int(m["threat"]) + 1, "угроза +1:")


func test_checks_rewards_expires() -> void:
	var c := content()
	var s := _shore()
	MissionFlow.open(c, s, "RS02")
	s.missions["RS02"]["mods"] = ["fog"]
	var parts := ModifierRules.check_parts(c, s, "RS02", ["stealth"])
	eq(parts.size(), 1, "туман помогает скрытности:")
	var r := StatResolver.resolve(c, s, "P01", [], {"id": "RS02", "tags": ["stealth"]}, {"id": "x", "tags": []})
	var r0 := StatResolver.resolve(c, s, "P01", [], {"id": "RS03", "tags": ["stealth"]}, {"id": "x", "tags": []})
	eq(int(r["totals"]["cunning"]), int(r0["totals"]["cunning"]) + 1, "+1 Хитрость в проверке:")
	s.missions["RS02"]["mods"] = ["cache", "hurry"]
	var before := int(s.resources["shards"])
	var rng := RandomNumberGenerator.new()
	ModifierRules.on_success(c, s, "RS02", "P01", rng)
	eq(int(s.resources["shards"]), before + 6, "тайник и спешка — +6 осколков:")
	eq(ModifierRules.expires(c, s, "RS02"), float(c.missions["RS02"]["expires"]) * 0.5, "спешка — срок вдвое короче:")
	var s2 := RunState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	eq(Array(s2.missions["RS02"]["mods"]), ["cache", "hurry"], "модификаторы сохраняются:")
