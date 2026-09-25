class_name TurnResolver
extends RefCounted
## Предпросмотр шансов и разрешение хода. Разрешение работает на копии состояния:
## при ошибке исходное состояние не меняется (транзакция, GDD 4.10).

const LOOT_CHANCE := 50
const DEATH_CHARACTER := "P01"  # смерть Санни — конец прохождения
const WARD_COST := 4
const CONCENTRATION_COST := 3
const CONCENTRATION_MAX := 2


## Предпросмотр всех трёх вариантов для текущего черновика.
static func preview(content: Content, state: RunState, event_id: String, draft: Dictionary,
		concentration: Dictionary = {}) -> Array:
	var ev: Dictionary = content.events.get(event_id, {})
	var executor: String = draft.get("character", "")
	var enh: Array = draft.get("enhancements", [])
	var out: Array = []
	for o: Dictionary in ev.get("options", []):
		var req := StatResolver.requirements(state, o)
		var info := {"option": o, "req": req, "blockers": [], "chance": 0, "needs_roll": false,
			"totals": {}, "parts": [], "done": state.is_option_done(event_id, str(o["id"]))}
		info["blockers"] = ConditionChecker.blockers(content, state, o, executor, enh)
		var check: String = o.get("check", "stat")
		if executor != "":
			var r := StatResolver.resolve(content, state, executor, enh, ev, o, concentration)
			info["totals"] = r["totals"]
			info["parts"] = r["parts"]
			if check == "stat" or check == "gate_stat":
				info["chance"] = ChanceCalculator.compute(r["totals"], req)
				info["needs_roll"] = info["chance"] < 100
			elif check == "combat":
				info["chance"] = CombatSession.estimate(content, state, event_id, str(o["id"]), draft)
				info["needs_roll"] = true
				info["combat"] = true
			else:
				info["chance"] = 100
		out.append(info)
	return out


## Можно ли нажать вариант. Возвращает "" или причину.
static func can_resolve(content: Content, state: RunState, event_id: String, option_id: String,
		draft: Dictionary, extras: Dictionary = {}) -> String:
	if state.game_over:
		return "Прохождение окончено"
	if not state.is_event_active(event_id):
		return "Событие не активно"
	var o := content.option(event_id, option_id)
	if o.is_empty():
		return "Нет такого варианта"
	if state.is_option_done(event_id, option_id):
		return "Вариант уже выполнен"
	var executor: String = draft.get("character", "")
	if executor == "" or not state.owns(executor) or not state.is_alive(executor):
		return "Поместите персонажа"
	var enh: Array = draft.get("enhancements", [])
	if enh.size() > 3:
		return "Не больше трёх усилений"
	for e: String in enh:
		if not state.owns(e) or content.card_kind(e) != "enhancement":
			return "Недоступное усиление: %s" % e
	var blockers := ConditionChecker.blockers(content, state, o, executor, enh)
	if not blockers.is_empty():
		return blockers[0]
	var mana_needed := _concentration_total(extras.get("concentration", {})) * CONCENTRATION_COST
	mana_needed += int(o.get("cost", {}).get("mana", 0))
	if mana_needed > int(state.resources.get("mana", 0)):
		return "Не хватает маны"
	for s: String in extras.get("concentration", {}):
		if int(extras["concentration"][s]) > CONCENTRATION_MAX:
			return "Концентрация — не больше двух раз"
	return ""


