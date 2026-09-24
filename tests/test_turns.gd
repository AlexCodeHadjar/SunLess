extends TestCase
## Разрешение хода, продвижение сюжета, смерть, износ, сохранение.


func _run() -> Array:
	var c := content()
	var s := EventFlow.new_run(c, 42)
	var rng := RandomNumberGenerator.new()
	rng.seed = s.rng_seed
	rng.state = s.rng_state
	EventFlow.use_initiator(c, s, "I01", rng)
	s.rng_state = rng.state
	return [c, s]


func _draft(cid: String = "P01", enh: Array = []) -> Dictionary:
	return {"character": cid, "enhancements": enh}


func test_initiator_spawns_event_without_time() -> void:
	var p := _run()
	var s: RunState = p[1]
	check(s.is_event_active("E01"), "E01 на карте")
	check(not s.owns("I01"), "инициатор исчез")
	eq(s.week, 1, "время не пошло:")


func test_story_option_advances() -> void:
	var p := _run()
	var c: Content = p[0]
	var s: RunState = p[1]
	s.characters["P01"]["perm"]["will"] = 5
	var r := TurnResolver.resolve(c, s, "E01", "E01_2", _draft())
	check(r["ok"], "ход разрешён")
	var ns: RunState = r["state"]
	check(r["result"]["success"], "100% — успех")
	check(not ns.is_event_active("E01"), "E01 закрыто")
	check(ns.is_event_active("E02") or ns.pending_story.get("event_id", "") == "E02", "E02 появилось или в пути")
	eq(ns.week, 2, "неделя +1:")
	check(s.is_event_active("E01"), "исходное состояние не изменено (транзакция)")


func test_empty_map_forces_story() -> void:
	# Если на карте пусто, ожидающее сюжетное событие появляется сразу.
	var p := _run()
	var c: Content = p[0]
	var s: RunState = p[1]
	s.characters["P01"]["perm"]["will"] = 5
	for seed_value in 30:
		s.rng_seed = seed_value
		s.rng_state = seed_value * 7919
		var ns: RunState = TurnResolver.resolve(c, s, "E01", "E01_2", _draft())["state"]
		check(not ns.active_event_ids().is_empty(), "карта не должна остаться пустой (seed %d)" % seed_value)


func test_non_story_success_keeps_event() -> void:
	var p := _run()
	var c: Content = p[0]
	var s: RunState = p[1]
	s.characters["P01"]["perm"]["cunning"] = 5
	var r := TurnResolver.resolve(c, s, "E01", "E01_3", _draft())
	var ns: RunState = r["state"]
	check(ns.is_event_active("E01"), "событие осталось")
	check(ns.is_option_done("E01", "E01_3"), "вариант выполнен")
	check(ns.owns("K01"), "получено знание K01")
	var again := TurnResolver.can_resolve(c, ns, "E01", "E01_3", _draft())
	check(again != "", "выполненный вариант нельзя повторить")


func test_failure_gives_trauma_and_keeps_event() -> void:
	var p := _run()
	var c: Content = p[0]
	var s: RunState = p[1]
	s.characters["P01"]["perm"]["will"] = -20
	var r := TurnResolver.resolve(c, s, "E01", "E01_2", _draft())
	var ns: RunState = r["state"]
	check(not r["result"]["success"], "шанс 0 — провал")
	eq(r["result"]["chance"], 0, "шанс:")
	eq(Array(ns.characters["P01"]["traumas"]).size(), 1, "одна травма:")
	eq(c.traumas[ns.characters["P01"]["traumas"][0]]["category"], "mental", "пул E01 — ментальный:")
	check(ns.is_event_active("E01"), "событие осталось на карте")


func test_sunny_death_ends_run() -> void:
	var p := _run()
	var c: Content = p[0]
	var s: RunState = p[1]
	s.characters["P01"]["perm"]["will"] = -20
	s.characters["P01"]["traumas"] = ["T01", "T02", "T03", "T04", "T05", "T06", "T08"]
	var r := TurnResolver.resolve(c, s, "E01", "E01_2", _draft())
	var ns: RunState = r["state"]
	eq(r["result"]["death"].get("chance", -1), 100, "8 травм — 100%:")
	check(ns.game_over, "смерть Санни — конец прохождения")
	eq(ns.week, 1, "после смерти неделя не идёт:")


