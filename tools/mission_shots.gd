extends Node
## Автоснимки режима миссий (docs/15): Godot --path . -- --mshots=<папка>
## Меню → карта с картами миссий и магазином → покупка героя → брифинг → два отряда в пути →
## прибытие → отчёт → вторая миссия с боем → просмотр боя → середина главы → конец главы → Академия.

var out_dir := ""
var from_ch4 := false   # --mshots-from=ch4: снять только Главу 4
var labels_shots := false   # --mshots-from=labels: подписи мест в разных стилях (коллаж для выбора)
var events_shots := false   # --mshots-from=events: места и следы событий Берега, картинки пака Главы 4
var figure_shots := false   # --mshots-from=figure: фигура (docs/18) — поле, перетаскивание, сцена лагеря, разрыв карты
var start_shots := false    # --mshots-from=start: экран «разбитое стекло» и старт с Берега
var fog_shots := false      # --mshots-from=fog: туман и «воздух» (буря, дымка) — проверка резких краёв
var boss_shots := false     # --mshots-from=bosses: бродячие боссы на картах глав (docs/22)
var live_chatter := false   # --mshots-from=live: мысли героев вживую (с подсказками, обычные сроки)
var mods_shots := false     # --mshots-from=mods: значки модификаторов над ромбами
var resize_shots := false   # --mshots-from=resize: история перед главой при смене размера окна
var quests_shots := false   # --mshots-from=quests: задания справа, показ места (docs/20)
var perf_run := false   # --mshots-from=perf: замер кадра и тяжёлых функций экрана карты (perf.txt в папке снимков)
var chatter_shots := false   # --mshots-from=chatter: мысли и реплики героев над картами, полдень, шаг к событию
var icons_shots := false   # --mshots-from=icons: события ромбами — поле, наведение (круг загрузки), карта события, фигура рядом
var timeline := false   # --mshots-from=timeline: карта по дням во всех главах (для коллажей, tools/map_collage.py)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mshots="):
			out_dir = a.substr(9)
		if a == "--mshots-from=ch4":
			from_ch4 = true
		if a == "--mshots-from=timeline":
			timeline = true
		if a == "--mshots-from=figure":
			figure_shots = true
		if a == "--mshots-from=events":
			events_shots = true
		if a == "--mshots-from=labels":
			labels_shots = true
		if a == "--mshots-from=icons":
			icons_shots = true
		if a == "--mshots-from=chatter":
			chatter_shots = true
		if a == "--mshots-from=perf":
			perf_run = true
		if a == "--mshots-from=quests":
			quests_shots = true
		if a == "--mshots-from=mods":
			mods_shots = true
		if a == "--mshots-from=live":
			live_chatter = true
		if a == "--mshots-from=bosses":
			boss_shots = true
		if a == "--mshots-from=fog":
			fog_shots = true
		if a == "--mshots-from=start":
			start_shots = true
		if a == "--mshots-from=resize":
			resize_shots = true
		if a == "--nohints":
			# чистые кадры: подсказки выключены только на этот запуск (настройки игрока не сохраняются)
			SettingsService.values["tutorial"] = false
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


func _story() -> StoryScreen:
	for ch in get_tree().current_scene.get_children():
		if ch is StoryScreen:
			return ch
	return null


## Убирает сюжетное окно, как будто его досмотрели.
func _dismiss_story() -> void:
	var sc := _story()
	if sc:
		sc.queue_free()
	StoryRules.mark_seen(GameState.state, GameState.state.chapter)
	GameState.story_open = false


