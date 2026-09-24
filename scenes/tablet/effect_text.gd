class_name EffectText
extends RefCounted
## Человекочитаемые последствия для строки варианта. Скрытые показываются значками с «?».

const POOL_NAMES := {"all": "любая", "physical": "физ.", "environment": "среда", "mental": "мент."}


static func summarize(c: Content, effects: Array, revealed: bool) -> String:
	if effects.is_empty():
		return "—"
	var parts: Array = []
	for e: Dictionary in effects:
		var t := _one(c, e, revealed)
		if t != "" and not parts.has(t):
			parts.append(t)
	return ", ".join(parts) if not parts.is_empty() else "—"


static func _one(c: Content, e: Dictionary, revealed: bool) -> String:
	var cmd: String = e.get("cmd", "")
	if not revealed:
		match cmd:
			"add_card":
				var k := c.card_kind(str(e["card"]))
				return {"character": "спутник ?", "initiator": "инициатор ?"}.get(k, "карта ?")
			"add_ability": return "способность ?"
			"adjust_resource": return "◈" if e["resource"] == "mana" else "✧"
			"add_temp", "add_perm": return "бонус ?"
			"reveal": return "знание ?"
			"remove_trauma", "clear_traumas": return "лечение"
			"set_flag": return "последствие ?"
			"combat_mod": return "влияет на бой ?"
			_: return ""
	match cmd:
		"add_card": return "▣ " + c.card_name(str(e["card"]))
		"add_ability": return "✦ " + c.card_name(str(e["ability"]))
		"adjust_resource": return "%s %+d" % ["◈" if e["resource"] == "mana" else "✧", int(e["value"])]
		"add_temp":
			var where := ""
			if str(e.get("option_id", "")) != "":
				where = " к сюжетной попытке"
			elif str(e.get("event_id", "")) != "":
				where = " в %s" % str(e["event_id"])
			elif not Array(e.get("tags", [])).is_empty():
				where = " (%s)" % ", ".join(e["tags"])
			else:
				where = " (след.)"
			return "%+d %s%s" % [int(e["value"]), Palette.STAT_SHORT.get(e["stat"], "?"), where]
		"add_perm": return "%+d %s навсегда" % [int(e["value"]), Palette.STAT_SHORT.get(e["stat"], "?")]
		"reveal": return "раскрытие"
		"remove_trauma": return "снять травму"
		"clear_traumas": return "снять травмы"
		"set_flag": return str(e.get("text", "")) if e.has("text") else ""
		"remove_card": return ""
		"text": return str(e["text"])
		"combat_mod": return "меняет бой"
	return ""


static func failure(c: Content, ev: Dictionary, o: Dictionary) -> String:
	if str(o.get("check", "")) == "combat":
		return "травма за каждый проигранный раунд"
	var count := int(o.get("failure_traumas", 2 if bool(o.get("danger", ev.get("danger", false))) else 1))
	if count <= 0:
		return "без травмы"
	var pool: String = o.get("trauma_pool", ev.get("trauma_pool", "all"))
	return "травма ×%d (%s)%s" % [count, POOL_NAMES.get(pool, pool), " · Опасно" if count >= 2 else ""]
