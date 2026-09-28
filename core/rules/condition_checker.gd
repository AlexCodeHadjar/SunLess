class_name ConditionChecker
extends RefCounted
## Жёсткие условия варианта. Невыполненное условие блокирует вариант (замок),
## это не то же самое, что низкий шанс.

const RESOURCE_NAMES := {"shards": "осколков"}


## Возвращает список причин блокировки (пусто — вариант доступен).
## executor может быть "" — тогда условия на исполнителя считаются невыполненными.
static func blockers(content: Content, state: RunState, option: Dictionary, executor: String,
		attached: Array) -> Array[String]:
	var out: Array[String] = []
	for c: Dictionary in option.get("conditions", []):
		var reason := _check(content, state, c, executor, attached)
		if reason != "":
			out.append(reason)
	var cost: Dictionary = option.get("cost", {})
	for r: String in cost:
		if not RESOURCE_NAMES.has(r):
			continue   # жертва карты, психика, грань — проверяются в MissionFlow
		if int(state.resources.get(r, 0)) < int(cost[r]):
			out.append("Нужно: %d %s" % [int(cost[r]), RESOURCE_NAMES.get(r, r)])
	return out


static func _check(content: Content, state: RunState, c: Dictionary, executor: String, attached: Array) -> String:
	match str(c.get("type", "")):
		"in_collection":
			var card: String = c["card"]
			if not state.owns(card):
				return "Нужен: %s в коллекции" % content.card_name(card)
		"not_owned":
			var card2: String = c["card"]
			if state.owns(card2):
				return "Уже есть: %s" % content.card_name(card2)
		"executor_is":
			var ids: Array = c.get("ids", [])
			if not ids.has(executor):
				var names: Array = []
				for i: String in ids:
					names.append(content.card_name(i))
				return "Исполнитель: %s" % " или ".join(names)
		"has_flag":
			if not state.has_flag(str(c["flag"])):
				return str(c.get("text", "Не выполнено условие"))
		"not_flag":
			if state.has_flag(str(c["flag"])):
				return str(c.get("text", "Уже сделано"))
		"owned_count":
			var n := 0
			for card3: String in c.get("cards", []):
				if state.owns(card3):
					n += 1
			if n < int(c.get("min", 1)):
				return str(c.get("text", "Нужно карт: %d" % int(c.get("min", 1))))
		"attached":
			if not attached.has(str(c["card"])):
				return "Приложите: %s" % content.card_name(str(c["card"]))
		"executor_on_edge":
			if executor == "" or not EdgeRules.on_edge(state, executor):
				return str(c.get("text", "Нужен герой на грани"))
		_:
			return "Неизвестное условие: %s" % str(c.get("type", ""))
	return ""
