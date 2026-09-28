class_name EdgeRules
extends RefCounted
## Грань смерти (docs/16 §9е, вместо травм; по мотивам Darkest Dungeon).
## Проигранный бой или проваленный этап ставит героя «на грань» (метка на карте).
## Поражение на грани — бросок смерти (DEATH %). Лагерь или удачная миссия снимают грань. Смерть — навсегда.
##
## Что смягчает: усиление с edge_shield в кармашке — первое поражение события не ставит на грань;
## способность edge_soft — шанс смерти вдвое ниже; «Стойкость» — −10; рост тегов edge_avoid (шанс не упасть на грань),
## death_save (один раз пережить бросок). Навыки карт фазы «lose» (guard, echo_guard) — отводят поражение в бою.

const DEATH := 35             # шанс смерти при поражении на грани, %
const DEATH_MIN := 5
const TAG_DEATH := {"Стойкость": -10, "Хрупкая психика": 5}
const COMBAT_PENALTY := 0.10  # в бою герой на грани слабее на 10%


static func on_edge(state: RunState, cid: String) -> bool:
	return bool(state.character(cid).get("edge", false))


## Шанс смерти, если герой на грани проиграет сейчас (0 — не на грани).
static func death_chance(content: Content, state: RunState, cid: String, extra: int = 0) -> int:
	var d := DEATH + extra
	var tags := MissionFlow.hero_tags(content, state, cid)
	for t: String in TAG_DEATH:
		if tags.has(t):
			d += int(TAG_DEATH[t])
	for aid: String in state.character(cid).get("abilities", []):
		if bool(content.abilities.get(aid, {}).get("edge_soft", false)):
			d = int(d / 2.0)
	return clampi(d, DEATH_MIN, 100)


## Шанс смерти для показа на карте героя: сколько будет при следующем поражении (0 — пока не на грани).
static func shown_death(content: Content, state: RunState, cid: String) -> int:
	return death_chance(content, state, cid) if on_edge(state, cid) else 0


## Поражение героя: не на грани — встаёт на грань; на грани — бросок смерти.
## pocket — усиления при нём (edge_shield), shielded — уже сработавший щит события (Dictionary, общий на событие),
## extra — прибавка к шансу смерти (жестокий удар врага). Пишет в result: edge [cid], death {chance, roll, died}.
static func defeat(content: Content, state: RunState, cid: String, pocket: Array, rng: RandomNumberGenerator,
		result: Dictionary, entries: Array, shielded: Dictionary = {}, extra: int = 0) -> void:
	if not state.is_alive(cid):
		return
	var ch: Dictionary = state.character(cid)
	var avoid := GrowthRules.total(content, state, cid, "edge_avoid")
	if not on_edge(state, cid):
		if not bool(shielded.get(cid, false)):
			for card: String in pocket:
				if bool(content.enhancements.get(card, {}).get("edge_shield", false)):
					shielded[cid] = true
					entries.append({"kind": "info", "card": card, "text": "%s принимает удар на себя — %s не на грани" % [content.card_name(card), content.card_name(cid)]})
					return
		if avoid > 0.0 and rng.randf() < avoid:
			entries.append({"kind": "info", "text": "%s выдерживает — на грань не падает" % content.card_name(cid)})
			return
		ch["edge"] = true
		state.note(cid, "На грани")
		var arr: Array = result.get("edge", [])
		arr.append(cid)
		result["edge"] = arr
		entries.append({"kind": "edge", "card": cid, "text": "%s — на грани смерти. Следующее поражение может стать последним (%d%%)" % [content.card_name(cid), death_chance(content, state, cid)]})
		return
	var dchance := death_chance(content, state, cid, extra)
	var droll := rng.randi_range(1, 100)
	var died := droll <= dchance
	if died and GrowthRules.has(content, state, cid, "death_save") and not bool(ch.get("death_saved", false)):
		ch["death_saved"] = true
		died = false
		entries.append({"kind": "growth", "card": cid, "text": "%s должен был погибнуть — но выстоял (один раз)" % content.card_name(cid)})
	result["death"] = {"chance": dchance, "roll": droll, "died": died, "hero": cid}
	if died:
		InjuryRules.kill(content, state, cid, entries)
	else:
		entries.append({"kind": "edge", "card": cid, "text": "%s на грани — и выживает (бросок %d против %d%%)" % [content.card_name(cid), droll, dchance]})


## Снять грань: лагерь, удачная миссия, лечение по сюжету.
static func recover(content: Content, state: RunState, cid: String, why: String, entries: Array) -> void:
	if not state.is_alive(cid) or not on_edge(state, cid):
		return
	state.character(cid)["edge"] = false
	state.note(cid, "Отошёл от грани: %s" % why)
	entries.append({"kind": "recover", "card": cid, "text": "%s отходит от грани — %s" % [content.card_name(cid), why]})
