extends Node
## Текущее прохождение и API миссий для интерфейса (docs/15). Логика — в core/rules.

signal missions_changed
signal mission_events(events: Array)

var state: RunState
var combat: CombatSession   # бой, который сейчас показывает экран «Столкновение» (просмотр автобоя)
var _autosave_at := 0.0


func content() -> Content:
	return ContentDB.data


func has_run() -> bool:
	return state != null


func continue_run() -> String:
	var r: Dictionary = SaveService.load_state(content())
	if not r["ok"]:
		return r["error"]
	state = r["state"]
	EventBus.state_changed.emit()
	return ""


## Кармашек персонажа: до трёх усилений по умолчанию. Усиление лежит только в одном кармашке.
func pocket_add(character_id: String, card: String) -> String:
	var ch := state.character(character_id)
	if ch.is_empty() or ContentDB.data.card_kind(card) != "enhancement" or not state.owns(card):
		return "Это не усиление"
	var pocket: Array = ch.get("pocket", [])
	if pocket.has(card):
		return ""
	if is_missions():
		var lock := MissionFlow.pocket_lock(ContentDB.data, state, character_id, card)
		if lock != "":
			EventBus.toast.emit(lock)
			return "locked"
	if pocket.size() >= 3:
		EventBus.toast.emit("В кармашке не больше трёх усилений")
		return "full"
	for cid: String in state.characters:
		Array(state.characters[cid].get("pocket", [])).erase(card)
	pocket.append(card)
	ch["pocket"] = pocket
	SaveService.save_state(state)
	EventBus.state_changed.emit()
	return ""


func pocket_remove(character_id: String, card: String) -> void:
	var ch := state.character(character_id)
	if is_missions():
		var lock := MissionFlow.pocket_lock(ContentDB.data, state, character_id, card)
		if lock != "":
			EventBus.toast.emit(lock)
			return
	Array(ch.get("pocket", [])).erase(card)
	SaveService.save_state(state)
	EventBus.state_changed.emit()


func is_missions() -> bool:
	return state != null and state.mode == "missions"


## Следующая глава после экрана «Глава пройдена».
func next_chapter() -> void:
	var ch := str(state.flags.get("next_chapter", ""))
	if ch == "":
		return
	var events: Array = MissionFlow.start_chapter(content(), state, ch)
	SaveService.save_state(state)
	missions_changed.emit()
	EventBus.state_changed.emit()
	mission_events.emit(events)


func new_mission_run(seed_value: int = -1) -> void:
	if seed_value < 0:
		seed_value = randi()
	state = MissionFlow.new_run(content(), seed_value)
	SaveService.save_state(state)
	EventBus.state_changed.emit()


## Игровые часы: вызывается экраном миссий каждый кадр. События — прибытие, отдых, новые миссии.
func mission_tick(dt: float) -> void:
	if not is_missions() or state.game_over:
		return
	var ev: Array = MissionFlow.tick(content(), state, dt)
	if not ev.is_empty():
		mission_events.emit(ev)
		missions_changed.emit()
		SaveService.save_state(state)
		_autosave_at = state.clock
	elif state.clock - _autosave_at > 10.0:
		SaveService.save_state(state)
		_autosave_at = state.clock


## "" — отряд ушёл; иначе причина.
func launch_squad(mission_id: String, heroes: Array) -> String:
	var r: Dictionary = MissionFlow.launch(content(), state, mission_id, heroes)
	if not r["ok"]:
		return r["error"]
	SaveService.save_state(state)
	missions_changed.emit()
	EventBus.state_changed.emit()
	return ""


## Выбор действия прибывшего отряда. Возвращает отчёт (или {"error": ...}).
func resolve_squad(squad_id: int, action_id: String) -> Dictionary:
	var r: Dictionary = MissionResolver.resolve(content(), state, squad_id, action_id)
	if not r["ok"]:
		return {"error": r["error"]}
	state = r["state"]
	# связи тегов открываются при просмотре боя или при закрытии отчёта (MissionWindow)
	SaveService.save_state(state)
	missions_changed.emit()
	EventBus.state_changed.emit()
	return r["report"]


## Покупка в магазине главы: "" — куплено, иначе причина отказа.
func shop_buy(shop_id: String, card: String) -> String:
	var out: Array = []
	var err := ShopRules.buy(content(), state, shop_id, card, out)
	if err != "":
		return err
	AudioManager.play("new_event", -4.0)
	SaveService.save_state(state)
	missions_changed.emit()
	EventBus.state_changed.emit()
	return ""


func shop_seen(shop_id: String) -> void:
	ShopRules.mark_seen(content(), state, shop_id)
	SaveService.save_state(state)