func _run() -> void:
	SettingsService.values["roll_speed"] = 0.0
	if from_ch4:
		await _ch4(true)
		get_tree().quit()
		return
	if timeline:
		await _timeline()
		get_tree().quit()
		return
	if figure_shots:
		await _figure()
		get_tree().quit()
		return
	if events_shots:
		await _events()
		get_tree().quit()
		return
	if labels_shots:
		await _labels()
		get_tree().quit()
		return
	if icons_shots:
		await _icons()
		get_tree().quit()
		return
	if chatter_shots:
		await _chatter()
		get_tree().quit()
		return
	if perf_run:
		await _perf()
		get_tree().quit()
		return
	if quests_shots:
		await _quests()
		get_tree().quit()
		return
	if mods_shots:
		await _mods()
		get_tree().quit()
		return
	if live_chatter:
		await _chatter_live()
		get_tree().quit()
		return
	if boss_shots:
		await _bosses()
		get_tree().quit()
		return
	if fog_shots:
		await _fog_check()
		get_tree().quit()
		return
	if start_shots:
		await _start_check()
		get_tree().quit()
		return
	if resize_shots:
		await _resize()
		get_tree().quit()
		return
	await _wait(0.6)
	await _shot("m01_menu")
	GameState.new_mission_run(4242)
	get_tree().change_scene_to_file("res://scenes/missions/mission_game.tscn")
	# сюжетное окно вступления: текст проявляется, потом показан целиком
	await _wait(3.2)
	await _shot("m00_story_intro")
	var story := _story()
	if story:
		story.call("_reveal_all")
		await _wait(0.5)
		await _shot("m00b_story_full")
	_dismiss_story()
	await _wait(1.2)
	await _shot("m02_map")
	var game := get_tree().current_scene
	# небо: ночь → день — следующая фаза недели (перетекание 4 с)
	GameState.state.day = 3
	await _wait(2.0)
	await _shot("m02c_sky_dawn_fade")
	await _wait(3.0)
	await _shot("m02d_sky_day")
	GameState.state.day = 1
	game.call("_open_mission", "MS01")
	await _wait(0.8)
	await _shot("m02b_brief_ms01")
	_window().close()
	# сразу к каравану: MS01 считаем пройденной
	GameState.state.missions["MS01"] = {"status": "done", "attempts": 0}
	MissionFlow.open(ContentDB.data, GameState.state, "MS02")
	GameState.missions_changed.emit()
	await _wait(0.4)
	# магазин (с Академии; в Первом Кошмаре торговца нет): снимок лавки, потом обратно в Кошмар
	GameState.state.chapter = "academy"
	game.call("_open_shop", "academy_store")
	await _wait(0.8)
	await _shot("m03_shop")
	var hero := ""
	for it: Dictionary in ShopRules.ensure(ContentDB.data, GameState.state, "academy_store")["items"]:
		if ContentDB.data.card_kind(it["card"]) == "character" and int(it["price"]) <= int(GameState.state.resources["shards"]):
			hero = it["card"]
	if hero != "":
		_shop().call("_buy", hero)
		await _wait(0.8)
		await _shot("m03b_shop_bought")
	# услуги торговца (Ф10): заточка и починка
	_shop().set("_tab", "services")
	_shop().call("_refresh")
	await _wait(0.6)
	await _shot("m03c_services")
	_shop().close()
	GameState.state.chapter = "nightmare"
	await _wait(0.6)
	game.call("_open_mission", "MS02")
	await _wait(0.8)
	await _shot("m04_brief_ms02")
	_window().call("_show_rumor_hint", "Холод")
	await _wait(0.3)
	await _shot("m04c_rumor_hint")
	_window().call("_hide_rumor_hint")
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
	gs.character("P01")["panic"] = 65   # психика 35 — для снимка
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
	# лагерь (Ф10): Санни на койке — на грани смерти (docs/16 §9е)
	gs.character("P01")["edge"] = true
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
	GameState.missions_changed.emit()
	await _wait(0.6)
	await _shot("m11g_edge_map")
	gs.character("P01")["edge"] = false
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
	# середина главы: сюжет, случайная миссия и миссия-выбор
	var st := GameState.state
	st.squads.clear()
	st.rest_until.clear()
	for mid: String in ["MS01", "MS02", "MS03", "MS04"]:
		st.missions[mid] = {"status": "done", "attempts": 0}
	for mid: String in ["MS05", "RM01", "SM02", "SM03"]:
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
	StoryRules.mark_seen(GameState.state, "academy")
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
	# прорывы Академии (GateRules): сигнал, пролом, рой в корпусе, повреждения и баррикада
	var ga := GameState.state
	get_tree().current_scene.get_children().filter(func(n: Node) -> bool: return n is MissionWindow).map(func(n: Node) -> void: n.close())
	GateRules.raise_signal(ContentDB.data, ga, "B4")
	ga.flags["gates"]["B1"] = {"stage": "open", "open_day": ga.day}
	GateRules.set_site(ga, "dorm", "alarm")
	GateRules.set_site(ga, "yard", "alarm")
	ga.flags["swarms"] = [{"at": "canteen", "from": "dorm", "point": "B1"}]
	GateRules.set_site(ga, "canteen", "alarm")
	GateRules.set_site(ga, "medbay", "burning")
	GateRules.set_site(ga, "arena", "barricaded")
	GateRules.set_site(ga, "lab", "leak")
	MissionFlow.open(ContentDB.data, ga, "BA15", true)
	GameState.missions_changed.emit()
	await _wait(1.5)
	await _shot("m18b_academy_breach")
	GameState.state.flags.erase("swarms")
	GateRules.reset(GameState.state)
	GameState.missions_changed.emit()
	get_tree().current_scene.get_children().filter(func(n: Node) -> bool: return n is MissionWindow).map(func(n: Node) -> void: n.close())
	# Забытый Берег (Ф13): после Зимнего солнцестояния — Санни один, ночь, потом шторм и день
	var sa := GameState.state
	sa.demo_complete = true
	sa.flags["next_chapter"] = "shore"
	for cid: String in ["P02", "P03", "P04"]:
		sa.collection.erase(cid)
	GameState.next_chapter()
	get_tree().reload_current_scene()
	await _wait(3.0)
	await _shot("m19a_story_shore")
	_dismiss_story()
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
	MissionFlow.open(ContentDB.data, sa, "RS01", true)
	GameState.missions_changed.emit()
	await _wait(5.0)
	await _shot("m20_shore_storm")
	get_tree().current_scene.call("_open_mission", "SH27")
	await _wait(0.8)
	await _shot("m21_brief_sh27")
	get_tree().current_scene.get_children().filter(func(n: Node) -> bool: return n is MissionWindow).map(func(n: Node) -> void: n.close())
	await _wait(0.4)
	# колода событий (DeckRules): звено цепочки в брифинге
	MissionFlow.open(ContentDB.data, sa, "SC02", true)
	GameState.missions_changed.emit()
	await _wait(0.5)
	get_tree().current_scene.call("_open_mission", "SC02")
	await _wait(0.8)
	await _shot("m21a_brief_chain")
	get_tree().current_scene.get_children().filter(func(n: Node) -> bool: return n is MissionWindow).map(func(n: Node) -> void: n.close())
	sa.missions.erase("SC02")
	GameState.missions_changed.emit()
	await _wait(0.4)
	# прилив (TideRules): предупреждение → вода → отлив с новыми проходами
	MissionFlow.open(ContentDB.data, sa, "RS02", true)
	MissionFlow.open(ContentDB.data, sa, "SS01", true)
	GameState.missions_changed.emit()
	GameState.mission_events.emit(TideRules.schedule(ContentDB.data, sa, 2, 2, "Шторм гонит воду в лабиринт."))
	await _wait(3.0)
	await _shot("m21b_tide_warn")
	get_tree().current_scene.call("_open_mission", "RS01")
	await _wait(0.8)
	await _shot("m21c_brief_tide")
	get_tree().current_scene.get_children().filter(func(n: Node) -> bool: return n is MissionWindow).map(func(n: Node) -> void: n.close())
	sa.tide["left"] = 0
	await _wait(3.0)
	await _shot("m21d_tide_flood")
	sa.tide["left"] = 0
	await _wait(3.0)
	await _shot("m21e_tide_ebb")
	# переходы и дела лагеря (docs/17): окно пути к месту, выбор героя для дела
	var gsc := get_tree().current_scene
	sa.tide = {}
	sa.squads.clear()
	GameState.missions_changed.emit()
	await _wait(0.8)
	await _shot("m21h_day_plan")
	# подсказка обучения: затемнение и рамка держатся, пока игрок не щёлкнет (проверка через 4 с)
	EventBus.tutorial_hint.emit({"id": "shot", "title": "Дела лагеря", "text": "Проверка подсказки: затемнение держится до щелчка.", "target": "tasks"})
	await _wait(0.6)
	await _shot("m21h2_hint")
	await _wait(4.0)
	await _shot("m21h3_hint_hold")
	var click := InputEventKey.new()
	click.keycode = KEY_SPACE
	click.pressed = true
	Input.parse_input_event(click)
	await _wait(0.8)
	await _shot("m21h4_hint_gone")
	gsc.call("_show_travel", "statue_hill")
	await _wait(0.4)
	await _shot("m21i_travel")
	gsc.call("_close_travel")
	gsc.call("_pick_task_hero", "scout")
	await _wait(0.4)
	await _shot("m21j_task_pick")
	for n in gsc.get_children():
		if n == gsc.get("_picker"):
			n.queue_free()
	# Воспоминание-добыча (LootRules): выбор 1 из 3
	var lrng := RandomNumberGenerator.new()
	lrng.seed = 7
	LootRules.offer(ContentDB.data, sa, "SH28", "", lrng)
	await _wait(2.5)
	await _shot("m21f_memory")
	for n in get_tree().current_scene.get_children():
		if n is MemoryChoice:
			n.call("_choose", 1)
	await _wait(0.45)
	await _shot("m21g_memory_pick")
	await _wait(1.5)
	# психика (docs/16 §9г): карты в кризисе, момент срабатывания, планшет
	sa.character("P10")["psy"] = {"state": "panic", "origin": "mission"}
	sa.character("P10")["panic"] = 100
	sa.character("P02")["psy"] = {"state": "uplift", "origin": "mission"}
	sa.character("P02")["panic"] = 100
	sa.character("P03")["panic"] = 55
	GameState.missions_changed.emit()
	EventBus.state_changed.emit()
	await _wait(0.8)
	await _shot("m22_crisis_cards")
	var fxp := CrisisFX.play(get_tree().current_scene, [{"card": "P10", "state": "panic", "quote": "«Мы здесь умрём. Все. Слышите?!»"}])
	await _wait(1.1)
	await _shot("m23_fx_panic")
	await fxp.finished
	var fxu := CrisisFX.play(get_tree().current_scene, [{"card": "P02", "state": "uplift", "quote": "«Держитесь за мной — я проведу.»"}])
	await _wait(1.1)
	await _shot("m24_fx_uplift")
	await fxu.finished
	var ip := CardInspector.open_for(get_tree().current_scene, "P03")
	await _wait(0.6)
	ip.call("_show_hint", SquadLifeUI.panic_hint("P03"))
	await _wait(0.4)
	await _shot("m25_psyche_inspector")
	ip.call("_close")
	for cid: String in ["P10", "P02"]:
		sa.character(cid).erase("psy")
	await _wait(0.3)
	# навыки карт в бою (docs/16 §9д): Лазурный Клинок и Знание Карапакса против Падальщика, Касси в поддержке
	for card: String in ["U07", "K07"]:
		EffectApplier.add_card(ContentDB.data, sa, card)
	sa.character("P01")["pocket"] = ["U07", "K07"]
	var setup := {"state": sa.to_dict(), "key": "SHOT", "spec": {"enemies": ["M03"], "field": "F_08"}, "hero": "P01",
		"enh": ["U07", "K07"], "support": ["P03"], "ctx_event": {"id": "SHOT", "tags": ["combat"]}, "ctx_option": {"id": "SHOT_a", "tags": []}}
	SettingsService.values["roll_speed"] = 1.0   # удары — с обычной скоростью, чтобы поймать выпад и урон
	get_tree().current_scene.call("_watch_combat", setup)
	await _wait(2.2)
	await _shot("m26_memory_fire")
	await _wait(1.6)
	await _shot("m27_memory_after")
	# ждём начала ударов (фаза RESULT экрана боя), потом кадры по ходу обмена
	for i in 80:
		var scr: Array = get_tree().current_scene.get_children().filter(func(n: Node) -> bool: return n is CombatScreen)
		if not scr.is_empty() and scr[0].phase == CombatScreen.Phase.RESULT:
			break
		await _wait(0.2)
	await _wait(0.45)
	await _shot("m27b_strikes")
	await _wait(0.7)
	await _shot("m27c_strikes")
	await _wait(2.5)
	await _shot("m27d_round_end")
	SettingsService.values["roll_speed"] = 0.0
	get_tree().current_scene.get_children().filter(func(n: Node) -> bool: return n is CombatScreen).map(func(n: Node) -> void: n.queue_free())
	await _wait(0.4)
	for card2: String in ["U11", "K08", "U12"]:
		EffectApplier.add_card(ContentDB.data, sa, card2)
	var ipk := CardInspector.open_for(get_tree().current_scene, "P01")
	await _wait(0.7)
	await _shot("m28_pocket")
	ipk.call("_close")
	await _wait(0.3)
	# планшеты разных карт: текст и рисунки не должны налезать друг на друга
	for id: String in ["P02", "P03", "U07", "U12", "K07", "A03", "T03", "M04", "M03", "SH28"]:
		var insp := CardInspector.open_for(get_tree().current_scene, id)
		await _wait(0.6)
		await _shot("m30_inspect_" + id)
		insp.call("_close")
		await _wait(0.2)
	# Город людей (глава-черновик): Врата по стадиям, волна, разрушения, взорванный мост, паника
	var cs := AutoPlay.draft_start(ContentDB.data, "city", 77)
	StoryRules.mark_seen(cs, "city")
	GameState.state = cs
	get_tree().reload_current_scene()
	await _wait(2.0)
	await _shot("m40_city_map")
	cs = GameState.state
	var cc := ContentDB.data
	GateRules.raise_signal(cc, cs, "G4")
	GateRules.command(cc, cs, {"do": "raise", "point": "G3", "rank": 2, "open": true})
	GateRules.command(cc, cs, {"do": "raise", "point": "G2", "rank": 1, "open": true})
	cs.flags["gates"]["G2"]["open_day"] = cs.day - 1
	cs.flags["swarms"] = [{"at": "old_center", "from": "bunker", "point": "G2", "nights": 0, "path": ["industry", "bunker", "old_center"]}]
	GateRules.set_site(cs, "old_center", "fight")
	GateRules.set_site(cs, "industry", "ruined")
	GateRules.set_site(cs, "bunker", "damaged")
	GateRules.set_site(cs, "monorail", "repair", 3)
	GateRules.command(cc, cs, {"do": "blow", "place": "bridges"})
	GateRules.command(cc, cs, {"do": "evacuate", "place": "market"})
	cs.flags["panic"] = 55
	GateRules._city_alarm_states(cc, cs)
	MissionFlow.open(cc, cs, "CW06", true)
	GameState.missions_changed.emit()
	await _wait(1.5)
	await _shot("m41_city_gates")
	get_tree().current_scene.call("_open_mission", "CG3")
	await _wait(0.8)
	await _shot("m42_city_gate_brief")
	await _ch4(false)
	get_tree().quit()


