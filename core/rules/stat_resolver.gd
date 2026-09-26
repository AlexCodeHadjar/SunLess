class_name StatResolver
extends RefCounted
## Итоговые характеристики исполнителя для конкретного варианта:
## база стадии + постоянные + способности + черты + усиления + временные + концентрация − травмы.

const STATS := ChanceCalculator.STATS


## concentration: {"power": n, ...} — купленные за ману +1.
## Возвращает {"base": {}, "totals": {}, "parts": [{source, stat, value}], "temp_used": [индексы temp_effects]}.
static func resolve(content: Content, state: RunState, character_id: String, enhancement_ids: Array,
		event: Dictionary, option: Dictionary, concentration: Dictionary = {}) -> Dictionary:
	var parts: Array = []
	var ch: Dictionary = state.character(character_id)
	var base := {}
	var stage_stats := content.stage_stats(character_id, str(ch.get("stage", "")))
	var perm: Dictionary = ch.get("perm", {})
	for s in STATS:
		base[s] = int(stage_stats.get(s, 0)) + int(perm.get(s, 0))
	var tags := _tags(event, option)

	var cdef: Dictionary = content.characters.get(character_id, {})
	for tr: Dictionary in cdef.get("traits", []):
		_apply_bonuses(parts, str(tr.get("name", "")), tr.get("bonuses", []), tags)

	for aid: String in ch.get("abilities", []):
		var a: Dictionary = content.abilities.get(aid, {})
		_apply_bonuses(parts, str(a.get("name", aid)), a.get("bonuses", []), tags)

	for eid: String in enhancement_ids:
		var e: Dictionary = content.enhancements.get(eid, {})
		_apply_bonuses(parts, str(e.get("name", eid)), e.get("bonuses", []), tags)

	var temp_used: Array = []
	for i in state.temp_effects.size():
		var te: Dictionary = state.temp_effects[i]
		if temp_applies(te, event, option):
			parts.append({"source": str(te.get("label", "Временный эффект")), "stat": te["stat"], "value": int(te["value"])})
			temp_used.append(i)

	for s: String in concentration:
		var n := int(concentration[s])
		if n > 0:
			parts.append({"source": "Концентрация", "stat": s, "value": n})

	# небо над картой (docs/16 §4)
	if state.mode == "missions" and not content.locations.is_empty():
		parts.append_array(Atmosphere.check_parts(content, state, tags))
		# рост тегов героя (docs/16 §8)
		parts.append_array(GrowthRules.check_parts(content, state, character_id, tags, enhancement_ids))

	for tid: String in ch.get("traumas", []):
		var t: Dictionary = content.traumas.get(tid, {})
		var ctx: String = t.get("context_tag", "")
		if ctx != "" and not tags.has(ctx):
			continue
		for s: String in t.get("mods", {}):
			parts.append({"source": str(t.get("name", tid)), "stat": s, "value": int(t["mods"][s])})

	var totals := base.duplicate()
	for p: Dictionary in parts:
		totals[p["stat"]] = int(totals.get(p["stat"], 0)) + int(p["value"])
	return {"base": base, "totals": totals, "parts": parts, "temp_used": temp_used}


static func _tags(event: Dictionary, option: Dictionary) -> Array:
	var tags: Array = Array(event.get("tags", [])).duplicate()
	for t: String in option.get("tags", []):
		if not tags.has(t):
			tags.append(t)
	return tags


static func _apply_bonuses(parts: Array, source: String, bonuses: Array, tags: Array) -> void:
	for b: Dictionary in bonuses:
		var need: Array = b.get("tags", [])
		if not need.is_empty():
			var hit := false
			for t: String in need:
				if tags.has(t):
					hit = true
					break
			if not hit:
				continue
		parts.append({"source": source, "stat": str(b["stat"]), "value": int(b["value"])})


static func temp_applies(te: Dictionary, event: Dictionary, option: Dictionary) -> bool:
	var ev_id: String = te.get("event_id", "")
	if ev_id != "" and ev_id != event.get("id", ""):
		return false
	var op_id: String = te.get("option_id", "")
	if op_id != "" and op_id != option.get("id", ""):
		return false
	var need: Array = te.get("tags", [])
	if need.is_empty():
		return true
	var tags := _tags(event, option)
	for t: String in need:
		if tags.has(t):
			return true
	return false


## Требования варианта с учётом условных модификаторов (req_mods по флагам).
static func requirements(state: RunState, option: Dictionary) -> Dictionary:
	var req := {}
	for s in STATS:
		req[s] = int(option.get("req", {}).get(s, 0))
	for m: Dictionary in option.get("req_mods", []):
		if state.has_flag(str(m.get("flag", ""))):
			var s: String = m["stat"]
			req[s] = maxi(0, int(req[s]) + int(m["delta"]))
	return req
