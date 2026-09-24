extends Node
## Автоснимки для проверки интерфейса без ручной игры.
## Запуск: Godot --path . -- --shots=<папка>
## Проходит сценарий: меню → карта → инициатор → планшет → результат, сохраняет PNG и выходит.

var out_dir := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			out_dir = a.substr(8)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("[shots] saved ", name)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _run() -> void:
	SettingsService.values["tutorial"] = true
	SettingsService.values["roll_speed"] = 0.0
	await _wait(0.5)
	await _shot("01_menu")
	GameState.new_run(12345)
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")
	await _wait(0.8)
	await _shot("02_map_start")
	GameState.use_initiator("I01")
	await _wait(0.8)
	await _shot("03_map_e01")
	var game := get_tree().current_scene
	for m in game.get("_markers").get_children():
		if m is CardView:
			m.call("_on_hover", true)
	await _wait(1.0)
	await _shot("03b_hover_smoke")
	for m in game.get("_markers").get_children():
		if m is CardView:
			m.call("_on_hover", false)
	# время суток по неделям: рассвет, день, сумерки, снова ночь
	for wk: int in [2, 3, 4]:
		GameState.state.week = wk
		EventBus.state_changed.emit()
		await _wait(3.6)
		await _shot("03c_map_week%d_%s" % [wk, MapBackdrop.tod_name(wk)])
	GameState.state.week = 1
	EventBus.state_changed.emit()
	await _wait(3.6)
	game.call("_open_event", "E01")
	await _wait(2.4)
	await _shot("04_tablet_e01")
	# Продвинемся к E05 со снаряжением, чтобы увидеть веер и арт события
	var s: RunState = GameState.state
	for card: String in ["U01", "U02", "P09", "P08", "K01"]:
		EffectApplier.add_card(ContentDB.data, s, card)
	s.characters["P01"]["traumas"] = ["T02", "T05"]
	s.events["E01"]["status"] = "closed"
	s.events["E05"] = {"status": "active", "done_options": [], "spawned_week": s.week}
	s.wear["U01"] = 16
	EventBus.state_changed.emit()
	game.call("_open_event", "E05")
	GameState.set_executor("E05", "P01")
	GameState.attach("E05", "U01")
	GameState.attach("E05", "U02")
	await _wait(0.6)
	await _shot("05_tablet_e05")
	s.characters["P01"]["perm"]["cunning"] = 5
	GameState.resolve("E05", "E05_1")
	await _wait(0.65)
	await _shot("06a_burn")
	await _wait(1.6)
	await _shot("06_result")
	game.call("_on_nav", "cards")
	await _wait(0.5)
	await _shot("07_cards")
	game.call("_close_overlay")
	game.get("_result").call("_on_continue")
	# --- бой ---
	s = GameState.state
	s.characters["P01"]["traumas"] = []
	s.events["E03"] = {"status": "active", "done_options": [], "spawned_week": s.week}
	EventBus.state_changed.emit()
	game.call("_open_event", "E03")
	GameState.set_executor("E03", "P01")
	GameState.attach("E03", "U01")
	await _wait(0.5)
	await _shot("08_tablet_combat_option")
	game.call("_on_resolve_requested", "E03", "E03_1")
	await _wait(1.2)
	await _shot("09_combat_prep")
	var cs_screen: Node = null
	for ch in game.get_children():
		if ch is CombatScreen:
			cs_screen = ch
	cs_screen.call("_on_action")
	await _wait(2.2)
	await _shot("10a_beams_in_flight")
	await _wait(6.5)
	await _shot("10_combat_round")
	var hand: Array = GameState.combat.hand
	if not hand.is_empty():
		cs_screen.call("_pick_tactic", hand[0])
	await _wait(0.6)
	await _shot("10b_tactic_diff")
	await _wait(1.5)
	await _shot("10c_tactic_selected")
	cs_screen.call("_on_action")
	await _wait(1.3)
	await _shot("11_combat_round_result")
	cs_screen.get("_info").call("show_tag", "Мягкое тело", Vector2(900, 420), "В этом бою: есть у врага")
	await _wait(0.3)
	await _shot("12_tag_info")
	cs_screen.get("_info").visible = false
	cs_screen.set("_graph_forced", true)
	cs_screen.get("_graph").call("show_for", "Тень")
	await _wait(0.4)
	await _shot("13_link_graph")
	cs_screen.set("_graph_forced", false)
	cs_screen.get("_graph").visible = false
	# витрина живого облика карт: враги по тегам, герой с травмами
	var shelf := Control.new()
	shelf.top_level = true
	shelf.z_index = 100
	shelf.size = Vector2(1920, 1080)
	var bg := ColorRect.new()
	bg.color = Color("#0A0B10")
	bg.size = shelf.size
	shelf.add_child(bg)
	get_tree().root.add_child(shelf)
	s.characters["P01"]["traumas"] = ["T01", "T06"]
	var ids := ["M01", "M06", "M08", "M16", "M18", "M25", "M26", "M37", "M15", "M19", "M38", "P01"]
	for i in ids.size():
		var cv := CardView.make(ids[i], Vector2(190, 326), false)
		cv.position = Vector2(60 + (i % 6) * 305, 80 + int(i / 6) * 490)
		shelf.add_child(cv)
		var cap := Label.new()
		cap.text = ", ".join(CardAura.motifs_for(cv.call("_combat_tags"), s.characters["P01"]["traumas"] if ids[i] == "P01" else []))
		cap.position = cv.position + Vector2(-20, 350)
		shelf.add_child(cap)
	await _wait(2.5)
	await _shot("14_card_auras")
	get_tree().quit()