## Глава 4: Древо Души (буря, мост, Демон, гнев Владыки, Очарование, Чёрная вода) и Мрачный город (территории,
## охотники, завалы, дань, сюжет по зачищенным районам).
func _ch4(fresh: bool) -> void:
	var c := ContentDB.data
	var ts := AutoPlay.draft_start(c, "tree", 91)
	StoryRules.mark_seen(ts, "tree")
	GameState.state = ts
	if fresh:
		get_tree().change_scene_to_file("res://scenes/missions/mission_game.tscn")
	else:
		get_tree().reload_current_scene()
	await _wait(2.5)
	await _shot("m50_tree_map")
	ts = GameState.state
	for lid: String in MapRules.config(c, "tree").get("places", {}):
		TravelRules.visit(ts, lid)
	ts.day = 1
	ts.party_at = "lake_shore"
	MoverRules.command(c, ts, {"do": "spawn", "mover": "demon", "place": "demon_trail"})
	ts.flags["movers"]["demon"]["from"] = "ash_bones"
	ts.flags["boat"] = true
	TerrainRules.command(c, ts, {"do": "set", "place": "abyss_bridge", "state": "cracked"})
	GameState.missions_changed.emit()
	await _wait(2.0)
	await _shot("m51_tree_night")
	ts.day = 5
	ts.flags["path_set"] = 1
	ts.party_at = "stone_hulk"
	GameState.missions_changed.emit()
	await _wait(4.5)
	await _shot("m52_tree_storm")
	var ds := AutoPlay.draft_start(c, "dark_city", 93)
	StoryRules.mark_seen(ds, "dark_city")
	GameState.state = ds
	get_tree().reload_current_scene()
	await _wait(2.5)
	await _shot("m53_dark_map")
	ds = GameState.state
	for lid: String in MapRules.config(c, "dark_city").get("places", {}):
		TravelRules.visit(ds, lid)
	for mid: String in ["DS01", "DS02", "DS03", "DS04", "DS05", "DS06", "DS07"]:
		ds.missions[mid] = {"status": "done"}
	ZoneRules.command(c, ds, {"do": "clear", "zone": "statues", "days": 30})
	for mid: String in ["DK01", "DK02", "DK03"]:
		MissionFlow.open(c, ds, mid, true)
	ds.day = 1
	ZoneRules.night(c, ds)
	ZoneRules.night(c, ds)
	TerrainRules.command(c, ds, {"do": "collapse", "rubble": "R2"})
	MoverRules.noise(ds, "hunters_guild")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	MoverRules.night(c, ds, rng)
	ds.party_at = "sunny_lair"
	GameState.missions_changed.emit()
	await _wait(2.0)
	await _shot("m54_dark_night")
	get_tree().current_scene.call("_open_mission", "DK01")
	await _wait(0.8)
	await _shot("m55_dark_contract")


