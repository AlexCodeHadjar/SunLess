class_name InjuryRules
extends RefCounted
## Износ и гибель героев — общее для этапов миссий и автобоя (docs/15 §14). Грань смерти — EdgeRules.

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
