class_name WearRules
extends RefCounted
## Износ усилений: старт 1%, +5% после каждого использования; поломка = уничтожение.

const START := 1
const STEP := 5


## Изнашивается ли карта сейчас (знания, Эхо и исключения по арке — нет).
static func wears(content: Content, state: RunState, card_id: String) -> bool:
	var e: Dictionary = content.enhancements.get(card_id, {})
	if e.is_empty() or not bool(e.get("wears", true)):
		return false
	var exempt: Array = e.get("wear_exempt_arcs", [])
	return not exempt.has(state.arc)


static func current(state: RunState, card_id: String) -> int:
	return int(state.wear.get(card_id, START))


## Бросок после события. Возвращает {"broken": bool, "before": int, "after": int, "roll": int}.
static func roll(state: RunState, card_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var before := current(state, card_id)
	var r := rng.randi_range(1, 100)
	if r <= before:
		return {"broken": true, "before": before, "after": before, "roll": r}
	var after := mini(100, before + STEP)
	return {"broken": false, "before": before, "after": after, "roll": r}