# --- карта по дням (коллажи) ---------------------------------------------------------------------------------

## Каждая глава: бот играет, каждое утро — снимок состояния; выбираются 6 дней с самыми заметными переменами
## (первый и последний — всегда) и снимаются без интерфейса. Академия — сценарий прорыва (бот гасит прорывы на сигнале).
## Подписи — timeline.json (MapStory.snapshot): облик каждого места и почему.
func _timeline() -> void:
	var c := ContentDB.data
	var meta := {}
	var first := true
	for chapter: String in ["academy", "shore", "city", "tree", "dark_city"]:
		var frames: Array = _academy_script(c) if chapter == "academy" else _bot_frames(c, chapter)
		var picked := _pick_frames(frames, 6)
		var out: Array = []
		for i in picked.size():
			var fr: Dictionary = picked[i]
			var st: RunState = (fr["state"] as RunState).copy()
			StoryRules.mark_seen(st, chapter)
			GameState.state = st
			if first:
				get_tree().change_scene_to_file("res://scenes/missions/mission_game.tscn")
				first = false
			else:
				get_tree().reload_current_scene()
			await _wait(2.8)
			_map_only()
			await _wait(1.2)
			_map_only()
			var name := "tl_%s_%d" % [chapter, i]
			await _shot(name)
			var snap: Dictionary = fr["snap"]
			snap["file"] = name + ".png"
			snap["note"] = str(fr.get("note", ""))
			out.append(snap)
		meta[chapter] = out
	var f := FileAccess.open("%s/timeline.json" % out_dir, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, " "))
	f.close()


func _bot_frames(c: Content, chapter: String) -> Array:
	var best: Array = []
	var best_score := -1
	for sd in 3:
		var s := MapStory.start(c, chapter, 5200 + sd * 31)
		var frames: Array = [{"state": s.copy(), "snap": MapStory.snapshot(c, s)}]
		var last := s.day
		for step in 3000:
			var r := AutoPlay.step(c, s)
			s = r["state"]
			if str(r["error"]) != "" or s.game_over or s.chapter != chapter:
				break
			if s.day != last or s.demo_complete:
				if s.day == last and frames.size() > 1:
					frames.pop_back()   # финал главы в тот же день — вместо утреннего снимка
				last = s.day
				frames.append({"state": s.copy(), "snap": MapStory.snapshot(c, s)})
			if s.demo_complete:
				break
		var score := 0
		for i in range(1, frames.size()):
			score += _change(frames[i - 1]["snap"], frames[i]["snap"])
		if score > best_score:
			best_score = score
			best = frames
	return best


## Академия: прорыв по шагам, как в тесте (сигнал → пролом → рой → повреждение → отбит → ремонт).
func _academy_script(c: Content) -> Array:
	var s := MapStory.start(c, "academy", 5)
	for mid: String in MissionFlow.open_missions(s):
		s.missions[mid]["status"] = "done"
	s.party_at = "capsules"
	var frames: Array = [{"state": s.copy(), "snap": MapStory.snapshot(c, s), "note": "начало: тихий кампус"}]
	GateRules.raise_signal(c, s, "B3")
	frames.append({"state": s.copy(), "snap": MapStory.snapshot(c, s), "note": "сигнал на восточной стене"})
	DayRules.end_day(c, s)
	frames.append({"state": s.copy(), "snap": MapStory.snapshot(c, s), "note": "ночь: прорыв, тревога в медкрыле"})
	DayRules.end_day(c, s)
	frames.append({"state": s.copy(), "snap": MapStory.snapshot(c, s), "note": "пролом не закрыли: рой в кампусе"})
	DayRules.end_day(c, s)
	frames.append({"state": s.copy(), "snap": MapStory.snapshot(c, s), "note": "рой не отбили: медкрыло повреждено, рой идёт дальше"})
	if not GateRules.swarms(s).is_empty():
		GateRules.command(c, s, {"do": "clear", "place": str(GateRules.swarms(s)[0]["at"])})
	DayRules.end_day(c, s)
	frames.append({"state": s.copy(), "snap": MapStory.snapshot(c, s), "note": "рой отбит: ремонт"})
	return frames


