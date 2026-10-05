class_name StartRules
extends RefCounted
## Старт с Берега — «разбитое стекло» (docs/16 §11.5; решение владельца 05.10: выбор доступен сразу при новой игре).
## Три осколка — Санни / Нефис / Касси. Игра начинается с Забытого Берега; Санни всегда в отряде (он — Спящий, уже с
## Тенью: стадия sleeper и способности Кошмара). Выбор меняет спутников, стартовые карты, осколки и одну особенность:
## Нефис — высокое доверие пары; Касси — скрытые теги видны сразу. Остальные герои приходят по сюжету (SH22).
## Данные — data/starts.json {list: [{id, hero, name, title, text, heroes, cards, shards, trust{пара: значение}, reveal}]}.
## Сложность словами не подписывается (решение владельца).


static func list(content: Content) -> Array:
	return Array(content.starts.get("list", []))


static func get_start(content: Content, id: String) -> Dictionary:
	for s: Dictionary in list(content):
		if str(s.get("id", "")) == id:
			return s
	return {}


## Новое прохождение с выбранным стартом (Берег).
static func new_run(content: Content, seed_value: int, start_id: String) -> RunState:
	var st := get_start(content, start_id)
	var s := MissionFlow.new_run(content, seed_value, "shore")
	# Санни после Первого Кошмара и Академии: Спящий, Тень с ним
	s.character("P01")["stage"] = "sleeper"
	for ab: String in ["A01", "A06"]:
		EffectApplier.apply(content, s, {"cmd": "add_ability", "character": "P01", "ability": ab}, "P01", RandomNumberGenerator.new())
	for cid: String in st.get("heroes", []):
		EffectApplier.add_card(content, s, cid)
	for card: String in st.get("cards", []):
		EffectApplier.add_card(content, s, card)
	s.resources["shards"] = int(st.get("shards", s.resources.get("shards", 10)))
	var trust: Dictionary = st.get("trust", {})
	for pair: String in trust:
		var ab2 := pair.split("+")
		TrustRules.change(content, s, ab2[0], ab2[1], int(trust[pair]), "старт")
	s.flags["start"] = start_id
	return s


## Старт открывает скрытые теги событий (Касси).
static func reveals(state: RunState, content: Content) -> bool:
	return bool(get_start(content, str(state.flags.get("start", ""))).get("reveal", false))