func test_ward_halves_death() -> void:
	var p := _run()
	var c: Content = p[0]
	var s: RunState = p[1]
	s.characters["P01"]["perm"]["will"] = -20
	s.characters["P01"]["traumas"] = ["T01", "T02"]
	var r := TurnResolver.resolve(c, s, "E01", "E01_2", _draft(), {"ward": true})
	eq(r["result"]["death"].get("chance", -1), 7, "15% / 2 = 7:")
	eq(int(r["state"].resources["mana"]), 6, "Оберег стоит 4 маны:")


func test_wear_after_use() -> void:
	var p := _run()
	var c: Content = p[0]
	var s: RunState = p[1]
	EffectApplier.add_card(c, s, "U01")
	s.characters["P01"]["perm"]["will"] = 5
	var r := TurnResolver.resolve(c, s, "E01", "E01_2", _draft("P01", ["U01"]))
	var ns: RunState = r["state"]
	var w: Dictionary = r["result"]["wear"][0]
	if w["broken"]:
		check(not ns.owns("U01"), "сломанная карта уничтожена")
	else:
		eq(int(ns.wear["U01"]), 6, "износ 1% → 6%:")


func test_concentration_costs_mana() -> void:
	var p := _run()
	var c: Content = p[0]
	var s: RunState = p[1]
	var prev := TurnResolver.preview(c, s, "E01", _draft(), {"will": 1})
	eq(prev[1]["chance"], 100, "Воля 5+1 = требование 6:")
	var r := TurnResolver.resolve(c, s, "E01", "E01_2", _draft(), {"concentration": {"will": 1}})
	eq(int(r["state"].resources["mana"]) - int(r["result"]["loot"].get("value", 0) if r["result"]["loot"].get("resource", "") == "mana" else 0), 7, "3 маны за Концентрацию:")


func test_gate_condition_blocks() -> void:
	var c := content()
	var s := EventFlow.new_run(c, 5)
	s.events["E05"] = {"status": "active", "done_options": [], "spawned_week": 1}
	var why := TurnResolver.can_resolve(c, s, "E05", "E05_3", _draft())
	check(why.contains("Ауро"), "без Ауро вариант заблокирован: %s" % why)


func test_e09_removes_auro() -> void:
	var c := content()
	var s := EventFlow.new_run(c, 5)
	EffectApplier.add_card(c, s, "P08")
	var rng := RandomNumberGenerator.new()
	EventFlow.spawn(c, s, "E09", rng)
	check(not s.owns("P08"), "Ауро покидает коллекцию")


func test_e11_finishes_slice() -> void:
	var c := content()
	var s := EventFlow.new_run(c, 5)
	s.characters["P01"]["traumas"] = ["T02", "T05"]
	EffectApplier.add_card(c, s, "P09")
	s.events["E11"] = {"status": "active", "done_options": [], "spawned_week": 1}
	var r := TurnResolver.resolve(c, s, "E11", "E11_1", _draft())
	var ns: RunState = r["state"]
	check(not ns.demo_complete, "после Кошмара игра продолжается")
	eq(ns.chapter, "academy", "свободный режим — Академия:")
	eq(ns.node, "medbay", "Санни просыпается в медкрыле:")
	check(ns.is_event_active("E12"), "первый якорь главы появился")
	eq(ns.characters["P01"]["stage"], "sleeper", "стадия:")
	eq(Array(ns.characters["P01"]["traumas"]).size(), 0, "травмы сняты:")
	check(Array(ns.characters["P01"]["abilities"]).has("A01"), "Контроль Теней получен")
	check(ns.owns("U06"), "Саван Кукловода получен")
	check(not ns.owns("P09"), "временные спутники ушли")
	eq(int(ns.characters["P01"]["perm"]["will"]), 1, "+1 Воля навсегда:")


func test_save_roundtrip() -> void:
	var p := _run()
	var s: RunState = p[1]
	s.flags["x"] = true
	s.wear["U01"] = 11
	s.temp_effects.append({"stat": "will", "value": 1, "tags": [], "event_id": "", "option_id": "", "remaining": 1, "label": "t"})
	s.rng_state = 9007199254740993  # больше 2^53 — проверка точности
	var text := JSON.stringify(s.to_dict())
	var back := RunState.from_dict(JSON.parse_string(text))
	eq(JSON.stringify(back.to_dict()), text, "сохранение → загрузка:")
	eq(back.rng_state, 9007199254740993, "RNG без потери точности:")