## Сколько заметных перемен между двумя снимками.
func _change(a: Dictionary, b: Dictionary) -> int:
	var n := 0
	var pa: Dictionary = a.get("places", {})
	var pb: Dictionary = b.get("places", {})
	for lid: String in pb:
		if str(pa.get(lid, {}).get("state", "")) != str(pb[lid].get("state", "")):
			n += 2
		if bool(pa.get(lid, {}).get("known", false)) != bool(pb[lid].get("known", false)):
			n += 1
	for k: String in ["emerged", "flooded", "rubble"]:
		if str(a.get(k, [])) != str(b.get(k, [])):
			n += 3
	for k: String in ["gates", "zones", "movers"]:
		if str(a.get(k, {})) != str(b.get(k, {})):
			n += 2
	if int(a.get("path_set", 0)) != int(b.get("path_set", 0)):
		n += 3
	return n


func _pick_frames(frames: Array, n: int) -> Array:
	if frames.size() <= n:
		return frames
	var scored: Array = []
	for i in range(1, frames.size() - 1):
		scored.append({"i": i, "score": _change(frames[i - 1]["snap"], frames[i]["snap"])})
	scored.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["score"]) > int(y["score"]))
	var idx: Array = [0, frames.size() - 1]
	for e: Dictionary in scored.slice(0, n - 2):
		idx.append(int(e["i"]))
	idx.sort()
	return idx.map(func(i: int) -> Dictionary: return frames[i])


## Только карта: интерфейс, метки миссий, туман-частицы скрыты; карта по центру.
func _map_only() -> void:
	var game := get_tree().current_scene
	var sl: SleeperMap = game.get("_sleeper")
	if sl == null:
		return
	for ch in game.get_children():
		if ch is CanvasItem and ch != sl:
			(ch as CanvasItem).visible = false
	sl.set_pan(Vector2((sl.view.size.x - sl.rect.size.x) / 2.0, -float(sl.cfg.get("view_top", 0.08)) * sl.rect.size.y))


# --- фигура (docs/18) ----------------------------------------------------------------------------------------

func _figure() -> void:
	var c := ContentDB.data
	var s := MissionFlow.new_run(c, 77, "shore")
	EffectApplier.add_card(c, s, "P02")
	EffectApplier.add_card(c, s, "P03")
	StoryRules.mark_seen(s, "shore")
	GameState.state = s
	get_tree().change_scene_to_file("res://scenes/missions/mission_game.tscn")
	await _wait(3.0)
	await _shot("f01_field")
	var game := get_tree().current_scene
	var sl: SleeperMap = game.get("_sleeper")
	# перетаскивание: соседние участки подсвечены, над одним — фигура
	game.call("_on_figure_drag")
	var targets: Array = sl.drag_targets
	if not targets.is_empty():
		sl.drag_hover = str(targets[0])
		var fig: FigurePiece = game.get("_figure")
		var p: Vector2 = sl.center(c, GameState.state, str(targets[0])) + sl.pan
		fig.position = p - fig.get_parent().global_position - Vector2(FigurePiece.W / 2.0, FigurePiece.H * 0.85)
	await _wait(0.6)
	await _shot("f02_drag")
	if not targets.is_empty():
		game.call("_on_figure_drop", sl.center(c, GameState.state, str(targets[0])) + sl.pan)
	await _wait(1.6)
	await _shot("f03_move_note")   # шаг — полдня: карточка полудня, лагерь не открывается
	game.call("_on_end_day")        # «Переждать до ночи» — сцена лагеря
	await _wait(2.6)
	await _shot("f03_camp_scene")
	# утро: камера отъехала
	for ch in game.get_children():
		if ch is Control and ch == game.get("_night"):
			pass
	var nb: Control = game.get("_night")
	if nb != null:
		for b in nb.find_children("*", "Button", true, false):
			(b as Button).pressed.emit()
	await _wait(1.6)
	await _shot("f04_morning")
	# разрыв карты события
	var markers: Dictionary = game.get("_markers")
	for mid: String in markers:
		game.call("_shatter", markers[mid])
		break
	await _wait(0.35)
	await _shot("f05_shatter")
	await _wait(1.2)
	# событие на соседнем участке: окно шага фигуры (полдня), событие — во вторую половину
	var cs := GameState.state
	for mid: String in MissionFlow.open_missions(cs):
		if FigureRules.reach(c, cs, mid) == 1:
			game.call("_open_mission", mid)
			break
	await _wait(1.0)
	await _shot("f06_step_to_event")


# --- бродячие боссы на карте (docs/22) --------------------------------------------------------------------------------

func _start_check() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")
	await _wait(1.2)
	var menu := get_tree().current_scene
	menu.call("_on_new")
	await _wait(0.8)
	await _shot("s1_shards")
	var sc: StartScreen
	for ch in menu.get_children():
		if ch is StartScreen:
			sc = ch
	sc.call("_pick", "nephis")
	await _wait(0.6)
	await _shot("s2_nephis")
	sc.call("_pick", "cassie")
	await _wait(0.6)
	await _shot("s3_cassie")
	GameState.new_start_run("sunny")
	StoryRules.mark_seen(GameState.state, "shore")
	get_tree().change_scene_to_file("res://scenes/missions/mission_game.tscn")
	await _wait(3.0)
	await _shot("s4_sunny_shore")
	# ядро души: впитать, выбор характеристики, полное ядро
	GameState.state.resources["shards"] = 80
	var insp := CardInspector.open_for(get_tree().current_scene, "P01")
	await _wait(0.6)
	await _shot("c1_core")
	GameState.core_absorb("P01")
	await _wait(0.6)
	await _shot("c2_core_pick")
	GameState.core_pick("P01", "will")
	for i in 4:
		GameState.core_absorb("P01")
		GameState.core_pick("P01", "power")
	await _wait(0.6)
	await _shot("c3_core_full")
	insp.queue_free()
	await _wait(1.0)
	await _shot("c4_trial_map")


