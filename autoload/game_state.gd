extends Node
## Текущее прохождение и API миссий для интерфейса (docs/15). Логика — в core/rules.

signal missions_changed
signal mission_events(events: Array)

var state: RunState
var combat: CombatSession   # бой, который сейчас показывает экран «Столкновение» (просмотр автобоя)
var last_outcomes: Dictionary = {}   # миссия -> исход последнего решённого события (окно карты рвёт карту удачного)
var last_launch: Dictionary = {}   # последний выход: {squad, entries} — окно миссии сразу показывает прибытие
var story_open := false     # идёт сюжетное окно: часы стоят, подсказки ждут


func content() -> Content:
	return ContentDB.data


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
		if lock == "":
			lock = DayRules.can_equip(ContentDB.data, state)
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
		if lock == "":
			lock = DayRules.can_equip(ContentDB.data, state)
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


## Ядро души (CoreRules, docs/23): впитать осколки — следующий уровень. "" — сделано, иначе причина.
func core_absorb(cid: String) -> String:
	var r := CoreRules.absorb(content(), state, cid)
	if not r["ok"]:
		return str(r["error"])
	SaveService.save_state(state)
	missions_changed.emit()
	EventBus.state_changed.emit()
	mission_events.emit(r["entries"])
	return ""


## Ядро души: +1 к характеристике за уровень.
func core_pick(cid: String, stat: String) -> String:
	var r := CoreRules.pick(content(), state, cid, stat)
	if not r["ok"]:
		return str(r["error"])
	SaveService.save_state(state)
	EventBus.state_changed.emit()
	return ""


## Новая игра с выбранным стартом «разбитое стекло» (StartRules): с Забытого Берега.
func new_start_run(start_id: String, seed_value: int = -1) -> void:
	if seed_value < 0:
		seed_value = randi()
	state = StartRules.new_run(content(), seed_value, start_id)
	SaveService.save_state(state)
	EventBus.state_changed.emit()


## «Закончить день»: ночь в лагере и новое утро. Возвращает записи ночи (для окна «Ночь»).
func end_day() -> Array:
	var why := DayRules.can_end(state)
	if why != "":
		EventBus.toast.emit(why)
		return []
	var ev: Array = DayRules.end_day(content(), state)
	SaveService.save_state(state)
	missions_changed.emit()
	EventBus.state_changed.emit()
	return ev


## Переход отряда в соседнее место без миссии. "" — перешли, иначе причина.
func move_party(lid: String) -> String:
	var out: Array = []
	var why := DayRules.move(content(), state, lid, out)
	if why != "":
		return why
	SaveService.save_state(state)
	missions_changed.emit()
	EventBus.state_changed.emit()
	mission_events.emit(out)
	return ""


## Фигура (docs/18): переставить на соседний участок — полдня. {error, events} — переход и полдень или ночь.
func figure_move(lid: String) -> Dictionary:
	var r := FigureRules.move(content(), state, lid)
	if not r["ok"]:
		return {"error": r["error"], "events": []}
	_after_day()
	return {"error": "", "events": r["entries"]}


## Фигура: «Переждать полдня». {error, events} — полдень или ночь.
func figure_wait() -> Dictionary:
	var r := FigureRules.wait(content(), state)
	if not r["ok"]:
		return {"error": r["error"], "events": []}
	_after_day()
	return {"error": "", "events": r["entries"]}


## Фигура: дело лагеря — полдня. {error, events} — дело и полдень или ночь.
func figure_task(task: String, cid: String) -> Dictionary:
	var r := FigureRules.task(content(), state, task, cid)
	if not r["ok"]:
		return {"error": r["error"], "events": []}
	_after_day()
	return {"error": "", "events": r["entries"]}


## Фигура: событие закончено — прошло полдня. Записи полудня или ночи ([] — событие не решено).
func figure_event_done() -> Array:
	var ev := FigureRules.end_after_event(content(), state)
	if not ev.is_empty():
		_after_day()
	return ev