## Разрешает вариант. Возвращает {"ok", "reason"?, "state": RunState, "result": {...}}.
## extras: {"concentration": {stat: n}, "ward": bool}
static func resolve(content: Content, state_in: RunState, event_id: String, option_id: String,
		draft: Dictionary, extras: Dictionary = {}) -> Dictionary:
	var why := can_resolve(content, state_in, event_id, option_id, draft, extras)
	if why != "":
		return {"ok": false, "reason": why, "state": state_in}
	if str(content.option(event_id, option_id).get("check", "")) == "combat":
		return {"ok": false, "reason": "Этот вариант решается в бою", "state": state_in}
	var state := state_in.copy()
	var rng := RandomNumberGenerator.new()
	rng.seed = state.rng_seed
	rng.state = state.rng_state

	var ev: Dictionary = content.events[event_id]
	var o := content.option(event_id, option_id)
	var executor: String = draft["character"]
	var enh: Array = Array(draft.get("enhancements", [])).duplicate()
	var concentration: Dictionary = extras.get("concentration", {})
	var entries: Array = []

	# --- траты до броска ---
	var conc_cost := _concentration_total(concentration) * CONCENTRATION_COST
	if conc_cost > 0:
		state.resources["mana"] = int(state.resources["mana"]) - conc_cost
		entries.append({"kind": "resource", "text": "◈ мана −%d (Концентрация)" % conc_cost})
	var cost: Dictionary = o.get("cost", {})
	for r: String in cost:
		state.resources[r] = int(state.resources.get(r, 0)) - int(cost[r])
		entries.append({"kind": "resource", "text": "%s −%d" % [EffectApplier.RES_NAMES.get(r, r), int(cost[r])]})

	# --- проверка ---
	var stats := StatResolver.resolve(content, state, executor, enh, ev, o, concentration)
	var req := StatResolver.requirements(state, o)
	var check: String = o.get("check", "stat")
	var chance := 100
	var rolled := false
	var roll := 0
	if check == "stat" or check == "gate_stat":
		chance = ChanceCalculator.compute(stats["totals"], req)
		if chance < 100:
			rolled = true
			roll = rng.randi_range(1, 100)
	var success := (not rolled) or roll <= chance

	# Временные эффекты, сработавшие в этой попытке, расходуются.
	var used: Array = stats["temp_used"]
	used.sort()
	used.reverse()
	for i: int in used:
		var te: Dictionary = state.temp_effects[i]
		te["remaining"] = int(te["remaining"]) - 1
		if int(te["remaining"]) <= 0:
			state.temp_effects.remove_at(i)

	var result := {
		"event_id": event_id, "option_id": option_id, "executor": executor,
		"success": success, "chance": chance, "roll": roll, "rolled": rolled,
		"traumas": [], "death": {}, "wear": [], "loot": {}, "progressed": false,
	}

	var story_scheduled := false
	if success:
		story_scheduled = apply_success(content, state, event_id, option_id, executor, rng, entries, result, true)
	else:
		if o.has("on_failure"):
			entries.append_array(EffectApplier.apply_all(content, state, o["on_failure"], executor, rng))
		var count := int(o.get("failure_traumas", 2 if bool(o.get("danger", ev.get("danger", false))) else 1))
		var pool: String = o.get("trauma_pool", ev.get("trauma_pool", "all"))
		give_traumas(content, state, executor, enh, count, pool, bool(extras.get("ward", false)), rng, result, entries)

	apply_wear(content, state, enh, rng, entries, result)
	return finish_turn(content, state, event_id, option_id, executor, chance, roll, success, story_scheduled, rng, entries, result)


## Успех варианта: эффекты, добыча, закрытие/продвижение события. Возвращает true, если назначен сюжет.
## Общая часть для обычной проверки и для боя.
static func apply_success(content: Content, state: RunState, event_id: String, option_id: String, executor: String,
		rng: RandomNumberGenerator, entries: Array, result: Dictionary, generic_loot: bool) -> bool:
	var ev: Dictionary = content.events[event_id]
	var o := content.option(event_id, option_id)
	entries.append_array(EffectApplier.apply_all(content, state, ev.get("on_success_common", []), executor, rng))
	entries.append_array(EffectApplier.apply_all(content, state, o.get("on_success", []), executor, rng))
	# Добыча: 50% — мана или осколки душ поровну.
	if generic_loot and rng.randi_range(1, 100) <= LOOT_CHANCE:
		var res := "shards" if rng.randi_range(0, 1) == 0 else "mana"
		var story_like: bool = ev.get("type", "") in ["story", "reward"]
		var amount := rng.randi_range(2, 4) if story_like else rng.randi_range(1, 3)
		entries.append_array(EffectApplier.apply(content, state, {"cmd": "adjust_resource", "resource": res, "value": amount}, executor, rng))
		result["loot"] = {"resource": res, "value": amount}
	var etype: String = ev.get("type", "story")
	var progresses := etype == "reward" or (etype == "story" and bool(o.get("story", false)))
	if etype in ["side", "random"] or progresses:
		state.events[event_id]["status"] = "closed"
	else:
		state.events[event_id]["done_options"].append(option_id)
	if progresses:
		result["progressed"] = true
		var immediate := bool(ev.get("next_immediate", false))
		entries.append_array(EventFlow.schedule_story(content, state, str(ev.get("next", "")), immediate, rng))
		result["next_event"] = str(ev.get("next", ""))
	return progresses


