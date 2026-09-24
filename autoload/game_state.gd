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
	EventBus.draft_changed.emit(event_id)


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
	var r := TurnResolver.resolve(content(), state, event_id, option_id, draft(event_id), _extras())
	if not r["ok"]:
		EventBus.toast.emit(r["reason"])
		return r
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


func _extras() -> Dictionary:
	return {"concentration": concentration.duplicate(), "ward": ward}
