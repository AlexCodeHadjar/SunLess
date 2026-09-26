class_name BondRules
extends RefCounted
## Связки героев (docs/16 §6): пара в одном отряде даёт особый эффект — data/bonds.json.
## effect: reveal (скрытые теги раскрыты), stat {stat, value, tags?} (к проверкам обоих), combat (+доля силы в бою),
## quarrel (шанс ссоры после миссии: −1 доверие). Связка не работает, если доверие пары ниже min_trust.


## Связки, собранные в этом отряде.
static func active(content: Content, state: RunState, heroes: Array) -> Array:
	var out: Array = []
	for bid: String in MissionFlow._sorted(content.bonds):
		var b: Dictionary = content.bonds[bid]
		var pair: Array = b.get("heroes", [])
		if pair.size() != 2 or not heroes.has(pair[0]) or not heroes.has(pair[1]):
			continue
		if not state.is_alive(pair[0]) or not state.is_alive(pair[1]):
			continue
		if TrustRules.value(state, pair[0], pair[1]) < int(b.get("min_trust", -2)):
			continue
		out.append(b)
	return out


static func reveals(content: Content, state: RunState, heroes: Array) -> bool:
	return active(content, state, heroes).any(func(b: Dictionary) -> bool: return bool(b.get("effect", {}).get("reveal", false)))


## Бонус связок к проверке героя cid с тегами tags: [{source, stat, value}].
static func check_parts(content: Content, state: RunState, heroes: Array, cid: String, tags: Array) -> Array:
	var out: Array = []
	for b: Dictionary in active(content, state, heroes):
		if not Array(b["heroes"]).has(cid):
			continue
		var st: Dictionary = b.get("effect", {}).get("stat", {})
		if st.is_empty():
			continue
		var need: Array = st.get("tags", [])
		if not need.is_empty() and not need.any(func(t: String) -> bool: return tags.has(t)):
			continue
		out.append({"source": "Связка: %s" % b.get("name", ""), "stat": str(st["stat"]), "value": int(st["value"])})
	return out


## Прибавка к силе героя в бою от связки с союзником.
static func combat_bonus(content: Content, state: RunState, hero: String, allies: Array) -> Dictionary:
	var best := {"value": 0.0, "name": ""}
	for b: Dictionary in active(content, state, [hero] + allies):
		if not Array(b["heroes"]).has(hero):
			continue
		var v := float(b.get("effect", {}).get("combat", 0.0))
		if v > float(best["value"]):
			best = {"value": v, "name": str(b.get("name", ""))}
	return best


## После миссии: ссоры в связках-соперничествах.
static func quarrels(content: Content, state: RunState, heroes: Array, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for b: Dictionary in active(content, state, heroes):
		var q := float(b.get("effect", {}).get("quarrel", 0.0))
		if q > 0.0 and rng.randf() < q:
			var pair: Array = b["heroes"]
			out.append({"kind": "info", "text": "Ссора в связке «%s»" % b.get("name", "")})
			out.append_array(TrustRules.change(content, state, pair[0], pair[1], -1, "ссора: «%s»" % b.get("name", "")))
	return out