## Износ приложенных усилений после события или боя.
static func apply_wear(content: Content, state: RunState, enh: Array, rng: RandomNumberGenerator, entries: Array, result: Dictionary) -> void:
	for card: String in enh:
		if not WearRules.wears(content, state, card) or not state.owns(card):
			continue
		var w := WearRules.roll(state, card, rng)
		w["card"] = card
		result["wear"].append(w)
		if w["broken"]:
			state.collection.erase(card)
			state.wear.erase(card)
			state.note(card, "Раскололась от износа")
			entries.append({"kind": "broken", "text": "%s раскалывается и исчезает" % content.card_name(card), "card": card})
		else:
			state.wear[card] = w["after"]


## Конец хода: журнал, неделя, сохранение RNG.
static func finish_turn(content: Content, state: RunState, event_id: String, option_id: String, executor: String,
		chance: int, roll: int, success: bool, story_scheduled: bool, rng: RandomNumberGenerator, entries: Array,
		result: Dictionary) -> Dictionary:
	var enh_used: Array = Array(state.drafts.get(event_id, {}).get("enhancements", [])).duplicate()
	state.drafts.erase(event_id)
	state.log.append({
		"week": state.week, "event": event_id, "option": option_id, "executor": executor,
		"chance": chance, "roll": roll, "success": success, "enh": enh_used,
	})
	if not state.game_over:
		entries.append_array(EventFlow.advance_week(content, state, rng, story_scheduled))
	state.rng_state = rng.state
	result["entries"] = entries
	result["week"] = state.week
	return {"ok": true, "state": state, "result": result}


static func give_traumas(content: Content, state: RunState, executor: String, enh: Array, count: int,
		pool: String, ward: bool, rng: RandomNumberGenerator, result: Dictionary, entries: Array) -> void:
	var ch: Dictionary = state.character(executor)
	var softened_once := false
	for i in count:
		var traumas: Array = ch["traumas"]
		var tid := TraumaRules.pick(content, pool, traumas, rng)
		if tid != "" and _softens(content, state, executor, enh, softened_once, tid):
			var soft := TraumaRules.soften(content, tid, traumas, rng)
			softened_once = true
			entries.append({"kind": "info", "text": "Травма смягчена: %s → %s" % [content.card_name(tid), content.card_name(soft) if soft != "" else "без травмы"]})
			tid = soft
		if tid != "":
			traumas.append(tid)
			result["traumas"].append(tid)
			state.note(executor, "Травма: %s" % content.card_name(tid))
			entries.append({"kind": "trauma", "text": "%s: %s" % [content.card_name(executor), content.card_name(tid)], "card": tid})
		var n := TraumaRules.counted(traumas)
		var dchance := TraumaRules.death_chance(n)
		if dchance <= 0:
			continue
		if ward and int(state.resources.get("mana", 0)) >= WARD_COST and not bool(result.get("ward_used", false)):
			state.resources["mana"] = int(state.resources["mana"]) - WARD_COST
			result["ward_used"] = true
			entries.append({"kind": "resource", "text": "◈ мана −%d (Оберег)" % WARD_COST})
		if bool(result.get("ward_used", false)):
			dchance = dchance / 2
		var droll := rng.randi_range(1, 100)
		var died := droll <= dchance
		result["death"] = {"chance": dchance, "roll": droll, "died": died}
		if died:
			_kill(content, state, executor, entries)
			return


static func _softens(content: Content, state: RunState, executor: String, enh: Array, softened_once: bool, tid: String) -> bool:
	if content.traumas.get(tid, {}).get("category", "") != "physical":
		return false
	for aid: String in state.character(executor).get("abilities", []):
		if bool(content.abilities.get(aid, {}).get("soften_physical", false)):
			return true
	if softened_once:
		return false
	for card: String in enh:
		if bool(content.enhancements.get(card, {}).get("soften_first_physical", false)):
			return true
	return false


static func _kill(content: Content, state: RunState, cid: String, entries: Array) -> void:
	state.characters[cid]["alive"] = false
	state.collection.erase(cid)
	state.note(cid, "Погиб")
	if state.mode == "missions":
		# новая механика: смерть навсегда, конец — когда героев не осталось (docs/15)
		entries.append({"kind": "death", "text": "%s погибает." % content.card_name(cid), "card": cid})
		if MissionFlow.heroes(content, state).is_empty():
			state.game_over = true
			entries.append({"kind": "death", "text": "Героев не осталось — прохождение окончено."})
	elif cid == DEATH_CHARACTER:
		state.game_over = true
		entries.append({"kind": "death", "text": "Тень угасла. %s погибает — прохождение окончено." % content.card_name(cid), "card": cid})
	else:
		entries.append({"kind": "death", "text": "%s погибает." % content.card_name(cid), "card": cid})


static func _concentration_total(c: Dictionary) -> int:
	var n := 0
	for s: String in c:
		n += int(c[s])
	return n
