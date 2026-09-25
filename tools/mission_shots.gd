extends Node
## Автоснимки режима миссий (docs/15): Godot --path . -- --mshots=<папка>
## Меню → карта с картами миссий → брифинг → отряд в пути → прибытие → отчёт → вторая миссия с боем → просмотр боя.

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


func _run() -> void:
	SettingsService.values["roll_speed"] = 0.0
	await _wait(0.6)
	await _shot("m01_menu")
	GameState.new_mission_run(4242)
	get_tree().change_scene_to_file("res://scenes/missions/mission_game.tscn")
	await _wait(1.2)
	await _shot("m02_map")
	var game := get_tree().current_scene
	game.call("_open_mission", "MS02")
	await _wait(0.8)
	await _shot("m04_brief_ms02")
	_window().call("_launch")
	await _wait(2.5)
	await _shot("m05_travel")
	await _wait(1.5)
	await _shot("m05b_travel")
	await _wait(3.5)
	await _shot("m06_arrived_map")
	game.call("_open_mission", "MS02")
	await _wait(0.8)
	await _shot("m07_arrival")
	_window().call("_choose", "MS02_watch")
	await _wait(0.8)
	await _shot("m08_report")
	_window().close()
	# вторая миссия: Санни отдыхает — подождём
	GameState.state.rest_until.clear()
	GameState.missions_changed.emit()
	if not GameState.state.missions.has("MS03"):
		GameState.state.missions["MS03"] = {"status": "open", "attempts": 0}
	GameState.missions_changed.emit()
	await _wait(0.8)
	await _shot("m08b_map_ms03")
	game.call("_open_mission", "MS03")
	await _wait(0.8)
	await _shot("m09_brief_ms03")
	_window().call("_launch")
	GameState.mission_tick(20.0)
	await _wait(0.6)
	game.call("_open_mission", "MS03")
	await _wait(0.8)
	await _shot("m10_arrival_ms03")
	_window().call("_choose", "MS03_fight")
	await _wait(0.8)
	await _shot("m11_report_ms03")
	var rep: Dictionary = _window().report
	if not Array(rep.get("combats", [])).is_empty():
		game.call("_watch_combat", rep["combats"][0]["setup"])
		await _wait(4.5)
		await _shot("m12_replay")
		await _wait(6.0)
		await _shot("m13_replay_later")
	get_tree().quit()
