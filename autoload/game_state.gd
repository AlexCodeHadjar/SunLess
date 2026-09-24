extends Node
## Текущее прохождение и API хода для интерфейса. Логика — в core/rules.

var state: RunState
## Концентрация и Оберег — черновик на открытом событии, мана списывается при нажатии варианта.
var concentration := {}
var ward := false


func content() -> Content:
	return ContentDB.data


func has_run() -> bool:
	return state != null


func new_run(seed_value: int = -1) -> void:
	if seed_value < 0:
		seed_value = randi()
	state = EventFlow.new_run(content(), seed_value)
	_reset_extras()
	SaveService.save_state(state)
	EventBus.state_changed.emit()


func continue_run() -> String:
	var r: Dictionary = SaveService.load_state(content())
	if not r["ok"]:
		return r["error"]
	state = r["state"]
	_reset_extras()
	EventBus.state_changed.emit()
	return ""


# --- черновик ----------------------------------------------------------------

func draft(event_id: String) -> Dictionary:
	return state.draft_for(event_id)


func set_executor(event_id: String, character_id: String) -> void:
	_detach_everywhere(character_id)
	var d := _draft_mut(event_id)
	d["character"] = character_id
	# кармашек: его усиления прикладываются сами (если есть место)
	for card: String in state.character(character_id).get("pocket", []):
		if state.owns(card) and Array(d["enhancements"]).size() < 3 and not Array(d["enhancements"]).has(card):
			_detach_everywhere(card)
			d["enhancements"].append(card)
	EventBus.draft_changed.emit(event_id)


## Кармашек персонажа: до трёх усилений по умолчанию. Усиление лежит только в одном кармашке.
func pocket_add(character_id: String, card: String) -> String:
	var ch := state.character(character_id)
	if ch.is_empty() or ContentDB.data.card_kind(card) != "enhancement" or not state.owns(card):
		return "Это не усиление"
	var pocket: Array = ch.get("pocket", [])
	if pocket.has(card):
		return ""
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
	Array(ch.get("pocket", [])).erase(card)
	SaveService.save_state(state)
	EventBus.state_changed.emit()


func clear_executor(event_id: String) -> void:
	_draft_mut(event_id)["character"] = ""
	EventBus.draft_changed.emit(event_id)


func attach(event_id: String, card: String) -> String:
	var d := _draft_mut(event_id)
	var list: Array = d["enhancements"]
	if list.has(card):
		return ""
	if list.size() >= 3:
		return "Не больше трёх усилений"
	_detach_everywhere(card)
	list.append(card)
	EventBus.draft_changed.emit(event_id)
	return ""


func detach(event_id: String, card: String) -> void:
	Array(_draft_mut(event_id)["enhancements"]).erase(card)
	EventBus.draft_changed.emit(event_id)


func _draft_mut(event_id: String) -> Dictionary:
	if not state.drafts.has(event_id):
		state.drafts[event_id] = {"character": "", "enhancements": []}
	return state.drafts[event_id]


func _detach_everywhere(card: String) -> void:
	for eid: String in state.drafts:
		var d: Dictionary = state.drafts[eid]
		if d.get("character", "") == card:
			d["character"] = ""
		Array(d.get("enhancements", [])).erase(card)


func _reset_extras() -> void:
	concentration = {}
	ward = false


# --- мана в планшете ------------------------------------------------------------

func add_concentration(stat: String) -> String:
	var n := int(concentration.get(stat, 0))
	if n >= TurnResolver.CONCENTRATION_MAX:
		return "Концентрация — не больше двух раз"
	var total := 0
	for s: String in concentration:
		total += int(concentration[s])
	if (total + 1) * TurnResolver.CONCENTRATION_COST > int(state.resources.get("mana", 0)):
		return "Не хватает маны"
	concentration[stat] = n + 1
	return ""