func _fog_check() -> void:
	var c := ContentDB.data
	var first := true
	for spec: Array in [["tree", 5], ["tree", 2], ["shore", 13]]:
		var s := MissionFlow.new_run(c, 93, str(spec[0]))
		for i in int(spec[1]) - 1:
			DayRules.end_day(c, s)
		await _open_map(s, str(spec[0]), first)
		first = false
		await _wait(2.0)
		await _shot("fog_%s_d%d" % [spec[0], spec[1]])
	# кнопка «Спрятать карты»
	var game := get_tree().current_scene
	game.call("_set_tray", false, true)
	await _wait(0.8)
	await _shot("tray_hidden")
	game.call("_set_tray", true, true)
	await _wait(0.8)
	await _shot("tray_shown")


func _bosses() -> void:
	var c := ContentDB.data
	var first := true
	for chapter: String in ["shore", "tree", "dark_city", "city"]:
		var s := MissionFlow.new_run(c, 91, chapter)
		EffectApplier.add_card(c, s, "P02")
		EffectApplier.add_card(c, s, "P03")
		_reveal_all(c, s, chapter)
		var w: Dictionary = WanderRules.defs(c, chapter)[0]
		for i in int(w["appear_day"]):
			DayRules.end_day(c, s)
		await _open_map(s, chapter, first)
		first = false
		var game := get_tree().current_scene
		var act := WanderRules.active(c, GameState.state)
		if not act.is_empty():
			var list := QuestRules.list(c, GameState.state)
			for e: Dictionary in list:
				if str(e["kind"]) == "boss":
					game.call("_quest_show", e)
					break
			await _wait(1.0)
		await _shot("b_%s_1" % chapter)
		if chapter == "shore":   # фишка крупно: ракурс меняется через прозрачность
			var sl: SleeperMap = game.get("_sleeper")
			var wd: Dictionary = sl.get("_wanderers")
			for wid: String in wd:
				var tk: WanderToken = wd[wid]["token"]
				for f in 4:
					tk.turn_to(f)
					await _wait(1.0)
					await _shot("b_shore_turn_%d" % (f + 1))
	# карты боссов и наград в планшете
	for id: String in ["MW1", "LW1", "MW4", "LW4"]:
		var insp := CardInspector.open_for(get_tree().current_scene, id)
		await _wait(0.7)
		await _shot("b_inspect_" + id)
		insp.queue_free()
		await _wait(0.2)


# --- мысли героев вживую: с подсказками, обычные сроки (проверка 03.10) ---------------------------------------------

func _chatter_live() -> void:
	var c := ContentDB.data
	var s := MissionFlow.new_run(c, 71, "shore")
	EffectApplier.add_card(c, s, "P02")
	EffectApplier.add_card(c, s, "P03")
	StoryRules.mark_seen(s, "shore")
	GameState.state = s
	get_tree().change_scene_to_file("res://scenes/missions/mission_game.tscn")
	await _wait(3.0)
	var game := get_tree().current_scene
	var ch: ChatterLayer = game.get("_chatter")
	var hint: HintPopup = game.get("_hint")
	for t in 12:
		print("[live] t=%ds можно говорить=%s подсказка видна=%s до реплики=%.1f пузырей=%d" % [t * 5, game.call("_chatter_ok"),
			hint.is_showing() if hint != null else false, float(ch.get("_next")), (ch.get("_bubbles") as Dictionary).size()])
		if t == 1 and hint != null and hint.visible:
			# игрок прочитал подсказки — они ушли
			print("[live] подсказка: ", (hint.get("_title") as Label).text, " · в очереди ", (hint.get("_queue") as Array).size())
			(hint.get("_queue") as Array).clear()
			hint.call("_hide")
		if (ch.get("_bubbles") as Dictionary).size() > 0:
			await _shot("live_bubble_%02d" % t)
		await _wait(5.0)


# --- значки модификаторов над ромбами; история при смене размера окна (03.10) ---------------------------------------

func _mods() -> void:
	var c := ContentDB.data
	var s := MissionFlow.new_run(c, 61, "shore")
	EffectApplier.add_card(c, s, "P02")
	_reveal_all(c, s, "shore")
	s.party_at = "coral_maze"
	var sets := [["fog", "thunder", "cache"], ["wounded"], ["nest", "armored"], ["cursed", "ambush", "tidepools", "hurry"]]
	var i := 0
	for mid: String in ["SC01", "SS02", "RS05", "RS02"]:
		MissionFlow.open(c, s, mid, true)
		s.missions[mid]["mods"] = sets[i % sets.size()]
		i += 1
	await _open_map(s, "shore", true)
	await _shot("x_mods_1")
	var c2 := ContentDB.data
	var s2 := MissionFlow.new_run(c2, 62, "city")
	EffectApplier.add_card(c2, s2, "P02")
	_reveal_all(c2, s2, "city")
	var k := 0
	for mid2: String in MissionFlow.open_missions(s2):
		s2.missions[mid2]["mods"] = [["gate_rank2", "blackout"], ["gate_rank3", "panic_crowd", "fog"]][k % 2]
		k += 1
	await _open_map(s2, "city", false)
	await _shot("x_mods_2_city")


func _resize() -> void:
	var c := ContentDB.data
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await _wait(0.8)
	var s := MissionFlow.new_run(c, 5, "shore")
	GameState.state = s
	get_tree().change_scene_to_file("res://scenes/missions/mission_game.tscn")
	await _wait(2.5)
	await _shot("r1_story_small")
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await _wait(1.2)
	await _shot("r2_story_big")


# --- задания справа (docs/20) ------------------------------------------------------------------------------------------

func _quests() -> void:
	var c := ContentDB.data
	var first := true
	for chapter: String in ["shore", "academy", "tree"]:
		var s := MissionFlow.new_run(c, 61, chapter)
		EffectApplier.add_card(c, s, "P02")
		EffectApplier.add_card(c, s, "P03")
		_reveal_all(c, s, chapter)
		if chapter == "shore":
			MissionFlow.open(c, s, "SC01", true)
			MissionFlow.open(c, s, "SS02", true)
			s.party_at = "coral_maze"
		await _open_map(s, chapter, first)
		first = false
		var game := get_tree().current_scene
		await _shot("q_%s_1panel" % chapter)
		var list := QuestRules.list(c, GameState.state)
		if not list.is_empty():
			game.call("_quest_show", list[0])
			await _wait(0.9)
			await _shot("q_%s_2show_story" % chapter)
		if list.size() > 1:
			await _wait(4.0)
			game.call("_quest_show", list[-1])
			await _wait(0.9)
			await _shot("q_%s_3show_side" % chapter)
		await _wait(4.5)


