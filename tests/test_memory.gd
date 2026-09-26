extends TestCase
## Особые навыки карт (docs/16 §9д): срабатывают сами по условию на тегах; приёмов в бою больше нет.

const LARVAE := {"enemies": ["M01", "M01"], "field": "F_05"}
const SCAV := {"enemies": ["M03"], "field": "F_08"}
const CLIFF := {"enemies": ["M03"], "field": "F_03"}


func _session(c: Content, spec: Dictionary, enh: Array, hero: String = "P01", support: Array = []) -> CombatSession:
	var s := MissionFlow.new_run(c, 5)
	s.chapter = "shore"
	for e: String in enh + support:
		EffectApplier.add_card(c, s, e)
	if not s.owns(hero):
		EffectApplier.add_card(c, s, hero)
	var cs := CombatSession.create_for_mission(c, s, "T", spec, hero, enh, support, {"id": "T", "tags": ["combat"]}, {"id": "T_a", "tags": []})
	cs.round_no = 1
	return cs


func _fired(f: Dictionary, card: String) -> bool:
	return Array(f["fired"]).any(func(m: Dictionary) -> bool: return m["card"] == card)


func test_no_tactics_left() -> void:
	var c := content()
	var cs := _session(c, SCAV, [])
	check(not ("tactics" in c), "приёмов в данных нет")
	cs.auto_play()
	check(cs.finished, "автобой идёт без приёмов")


func test_armor_and_once() -> void:
	var c := content()
	var cs := _session(c, SCAV, ["U07"])
	var f := MemoryRules.fire(cs, "round", true)
	check(_fired(f, "U07"), "Лазурный Клинок срабатывает против панциря")
	check(Array(f["effect"].get("cancel_enemy_tags", [])).has("Панцирь"), "броня врага не в счёт")
	check(not _fired(MemoryRules.fire(cs, "round", true), "U07"), "раз за бой — второй раз нет")
	check(WearRules.current(cs.state, "U07") > WearRules.START, "срабатывание изнашивает карту")
	var cs2 := _session(c, LARVAE, ["U07"])
	check(not _fired(MemoryRules.fire(cs2, "round", false), "U07"), "против личинок (без брони) — нет")


func test_lose_phase_guards() -> void:
	var c := content()
	var cs := _session(c, LARVAE, ["U06"])
	var f := MemoryRules.fire(cs, "lose", false)
	check(_fired(f, "U06") and int(f["effect"]["guard"]) == 100, "Саван отводит удар шипов")
	var cs2 := _session(c, CLIFF, ["U11"])
	check(_fired(MemoryRules.fire(cs2, "lose", false), "U11"), "Верёвка страхует на высоте")
	var cs3 := _session(c, SCAV, ["U16"])
	check(_fired(MemoryRules.fire(cs3, "lose", true), "U16") and _fired(MemoryRules.fire(cs3, "lose", true), "U16"), "Доспехи Легиона — каждый раз")


func test_echo_guard() -> void:
	var c := content()
	var cs := _session(c, SCAV, ["U12"])
	check(not _fired(MemoryRules.fire(cs, "lose", false), "U12"), "Эхо ждёт, пока герой цел")
	cs.state.character("P01")["traumas"] = ["T02", "T03"]
	check(bool(MemoryRules.fire(cs, "lose", false)["effect"].get("echo_guard", false)), "при двух травмах Эхо принимает удар")
	var rec := {"traumas": []}
	var before: int = Array(cs.state.character("P01")["traumas"]).size()
	cs._lose_round({}, rec)
	check(not cs.enh.has("U12") and Array(cs.state.character("P01")["traumas"]).size() == before, "Эхо рассыпалось, травмы нет")


func test_abilities() -> void:
	var c := content()
	var cs := _session(c, SCAV, [], "P02")
	cs.state.character("P02")["abilities"] = ["A03"]
	cs.momentum = "enemy"
	var f := MemoryRules.fire(cs, "round", false)
	check(_fired(f, "A03") and Array(f["effect"].get("self_tags", [])).has("Боль"), "после проигранного раунда — вспышка пламени ценой Боли")
	# Видение Касси работает из поддержки
	var cs2 := _session(c, SCAV, [], "P01", ["P03"])
	cs2.state.character("P03")["abilities"] = ["A04"]
	check(_fired(MemoryRules.fire(cs2, "round", false), "A04"), "Видение Касси из поддержки")


func test_replay_matches_and_log() -> void:
	var c := content()
	var cs := _session(c, SCAV, ["U07", "K07"])
	cs.round_no = 0
	cs.begin_round()
	var pre := MemoryRules.fire(cs, "round", false)
	var rec := cs.play_round()
	eq(Array(rec["memories"]).size(), Array(pre["fired"]).size(), "показ совпадает с расчётом:")
	check(cs.entries.any(func(e: Dictionary) -> bool: return e["kind"] == "memory"), "срабатывание записано в итог")