func remove_concentration(stat: String) -> void:
	var n := int(concentration.get(stat, 0))
	if n <= 1:
		concentration.erase(stat)
	else:
		concentration[stat] = n - 1


## Прозрение: 1 мана — раскрыть последствия одного варианта. Списывается сразу.
func foresee(option_id: String) -> String:
	if state.revealed.has(option_id):
		return ""
	if int(state.resources.get("mana", 0)) < 1:
		return "Не хватает маны"
	state.resources["mana"] = int(state.resources["mana"]) - 1
	state.revealed.append(option_id)
	SaveService.save_state(state)
	EventBus.state_changed.emit()
	return ""


# --- ходы ------------------------------------------------------------------

func preview(event_id: String) -> Array:
	return TurnResolver.preview(content(), state, event_id, draft(event_id), concentration)


func can_resolve(event_id: String, option_id: String) -> String:
	return TurnResolver.can_resolve(content(), state, event_id, option_id, draft(event_id), _extras())


func resolve(event_id: String, option_id: String) -> Dictionary:
	var before := state
	var r := TurnResolver.resolve(content(), state, event_id, option_id, draft(event_id), _extras())
	if not r["ok"]:
		EventBus.toast.emit(r["reason"])
		return r
	# Состояние до броска — для «Вернуться к началу хода» после смерти Санни.
	SaveService.save_state(before, "before_turn")
	state = r["state"]
	_reset_extras()
	SaveService.save_state(state)
	EventBus.option_resolved.emit(r["result"])
	EventBus.state_changed.emit()
	return r


func use_initiator(card: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = state.rng_seed
	rng.state = state.rng_state
	var r := EventFlow.use_initiator(content(), state, card, rng)
	state.rng_state = rng.state
	if r["ok"]:
		SaveService.save_state(state)
		EventBus.initiator_used.emit(r["event_id"])
		EventBus.state_changed.emit()
	else:
		EventBus.toast.emit(r["reason"])
	return r


## Свободный режим: переход в место (неделя за шаг) или отдых в лагере.
func move_to(node_id: String) -> Dictionary:
	return _chronicle_turn(func(s: RunState, rng: RandomNumberGenerator) -> Dictionary: return Chronicle.move(content(), s, node_id, rng))


func rest() -> Dictionary:
	return _chronicle_turn(func(s: RunState, rng: RandomNumberGenerator) -> Dictionary: return Chronicle.rest(content(), s, rng))


func _chronicle_turn(action: Callable) -> Dictionary:
	var s := state.copy()
	var rng := RandomNumberGenerator.new()
	rng.seed = s.rng_seed
	rng.state = s.rng_state
	var r: Dictionary = action.call(s, rng)
	if not r["ok"]:
		EventBus.toast.emit(r["reason"])
		return r
	state = s
	SaveService.save_state(state)
	for e: Dictionary in r["entries"]:
		if e.get("kind", "") in ["event", "story", "lost"]:
			EventBus.toast.emit(str(e["text"]))
	EventBus.state_changed.emit()
	return r


func _extras() -> Dictionary:
	return {"concentration": concentration.duplicate(), "ward": ward}


# --- бой ----------------------------------------------------------------------

var combat: CombatSession


func start_combat(event_id: String, option_id: String, support: Array = []) -> String:
	var why := can_resolve(event_id, option_id)
	if why != "":
		return why
	combat = CombatSession.create(content(), state, event_id, option_id, draft(event_id), support, ward)
	return ""


## Завершает бой: применяет итог, сохраняет, открывает связи, показывает результат.
func finish_combat() -> Dictionary:
	if combat == null:
		return {}
	var before := state
	var r := combat.finish()
	SaveService.save_state(before, "before_turn")
	state = r["state"]
	var fresh := ProfileService.discover(combat.discovered)
	r["result"]["discovered"] = fresh
	combat = null
	_reset_extras()
	SaveService.save_state(state)
	EventBus.option_resolved.emit(r["result"])
	EventBus.state_changed.emit()
	return r
