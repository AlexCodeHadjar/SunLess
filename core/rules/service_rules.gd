class_name ServiceRules
extends RefCounted
## Услуги торговца (docs/16 §9): лечение травмы, заточка усиления, снятие износа — за осколки душ.
## Какие услуги у какого торговца — shops.json `services: ["heal", "sharpen", "unwear"]`.
## Заточка: +1 к первому бонусу усиления в проверках до конца главы (state.sharpened[card] = глава).

const HEAL_PRICE := {"light": 5, "heavy": 10, "critical": 20}
const SHARPEN_PRICE := 8
const UNWEAR_PRICE := 3
const NAMES := {"heal": "Лечение", "sharpen": "Заточка", "unwear": "Починка"}


static func offers(content: Content, sid: String, kind: String) -> bool:
	return Array(content.shops.get(sid, {}).get("services", [])).has(kind)


static func heal_price(content: Content, tid: String) -> int:
	return int(HEAL_PRICE.get(str(content.traumas.get(tid, {}).get("severity", "light")), 5))


static func sharpened(state: RunState, card: String) -> bool:
	return str(state.sharpened.get(card, "")) == state.chapter


## Можно ли заточить: своё усиление с бонусами к характеристикам, ещё не заточенное в этой главе.
static func can_sharpen(content: Content, state: RunState, card: String) -> bool:
	return state.owns(card) and not Array(content.enhancements.get(card, {}).get("bonuses", [])).is_empty() and not sharpened(state, card)


## Прибавка заточки к проверке: [{source, stat, value}] (с условием по тегам первого бонуса).
static func check_parts(content: Content, state: RunState, card: String, tags: Array) -> Array:
	if not sharpened(state, card):
		return []
	var bon: Array = content.enhancements.get(card, {}).get("bonuses", [])
	if bon.is_empty():
		return []
	var need: Array = bon[0].get("tags", [])
	if not need.is_empty() and not need.any(func(t: String) -> bool: return tags.has(t)):
		return []
	return [{"source": "Заточка: %s" % content.card_name(card), "stat": str(bon[0]["stat"]), "value": 1}]


static func _pay(state: RunState, price: int) -> String:
	var shards := int(state.resources.get("shards", 0))
	if shards < price:
		return "Не хватает осколков душ: нужно %d, есть %d" % [price, shards]
	state.resources["shards"] = shards - price
	return ""


## Выполнить услугу. kind: heal (target = герой, extra = травма), sharpen / unwear (target = усиление). "" — успех.
static func perform(content: Content, state: RunState, sid: String, kind: String, target: String, extra: String = "") -> String:
	if not offers(content, sid, kind):
		return "Здесь так не умеют"
	match kind:
		"heal":
			if not state.is_alive(target):
				return "Некого лечить"
			if MissionFlow.on_mission(state, target):
				return "%s на миссии" % content.card_name(target)
			var tr: Array = state.character(target).get("traumas", [])
			if not tr.has(extra):
				return "Такой травмы нет"
			var err := _pay(state, heal_price(content, extra))
			if err != "":
				return err
			tr.erase(extra)
			state.note(target, "Вылечено: %s" % content.card_name(extra))
		"sharpen":
			if not can_sharpen(content, state, target):
				return "Это не заточить"
			var err2 := _pay(state, SHARPEN_PRICE)
			if err2 != "":
				return err2
			state.sharpened[target] = state.chapter
		"unwear":
			if not state.owns(target) or WearRules.current(state, target) <= WearRules.START:
				return "Чинить нечего"
			var err3 := _pay(state, UNWEAR_PRICE)
			if err3 != "":
				return err3
			state.wear[target] = WearRules.START
		_:
			return "Нет такой услуги"
	state.log.append({"week": 0, "text": "%s: %s" % [NAMES.get(kind, kind), content.card_name(extra if kind == "heal" else target)]})
	return ""