func _after_day() -> void:
	SaveService.save_state(state)
	missions_changed.emit()
	EventBus.state_changed.emit()


## Дело лагеря (DayPlanner, docs/17 §6): "" — сделано; иначе причина.
func do_task(task: String, cid: String) -> String:
	var r := DayPlanner.do_task(content(), state, task, cid)
	if not r["ok"]:
		return str(r["error"])
	SaveService.save_state(state)
	missions_changed.emit()
	EventBus.state_changed.emit()
	mission_events.emit(r["entries"])
	return ""


## "" — отряд ушёл; иначе причина.
func launch_squad(mission_id: String, heroes: Array) -> String:
	var r: Dictionary = MissionFlow.launch(content(), state, mission_id, heroes)
	if not r["ok"]:
		return r["error"]
	last_launch = r
	SaveService.save_state(state)
	missions_changed.emit()
	EventBus.state_changed.emit()
	return ""


## Выбор на развилке (docs/16 §2): продолжить, сменить путь или отступить. Отчёт — как у resolve_squad.
func resolve_fork(squad_id: int, option_id: String) -> Dictionary:
	var mid := str(MissionFlow.squad(state, squad_id).get("mission", ""))
	var r: Dictionary = MissionResolver.resume(content(), state, squad_id, option_id)
	if not r["ok"]:
		return {"error": r["error"]}
	state = r["state"]
	if not r.has("fork"):
		last_outcomes[mid] = str(r["report"].get("outcome", ""))
	SaveService.save_state(state)
	missions_changed.emit()
	EventBus.state_changed.emit()
	return r["report"]


## Выбор действия прибывшего отряда. Возвращает отчёт (или {"error": ...}).
func resolve_squad(squad_id: int, action_id: String) -> Dictionary:
	var mid := str(MissionFlow.squad(state, squad_id).get("mission", ""))
	var r: Dictionary = MissionResolver.resolve(content(), state, squad_id, action_id)
	if not r["ok"]:
		return {"error": r["error"]}
	state = r["state"]
	if not r.has("fork"):
		last_outcomes[mid] = str(r["report"].get("outcome", ""))
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


## Услуга торговца (лечение, заточка, починка). "" — успех.
func shop_service(shop_id: String, kind: String, target: String, extra: String = "") -> String:
	var err := ServiceRules.perform(content(), state, shop_id, kind, target, extra)
	if err != "":
		return err
	AudioManager.play("place", -4.0)
	SaveService.save_state(state)
	missions_changed.emit()
	EventBus.state_changed.emit()
	return ""


## Лагерь: уложить героя на койку / поднять. "" — успех.
func camp_put(cid: String) -> String:
	var err := CampRules.put(content(), state, cid)
	if err == "":
		AudioManager.play("place", -4.0)
		SaveService.save_state(state)
		EventBus.state_changed.emit()
	return err


func camp_take(cid: String) -> void:
	CampRules.take(state, cid)
	SaveService.save_state(state)
	EventBus.state_changed.emit()


## Подсказка обучения к событию (docs/16 Ф12): один раз за прохождение, если подсказки включены.
func tutorial(event: String) -> void:
	if state == null or story_open or not bool(SettingsService.get_value("tutorial")):
		return
	var h := TutorialRules.take(content(), state, event)
	if not h.is_empty():
		SaveService.save_state(state)
		EventBus.tutorial_hint.emit(h)


## Воспоминание-добыча: игрок взял одну из трёх карт ("" — отказался).
func take_memory(card: String) -> Array:
	var out := LootRules.take(content(), state, card)
	SaveService.save_state(state)
	EventBus.state_changed.emit()
	missions_changed.emit()
	return out


func shop_seen(shop_id: String) -> void:
	ShopRules.mark_seen(content(), state, shop_id)
	SaveService.save_state(state)