# --- замер производительности (аудит 03.10): кадр и тяжёлые функции экрана карты -------------------------------------

func _perf() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	SettingsService.values["chatter"] = false
	var out: Array = []
	var c := ContentDB.data
	var first := true
	for chapter: String in ["shore", "tree", "academy"]:
		var s := MissionFlow.new_run(c, 41, chapter)
		EffectApplier.add_card(c, s, "P02")
		EffectApplier.add_card(c, s, "P03")
		_reveal_all(c, s, chapter)
		if chapter == "shore":
			s.day = 13
			s.party_at = "statue_hill"
		DayPlanner.ensure(c, s)
		await _open_map(s, chapter, first)
		first = false
		var game := get_tree().current_scene
		await _wait(1.5)
		out.append("== %s: мест открыто %d, событий на карте %d, узлов %d" % [chapter, MapRules.known(c, GameState.state).size(),
			(game.get("_markers") as Dictionary).size(), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
		out.append_array(await _frames(4.0))
		var sl: SleeperMap = game.get("_sleeper")
		if chapter == "shore":
			# что сколько стоит: кадр без одной части (часть выключена — разница и есть её цена)
			var parts := {"туман войны (шейдер)": [sl.get("_fog")], "вода (шейдер высот)": [sl.get("_water")],
				"частицы экрана (туман, искры)": [game.get("_fog"), game.get("_embers")], "погода и тени облаков": [sl.get("_weather"), sl.get("_shade")],
				"угрозы и следы на карте": [sl.get("_threat")], "метки событий": [game.get("_pins_layer")],
				"ряд героев (карты, ауры)": [game.get("_heroes_row")], "подписи и кольца": [sl.get("_over"), sl.get("_labels")]}
			for part: String in parts:
				for n in parts[part]:
					if n != null:
						(n as CanvasItem).visible = false
				var r: Array = await _frames(2.0)
				out.append("   без «%s»: %s" % [part, str(r[0]).strip_edges().get_slice(";", 0)])
				for n in parts[part]:
					if n != null:
						(n as CanvasItem).visible = true
		out.append(_time("sleeper.sync (пересборка карты-плана)", 20, func() -> void: sl.sync(c, GameState.state, Atmosphere.sky(c, GameState.state))))
		out.append(_time("_refresh (обновление экрана)", 20, func() -> void: game.call("_refresh")))
		out.append(_time("_update_pins (метки событий)", 50, func() -> void: game.call("_update_pins")))
		out.append(_time("_update_tide (вода и строка угроз)", 20, func() -> void: game.call("_update_tide")))
		out.append(_time("_update_day (строка дня, план)", 50, func() -> void: game.call("_update_day")))
		out.append(_time("DayPlanner.options", 50, func() -> void: DayPlanner.options(c, GameState.state)))
		out.append(_time("TutorialRules.state_events", 50, func() -> void: TutorialRules.state_events(c, GameState.state)))
		out.append(_time("FigureRules.targets", 100, func() -> void: FigureRules.targets(c, GameState.state)))
		out.append(_time("MapRules.known", 100, func() -> void: MapRules.known(c, GameState.state)))
		var rng := RandomNumberGenerator.new()
		out.append(_time("ChatterRules.pick", 50, func() -> void: ChatterRules.pick(c, GameState.state, ["P01", "P02", "P03"], [], false, [], rng)))
	var f := FileAccess.open(out_dir + "/perf.txt", FileAccess.WRITE)
	f.store_string("\n".join(out) + "\n")
	f.close()
	print("\n".join(out))


## Кадры: средний и 95-й перцентиль по delta (без вертикальной синхронизации), время _process, вызовы отрисовки.
func _frames(sec: float) -> Array:
	var deltas: Array = []
	var proc := 0.0
	var draws := 0.0
	var n := 0
	var t := 0.0
	while t < sec:
		await get_tree().process_frame
		var d := get_process_delta_time()
		t += d
		deltas.append(d * 1000.0)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		n += 1
	deltas.sort()
	var avg := 0.0
	for d2: float in deltas:
		avg += d2
	avg /= maxf(1.0, deltas.size())
	return ["   кадр: в среднем %.2f мс (%.0f FPS), 95%% кадров не дольше %.2f мс; _process %.2f мс; вызовов отрисовки %.0f; память %.0f МБ" % [
		avg, 1000.0 / avg, deltas[int(deltas.size() * 0.95)], proc / n, draws / n, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0]]


func _time(label: String, n: int, f: Callable) -> String:
	var t0 := Time.get_ticks_usec()
	for i in n:
		f.call()
	var us := float(Time.get_ticks_usec() - t0) / n
	return "   %-40s %8.3f мс" % [label, us / 1000.0]


# --- мысли и реплики героев, половины дня (03.10) ---------------------------------------------------------------------

func _chatter() -> void:
	var c := ContentDB.data
	var s := MissionFlow.new_run(c, 77, "shore")
	EffectApplier.add_card(c, s, "P02")
	EffectApplier.add_card(c, s, "P03")
	var card := ""
	for k: String in c.enhancements:
		if not Dictionary(c.enhancements[k].get("memory", {})).is_empty():
			card = k
			break
	EffectApplier.add_card(c, s, card)
	s.character("P01")["pocket"] = [card]
	_reveal_all(c, s, "shore")
	s.party_at = "coral_maze"
	await _open_map(s, "shore", true)
	var game := get_tree().current_scene
	var ch: ChatterLayer = game.get("_chatter")
	# сама: что скажут здесь и сейчас (место, сюжет, кармашек)
	ch.set("_next", 0.0)
	await _wait(1.4)
	await _shot("c01_line")
	await _wait(9.0)
	# диалог о Воспоминании в кармашке, мысль о месте, высказывание
	ch.call("_bubble", "P02", "say", "Что за Воспоминание ты бережёшь?")
	await _wait(1.0)
	var use := ChatterRules.use_phrase(c, card)
	ch.call("_bubble", "P01", "say", "«%s». %s." % [c.card_name(card), use.left(1).to_upper() + use.substr(1)])
	ch.call("_bubble", "P03", "thought", "Багровый лабиринт звучит иначе, чем вчерашнее место. Тише… или осторожнее.")
	await _wait(0.8)
	await _shot("c02_dialog")
	await _wait(8.0)
	ch.call("_bubble", "P03", "wisdom", "Будущее похоже на реку: его можно услышать, но не остановить.")
	await _wait(0.8)
	await _shot("c03_wisdom")
	await _wait(6.0)
	# полдень: «Переждать полдня»
	game.call("_on_end_day")
	await _wait(1.2)
	await _shot("c04_midday")
	# событие на соседнем участке: окно шага фигуры
	var cs := GameState.state
	for mid: String in MissionFlow.open_missions(cs):
		if FigureRules.reach(c, cs, mid) == 1:
			game.call("_open_mission", mid)
			break
	await _wait(1.0)
	await _shot("c05_step_to_event")


# --- события ромбами (эксперимент 03.10) ------------------------------------------------------------------------------

func _icons() -> void:
	var c := ContentDB.data
	for chapter: String in ["shore", "academy", "tree"]:
		var s := MissionFlow.new_run(c, 77, chapter)
		EffectApplier.add_card(c, s, "P02")
		EffectApplier.add_card(c, s, "P03")
		_reveal_all(c, s, chapter)
		SettingsService.values["event_icons"] = false
		await _open_map(s, chapter, chapter == "shore")
		await _shot("i_%s_0cards" % chapter)
		SettingsService.values["event_icons"] = true
		await _open_map(s, chapter, false)
		await _shot("i_%s_1icons" % chapter)
		var game := get_tree().current_scene
		var markers: Dictionary = game.get("_markers")
		# наведение на событие у фигуры (если есть), иначе на первое
		var pick: MissionMarker = null
		for mid: String in markers:
			if pick == null or str(c.missions[mid].get("location", "")) == s.party_at:
				pick = markers[mid]
		if pick == null:
			continue
		pick.set("_hover", true)
		await _wait(0.3)
		await _shot("i_%s_2loading" % chapter)
		await _wait(0.6)
		await _shot("i_%s_3detail" % chapter)
		pick.set("_hover", false)
		await _wait(0.8)


# --- места и следы событий (комплекты событий Берега и Главы 4) ------------------------------------------------------

func _open_map(st: RunState, chapter: String, first: bool) -> void:
	StoryRules.mark_seen(st, chapter)
	GameState.state = st
	if first:
		get_tree().change_scene_to_file("res://scenes/missions/mission_game.tscn")
	else:
		get_tree().reload_current_scene()
	await _wait(3.0)


func _reveal_all(c: Content, st: RunState, chapter: String) -> void:
	for lid: String in MapRules.config(c, chapter).get("places", {}):
		TravelRules.visit(st, lid)


func _events() -> void:
	var c := ContentDB.data
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# Берег: Кровавая луна второй недели — алтарь, красный Шпиль, дымка, отсвет; места и следы событий
	var s := MissionFlow.new_run(c, 41, "shore")
	EffectApplier.add_card(c, s, "P02")
	EffectApplier.add_card(c, s, "P03")
	_reveal_all(c, s, "shore")
	s.day = 13
	s.party_at = "statue_hill"
	for lid: String in ["strangers_camp", "whale_carcass", "legion_well", "sleeping_golem", "messenger_nest", "centipede_lair", "fallen_star"]:
		MapRules.emerge(c, s, lid, rng)
	MapRules.mark(c, s, "legion_ruins", "banner", 999)
	MissionFlow.open(c, s, "RS02", true)
	s.missions["RS02"]["mods"] = ["fog"]
	MissionFlow.open(c, s, "RS09", true)
	s.missions["RS09"]["mods"] = ["cursed"]
	MapEventRules.after_mission(c, s, "RS10", {"outcome": "failure", "deaths": ["P03"]}, rng)
	MapEventRules.night_attack(c, s)
	await _open_map(s, "shore", true)
	_map_only()
	await _wait(0.6)
	await _shot("e01_shore_events")
	# ночь у лагеря: нападение — лагерь в тревоге
	await _open_map(s, "shore", false)
	get_tree().current_scene.call("_night_cinematic", [{"kind": "night_ordeal", "ok": false, "text": "На лагерь напали ночью — не все целы"}])
	await _wait(1.5)
	await _shot("e02_shore_camp_alarm")
	# Пепельный путь: Демон со следами, гнев Владыки, Очарование, огонь Маяка, лодка, пепельная буря
	var t := AutoPlay.draft_start(c, "tree", 7)
	_reveal_all(c, t, "tree")
	t.day = 5
	MoverRules.command(c, t, {"do": "spawn", "mover": "demon", "place": "demon_trail"})
	t.flags["movers"]["demon"]["from"] = "ash_bones"
	MoverRules.command(c, t, {"do": "lure", "mover": "demon", "place": "death_beacon", "days": 3})
	t.flags["boat"] = true
	await _open_map(t, "tree", false)
	_map_only()
	await _wait(0.6)
	await _shot("e03_ash_path")
	t.day = 1
	await _open_map(t, "tree", false)
	_map_only()
	await _wait(0.6)
	await _shot("e04_ash_path_night")
	# Мрачный город: охотники, статуи, территории и паутина, завал и пролом, логова, дозор у ворот
	var d := AutoPlay.draft_start(c, "dark_city", 9)
	_reveal_all(c, d, "dark_city")
	d.day = 1
	ZoneRules.night(c, d)
	ZoneRules.night(c, d)
	TerrainRules.command(c, d, {"do": "collapse", "rubble": "R2"})
	TerrainRules.command(c, d, {"do": "clear", "rubble": "R5"})
	MoverRules.noise(d, "hunters_guild")
	MoverRules.night(c, d, rng)
	await _open_map(d, "dark_city", false)
	_map_only()
	await _wait(0.6)
	await _shot("e05_dark_city")


## Подписи мест: один и тот же вид карты в каждом стиле SleeperMap.label_style (Берег ночью, Мрачный город, светлые дюны).
func _labels() -> void:
	var c := ContentDB.data
	var setups: Array = [["shore", 1], ["dark_city", 3], ["tree", 3]]
	var first := true
	for su: Array in setups:
		var chapter: String = su[0]
		var st := MapStory.start(c, chapter, 21)
		_reveal_all(c, st, chapter)
		st.day = int(su[1])
		await _open_map(st, chapter, first)
		first = false
		_map_only()
		var sl: SleeperMap = get_tree().current_scene.get("_sleeper")
		if sl == null:
			print("[labels] нет карты: сцена ", get_tree().current_scene, " глава ", GameState.state.chapter, " лагерь ", GameState.state.party_at)
			continue
		for style: String in ["silver", "white", "ice", "shadow", "gold", "caps", "frost"]:
			sl.label_style = style
			await _wait(0.3)
			await _shot("lbl_%s_%s" % [chapter, style])
