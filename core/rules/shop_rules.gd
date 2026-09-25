class_name ShopRules
extends RefCounted
## Магазины глав (docs/15 §11): отдельная иконка на карте, за осколки душ — карты усилений и персонажей.
## Ассортимент — `slots` карт из `stock`, обновляется раз в `refresh_every` завершённых миссий.
## Выбор ассортимента детерминирован: зерно прохождения + номер обновления.

## Цена по умолчанию, если в stock не задана своя.
const PRICE := {
	"enhancement": {"common": 5, "rare": 9, "epic": 16, "legendary": 28},
	"character": {"common": 8, "rare": 14, "epic": 20, "legendary": 35},
}


## Магазины текущей главы.
static func shops_of(content: Content, state: RunState) -> Array:
	var out: Array = []
	for sid: String in MissionFlow._sorted(content.shops):
		if str(content.shops[sid].get("chapter", "")) == state.chapter:
			out.append(sid)
	return out


## Номер ассортимента: сколько раз магазин уже обновлялся.
static func generation(content: Content, state: RunState, sid: String) -> int:
	return state.completed_missions / maxi(1, int(content.shops[sid].get("refresh_every", 7)))


## Сколько миссий осталось до нового товара.
static func missions_to_refresh(content: Content, state: RunState, sid: String) -> int:
	var every := maxi(1, int(content.shops[sid].get("refresh_every", 7)))
	return every - state.completed_missions % every


static func price_of(content: Content, entry: Dictionary) -> int:
	if entry.has("price"):
		return int(entry["price"])
	var card := str(entry.get("card", ""))
	var kind := content.card_kind(card)
	var d: Dictionary = content.characters.get(card, {}) if kind == "character" else content.enhancements.get(card, {})
	return int(PRICE.get(kind, PRICE["enhancement"]).get(str(d.get("rarity", "common")), 10))


## Можно ли вообще выставить карту: её ещё нет в коллекции, персонаж не погиб.
static func can_offer(content: Content, state: RunState, card: String) -> bool:
	if state.owns(card):
		return false
	if content.card_kind(card) == "character" and state.characters.has(card) and not state.is_alive(card):
		return false
	return true


## Текущий ассортимент; при новом номере обновления перекладывает витрину.
static func ensure(content: Content, state: RunState, sid: String) -> Dictionary:
	var gen := generation(content, state, sid)
	var cur: Dictionary = state.shops.get(sid, {})
	if cur.is_empty() or int(cur.get("gen", -1)) != gen:
		cur = {"gen": gen, "items": roll(content, state, sid, gen), "seen": int(cur.get("seen", -1))}
		state.shops[sid] = cur
	return cur


## Витрина номер gen: не меньше min_characters персонажей (если есть), остальное — случайно из stock.
static func roll(content: Content, state: RunState, sid: String, gen: int) -> Array:
	var sh: Dictionary = content.shops[sid]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%s:%d" % [state.rng_seed, sid, gen])
	var chars: Array = []
	var rest: Array = []
	for entry: Dictionary in sh.get("stock", []):
		var card := str(entry.get("card", ""))
		if not can_offer(content, state, card):
			continue
		if content.card_kind(card) == "character":
			chars.append(entry)
		else:
			rest.append(entry)
	_shuffle(chars, rng)
	_shuffle(rest, rng)
	var slots := int(sh.get("slots", 4))
	var picked: Array = []
	var need_chars := mini(int(sh.get("min_characters", 0)), chars.size())
	for i in need_chars:
		picked.append(chars.pop_front())
	var pool: Array = chars + rest
	_shuffle(pool, rng)
	while picked.size() < slots and not pool.is_empty():
		picked.append(pool.pop_front())
	var items: Array = []
	for entry: Dictionary in picked:
		items.append({"card": str(entry["card"]), "price": price_of(content, entry), "sold": false})
	return items


## Покупка: "" — успех, иначе причина отказа. Записи для тоста — в out.
static func buy(content: Content, state: RunState, sid: String, card: String, out: Array = []) -> String:
	var cur := ensure(content, state, sid)
	for it: Dictionary in cur["items"]:
		if it["card"] != card:
			continue
		if bool(it.get("sold", false)):
			return "Уже продано"
		if not can_offer(content, state, card):
			return "Эта карта уже у вас"
		var shards := int(state.resources.get("shards", 0))
		if shards < int(it["price"]):
			return "Не хватает осколков душ: нужно %d, есть %d" % [int(it["price"]), shards]
		state.resources["shards"] = shards - int(it["price"])
		it["sold"] = true
		out.append_array(EffectApplier.add_card(content, state, card))
		state.log.append({"week": 0, "text": "Куплено: %s за %d ✧" % [content.card_name(card), int(it["price"])]})
		return ""
	return "Этого нет на прилавке"


## Есть ли на витрине то, чего игрок ещё не видел (новый ассортимент).
static func has_news(content: Content, state: RunState, sid: String) -> bool:
	var cur := ensure(content, state, sid)
	return int(cur.get("seen", -1)) != int(cur["gen"])


static func mark_seen(content: Content, state: RunState, sid: String) -> void:
	var cur := ensure(content, state, sid)
	cur["seen"] = int(cur["gen"])


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t
