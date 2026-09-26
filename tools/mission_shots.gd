extends Node
## Автоснимки режима миссий (docs/15): Godot --path . -- --mshots=<папка>
## Меню → карта с картами миссий и магазином → покупка героя → брифинг → два отряда в пути →
## прибытие → отчёт → вторая миссия с боем → просмотр боя → середина главы → конец главы → Академия.

var out_dir := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mshots="):
			out_dir = a.substr(9)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("[mshots] saved ", name)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _window() -> MissionWindow:
	for ch in get_tree().current_scene.get_children():
		if ch is MissionWindow:
			return ch
	return null


func _shop() -> ShopWindow:
	for ch in get_tree().current_scene.get_children():
		if ch is ShopWindow:
			return ch
	return null


func _run() -> void:
	SettingsService.values["roll_speed"] = 0.0
	await _wait(0.6)
	await _shot("m01_menu")
	GameState.new_mission_run(4242)
	get_tree().change_scene_to_file("res://scenes/missions/mission_game.tscn")
	await _wait(1.2)
	await _shot("m02_map")
	var game := get_tree().current_scene
	# небо: ночь → день по часам (перетекание 4 с)
	GameState.state.clock = Atmosphere.DAY_CYCLE * 0.55
	await _wait(2.0)
	await _shot("m02c_sky_dawn_fade")
	await _wait(3.0)
	await _shot("m02d_sky_day")
	GameState.state.clock = 0.0
	game.call("_open_mission", "MS01")
	await _wait(0.8)
	await _shot("m02b_brief_ms01")
	_window().close()
	# сразу к каравану: MS01 считаем пройденной
	GameState.state.missions["MS01"] = {"status": "done", "attempts": 0}
	MissionFlow.open(ContentDB.data, GameState.state, "MS02")
	GameState.missions_changed.emit()
	await _wait(0.4)
	# магазин: на стартовые осколки — первый попутчик
	game.call("_open_shop", "nightmare_trader")
	await _wait(0.8)
	await _shot("m03_shop")
	var hero := ""
	for it: Dictionary in ShopRules.ensure(ContentDB.data, GameState.state, "nightmare_trader")["items"]:
		if ContentDB.data.card_kind(it["card"]) == "character" and int(it["price"]) <= int(GameState.state.resources["shards"]):
			hero = it["card"]
	if hero != "":
		_shop().call("_buy", hero)
		await _wait(0.8)
		await _shot("m03b_shop_bought")
	# услуги торговца (Ф10): травма у Санни — для снимка, потом убираем
	GameState.state.character("P01")["traumas"] = ["T03", "T01"]
	_shop().set("_tab", "services")
	_shop().call("_refresh")
	await _wait(0.6)
	await _shot("m03c_services")
	GameState.state.character("P01")["traumas"] = []
	_shop().close()
	await _wait(0.6)
	game.call("_open_mission", "MS02")
	await _wait(0.8)
	await _shot("m04_brief_ms02")
	_window().call("_launch")
	# второй отряд одновременно: MS03 откроем заранее, туда — купленный герой
	if hero != "":
		GameState.state.missions["MS03"] = {"status": "open", "attempts": 0}
		GameState.missions_changed.emit()
		await _wait(0.3)
		game.call("_on_hero_dropped", "MS03", hero)
		await _wait(0.8)
		await _shot("m04b_brief_ms03_dropped")
		_window().call("_launch")
	await _wait(2.5)
	await _shot("m05_two_squads")
	await _wait(3.5)
	await _shot("m06_arrived_map")
	game.call("_open_mission", "MS02")
	await _wait(0.8)
	await _shot("m07_arrival")
	_window().call("_choose", "MS02_watch")
	await _wait(0.8)
	await _shot("m08_report")
	_window().close()
	await _wait(0.4)
	if hero == "":
		GameState.state.rest_until.clear()
		if not GameState.state.missions.has("MS03"):
			GameState.state.missions["MS03"] = {"status": "open", "attempts": 0}
		GameState.missions_changed.emit()
		game.call("_open_mission", "MS03")
		await _wait(0.8)
		_window().call("_launch")
	GameState.mission_tick(20.0)
	await _wait(0.6)
	game.call("_open_mission", "MS03")
	await _wait(0.8)
	await _shot("m10_arrival_ms03")
	_window().call("_choose", "MS03_fight")
	await _wait(0.8)
	await _shot("m10b_fork")
	if _window().mode == "fork":
		var r: Dictionary = GameState.resolve_fork(_window().squad_id, "push")
		_window().show_report(r)
		await _wait(0.8)
	await _shot("m11_report_ms03")
	# Ф9: планшет героя — паника и доверие (подсказка доверия открыта)
	var gs := GameState.state
	TrustRules.change(ContentDB.data, gs, "P01", "P03", 4, "успех вместе: «Тропа через перевал»")
	TrustRules.change(ContentDB.data, gs, "P01", "P02", 2, "успех вместе: «Первый бой»")
	TrustRules.change(ContentDB.data, gs, "P01", "P10", -3, "бегство с этапа")
	PanicRules.add(ContentDB.data, gs, "P01", 70, "снимок")
	gs.character("P01")["tag_xp"] = {"Скрытность": 4.0, "Чутьё": 1.5, "Импровизация": 6.0, "Раб": 6.0}
	gs.character("P01")["growth"] = {"Импровизация": "evo", "Раб": "mut"}
	var ins := CardInspector.open_for(game, "P01")
	await _wait(0.8)
	ins.call("_show_hint", SquadLifeUI.trust_hint("P01"))
	await _wait(0.4)
	await _shot("m11b_trust_panic")
	ins.call("_show_hint", ins.call("_growth_hint", "Скрытность"))
	await _wait(0.4)
	await _shot("m11c_growth")
	ins.call("_close")
	await _wait(0.3)
	# лагерь (Ф10): Санни на койке с лёгкой травмой
	gs.character("P01")["traumas"] = ["T02"]
	GameState.camp_put("P01")
	game.call("_on_nav", "camp")
	await _wait(0.8)
	await _shot("m11d_camp")
	for n in game.get_children():
		if n is CampWindow:
			n.close()
	# журнал (Ф11): бестиарий после боя MS03
	game.call("_on_nav", "journal")
	await _wait(0.8)
	await _shot("m11e_bestiary")
	for n in game.get_children():
		if n is JournalWindow:
			n.set("_tab", "rumors")
			n.call("_refresh")
	await _wait(0.4)
	await _shot("m11f_rumors")
	for n in game.get_children():
		if n is JournalWindow:
			n.close()
	GameState.camp_take("P01")
	gs.character("P01")["traumas"] = []
	await _wait(0.3)
	var rep: Dictionary = _window().report
	if not Array(rep.get("combats", [])).is_empty():
		game.call("_watch_combat", rep["combats"][0]["setup"])
		await _wait(4.5)
		await _shot("m12_replay")
		get_tree().current_scene.get_children().filter(func(n: Node) -> bool: return n is CombatScreen).map(func(n: Node) -> void: n.queue_free())
		game.set("_combat_open", false)
	await _wait(0.5)
	if is_instance_valid(_window()):
		_window().close()
	# середина главы: несколько мест, побочная и случайная миссии веером
	var st := GameState.state
	st.squads.clear()
	st.rest_until.clear()
	for mid: String in ["MS01", "MS02", "MS03", "MS04"]:
		st.missions[mid] = {"status": "done", "attempts": 0}
	for mid: String in ["MS05", "RM01", "SM01", "RM04"]:
		MissionFlow.open(ContentDB.data, st, mid)
	GameState.missions_changed.emit()
	await _wait(5.0)
	await _shot("m14_mid_chapter")
	MissionFlow.open(ContentDB.data, st, "MS09")
	GameState.missions_changed.emit()
	await _wait(5.0)
	await _shot("m14b_eclipse")
	st.missions.erase("MS09")
	GameState.missions_changed.emit()
	st.demo_complete = true
	st.flags["next_chapter"] = "academy"
	await _wait(1.0)
	await _shot("m15_chapter_end")
	# Академия: «Дальше» на экране конца главы
	GameState.next_chapter()
	get_tree().reload_current_scene()
	await _wait(1.5)
	await _shot("m16_academy_map")
	for mid: String in ["MA12", "MA13"]:
		GameState.state.missions[mid] = {"status": "done", "attempts": 0}
	for mid: String in ["MA14", "MA15", "MA16", "SA01", "RA02", "RA03"]:
		MissionFlow.open(ContentDB.data, GameState.state, mid)
	GameState.missions_changed.emit()
	await _wait(1.0)
	await _shot("m17_academy_parallel")
	get_tree().current_scene.call("_open_mission", "MA16")
	await _wait(0.8)
	await _shot("m18_brief_ma16")
	get_tree().current_scene.get_children().filter(func(n: Node) -> bool: return n is MissionWindow).map(func(n: Node) -> void: n.close())
	# Забытый Берег (Ф13): после Зимнего солнцестояния — Санни один, ночь, потом шторм и день
	var sa := GameState.state
	sa.demo_complete = true
	sa.flags["next_chapter"] = "shore"
	for cid: String in ["P02", "P03", "P04"]:
		sa.collection.erase(cid)
	GameState.next_chapter()
	get_tree().reload_current_scene()
	await _wait(1.5)
	sa = GameState.state
	sa.clock = 10.0
	GameState.missions_changed.emit()
	await _wait(5.0)
	await _shot("m19_shore_night")
	for mid: String in ["SH19", "SH20", "SH21", "SH22", "SH23", "SH24", "SH25", "SH26"]:
		sa.missions[mid] = {"status": "done", "attempts": 0}
	for cid: String in ["P02", "P03"]:
		EffectApplier.add_card(ContentDB.data, sa, cid)
	MissionFlow.open(ContentDB.data, sa, "SH27")
	MissionFlow.open(ContentDB.data, sa, "RS01")
	GameState.missions_changed.emit()
	await _wait(5.0)
	await _shot("m20_shore_storm")
	get_tree().current_scene.call("_open_mission", "SH27")
	await _wait(0.8)
	await _shot("m21_brief_sh27")
	get_tree().quit()
