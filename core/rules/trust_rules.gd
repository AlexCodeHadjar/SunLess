class_name TrustRules
extends RefCounted
## Доверие между героями (docs/16 §5): −5…+5 на пару, симметрично. Растёт от успехов вместе, падает от провалов,
## бегства товарища и ссор. Высокое открывает особые действия и усиливает поддержку в бою,
## низкое — герой отказывается идти в отряд с тем, кому не доверяет.

const MIN := -5
const MAX := 5
const REFUSE_AT := -3     # доверие ≤ −3 — в один отряд не идут
const HIGH := 3           # доверие ≥ 3 — «близкие»: +5% в бою поддержке
const COMBAT_HIGH := 0.05


static func key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


static func value(state: RunState, a: String, b: String) -> int:
	if a == b:
		return 0
	return int(state.trust.get(key(a, b), 0))


## Изменить доверие пары. Возвращает запись для отчёта (или пусто, если не изменилось).
static func change(content: Content, state: RunState, a: String, b: String, delta: int, reason: String) -> Array:
	if a == b or delta == 0:
		return []
	var k := key(a, b)
	var before := int(state.trust.get(k, 0))
	var after := clampi(before + delta, MIN, MAX)
	if after == before:
		return []
	state.trust[k] = after
	state.trust_notes[k] = reason
	return [{"kind": "trust", "delta": after - before, "text": "Доверие %s — %s: %+d (%s)" % [content.card_name(a), content.card_name(b), after - before, reason]}]


## Кто в отряде не пойдёт вместе: "" — все согласны.
static func refusal(content: Content, state: RunState, heroes: Array) -> String:
	for i in heroes.size():
		for j in range(i + 1, heroes.size()):
			if value(state, heroes[i], heroes[j]) <= REFUSE_AT:
				return "%s не пойдёт вместе с %s (доверие %d)" % [content.card_name(heroes[i]), content.card_name(heroes[j]), value(state, heroes[i], heroes[j])]
	return ""


## Лучшее доверие среди пар отряда (для requires_trust без указанной пары).
static func best_pair(state: RunState, heroes: Array) -> int:
	var best := MIN - 1
	for i in heroes.size():
		for j in range(i + 1, heroes.size()):
			best = maxi(best, value(state, heroes[i], heroes[j]))
	return best


## Условие действия {min, pair?}: хватает ли доверия в этом отряде.
static func meets(state: RunState, heroes: Array, need: Dictionary) -> bool:
	var pair: Array = need.get("pair", [])
	if pair.size() == 2:
		return heroes.has(pair[0]) and heroes.has(pair[1]) and value(state, pair[0], pair[1]) >= int(need.get("min", HIGH))
	return best_pair(state, heroes) >= int(need.get("min", HIGH))


## После миссии: успех вместе +1, провал −1 — каждой паре отряда (живым).
static func after_mission(content: Content, state: RunState, heroes: Array, outcome: String, title: String,
		rng: RandomNumberGenerator = null) -> Array:
	var d := 1 if outcome in ["success", "partial"] else (-1 if outcome == "failure" else 0)
	if d == 0:
		return []
	var out: Array = []
	var alive: Array = heroes.filter(func(c: String) -> bool: return state.is_alive(c))
	for i in alive.size():
		for j in range(i + 1, alive.size()):
			var dd := d
			if d > 0 and rng != null:
				# Лжец до костей — доверие растёт медленнее, Честь — быстрее (docs/16 §8)
				var m := GrowthRules.mult(content, state, alive[i], "trust_gain_mult") * GrowthRules.mult(content, state, alive[j], "trust_gain_mult")
				dd = int(floor(m)) + (1 if rng.randf() < m - floor(m) else 0)
			out.append_array(change(content, state, alive[i], alive[j], dd, ("успех вместе: «%s»" if d > 0 else "провал вместе: «%s»") % title))
	return out


## Для планшета героя: [{hero, value, note}] — топ-N положительных и топ-N отрицательных.
static func top(content: Content, state: RunState, cid: String, n: int = 5) -> Dictionary:
	var pos: Array = []
	var neg: Array = []
	for k: String in state.trust:
		var parts := k.split("|")
		if not parts.has(cid):
			continue
		var other := parts[1] if parts[0] == cid else parts[0]
		var v := int(state.trust[k])
		var rec := {"hero": other, "value": v, "note": str(state.trust_notes.get(k, ""))}
		if v > 0:
			pos.append(rec)
		elif v < 0:
			neg.append(rec)
	pos.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["value"]) > int(y["value"]))
	neg.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["value"]) < int(y["value"]))
	return {"positive": pos.slice(0, n), "negative": neg.slice(0, n)}
