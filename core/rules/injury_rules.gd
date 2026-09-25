class_name InjuryRules
extends RefCounted
## Травмы, износ и гибель героев — общее для этапов миссий и автобоя (docs/15 §14).

const LOOT_CHANCE := 50


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


static func give_traumas(content: Content, state: RunState, executor: String, enh: Array, count: int,
		pool: String, rng: RandomNumberGenerator, result: Dictionary, entries: Array) -> void:
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
		var droll := rng.randi_range(1, 100)
		var died := droll <= dchance
		result["death"] = {"chance": dchance, "roll": droll, "died": died}
		if died:
			kill(content, state, executor, entries)
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


## Гибель навсегда. Конец — когда героев не осталось или погиб герой, без которого не пройти сюжет главы.
static func kill(content: Content, state: RunState, cid: String, entries: Array) -> void:
	state.characters[cid]["alive"] = false
	state.collection.erase(cid)
	state.note(cid, "Погиб")
	entries.append({"kind": "death", "text": "%s погибает." % content.card_name(cid), "card": cid})
	var key := MissionFlow.key_mission_for(content, state, cid)
	if MissionFlow.heroes(content, state).is_empty():
		state.game_over = true
		entries.append({"kind": "death", "text": "Героев не осталось — прохождение окончено."})
	elif key != "":
		state.game_over = true
		entries.append({"kind": "death", "text": "Без героя %s не пройти «%s» — прохождение окончено." % [content.card_name(cid), key]})
