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
	get_tree().quit()
