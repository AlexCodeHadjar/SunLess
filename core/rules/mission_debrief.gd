class_name MissionDebrief
extends RefCounted
## Разбор после миссии (docs/16 §9): 2–3 строки «что решило исход» с числами, без нагромождения.
## Резолвер кладёт в запись этапа rec["why"]: проверка — {kind: check, stat, have, need, help, hurt};
## бой — {kind: combat, score, links: [{name, value, side}]}. lines() собирает из них строки отчёта.

const MAX_LINES := 3
const STAT_NAMES := {"power": "Сила", "will": "Воля", "cunning": "Хитрость"}


## Почему проверка удалась или нет: самая «узкая» характеристика и главный плюс/минус к ней.
static func check_why(content: Content, state: RunState, m: Dictionary, a: Dictionary, st: Dictionary, heroes: Array, cid: String) -> Dictionary:
	var r := StatResolver.resolve(content, state, cid, MissionFlow.pocket(state, cid), MissionForecast.ctx_event(m), MissionForecast.ctx_option(a, st))
	var totals: Dictionary = r["totals"].duplicate()
	var parts: Array = Array(r["parts"]).duplicate()
	var tags: Array = Array(m.get("context", [])) + Array(st.get("tags", []))
	for p: Dictionary in BondRules.check_parts(content, state, heroes, cid, tags) + PanicRules.check_parts(content, state, cid):
		totals[p["stat"]] = int(totals.get(p["stat"], 0)) + int(p["value"])
		parts.append(p)
	var req: Dictionary = st.get("req", {})
	var worst := ""
	var margin := 999
	for s: String in req:
		if int(req[s]) <= 0:
			continue
		var d := int(totals.get(s, 0)) - int(req[s])
		if d < margin:
			margin = d
			worst = s
	if worst == "":
		return {}
	var help := {}
	var hurt := {}
	for p: Dictionary in parts:
		if str(p["stat"]) != worst:
			continue
		if int(p["value"]) > int(help.get("value", 0)):
			help = {"source": str(p["source"]), "value": int(p["value"])}
		if int(p["value"]) < int(hurt.get("value", 0)):
			hurt = {"source": str(p["source"]), "value": int(p["value"])}
	return {"kind": "check", "stat": worst, "have": int(totals.get(worst, 0)), "need": int(req[worst]), "help": help, "hurt": hurt}


## Почему бой повернулся так: счёт раундов и две самые весомые связи первого раунда.
static func combat_why(rounds: Array, hero_wins: int, enemy_wins: int) -> Dictionary:
	var links: Array = []
	if not rounds.is_empty():
		for l: Dictionary in rounds[0].get("ledger", {}).get("links", []):
			if absf(float(l.get("value", 0.0))) >= 0.05:
				links.append({"name": str(l.get("name", "")), "value": float(l["value"]), "side": str(l.get("side", "hero"))})
	links.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return absf(float(x["value"])) > absf(float(y["value"])))
	return {"kind": "combat", "score": "%d:%d" % [hero_wins, enemy_wins], "links": links.slice(0, 2)}


## Строки разбора: [{text, good}] — сначала то, что подвело.
static func lines(report: Dictionary) -> Array:
	var bad: Array = []
	var good: Array = []
	for rec: Dictionary in report.get("stages", []):
		var w: Dictionary = rec.get("why", {})
		if w.is_empty():
			continue
		var name := str(rec.get("name", ""))
		var ok := str(rec.get("outcome", "")) == "ok"
		if w["kind"] == "check":
			var stat := str(STAT_NAMES.get(w["stat"], w["stat"]))
			var nums := "%d из %d" % [int(w["have"]), int(w["need"])]
			var text := ""
			if not ok:
				text = "«%s»: не хватило: %s %s" % [name, stat, nums]
				if not Dictionary(w["hurt"]).is_empty():
					text += " (%s %+d)" % [w["hurt"]["source"], int(w["hurt"]["value"])]
			elif int(w["have"]) < int(w["need"]):
				text = "«%s»: повезло — %s %s" % [name, stat, nums]
			else:
				text = "«%s»: хватило: %s %s" % [name, stat, nums]
				if not Dictionary(w["help"]).is_empty():
					text += " (%s %+d)" % [w["help"]["source"], int(w["help"]["value"])]
			(good if ok else bad).append({"text": text, "good": ok})
		else:
			var parts: Array = []
			for l: Dictionary in w["links"]:
				var v := float(l["value"])
				parts.append("%s %s%d%%" % [l["name"], "+" if v > 0 else "−", int(round(absf(v) * 100))] + ("" if l["side"] == "hero" else " у врага"))
			var text2 := "«%s»: раунды %s" % [name, w["score"]] + (" — " + ", ".join(parts) if not parts.is_empty() else "")
			(good if ok else bad).append({"text": text2, "good": ok})
	return (bad + good).slice(0, MAX_LINES)
