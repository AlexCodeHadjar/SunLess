class_name MemoryRules
extends RefCounted
## Особые навыки карт (docs/16 §9д) — вместо приёмов в бою. У усиления в кармашке ведущего или у способности
## героя есть поле `memory`: {name, cond, text, phase, when, effect, once, wear, support}.
## Навык срабатывает сам, когда выполнено условие — игрок ничего не выбирает, решение — что положить в кармашек.
##
## phase: "round" — перед броском раунда (меняет расчёт силы), "lose" — когда раунд проигран (защита от травмы).
## when (все условия должны выполниться; any_of — хотя бы один вариант):
##   round [номера], after_loss / after_win (исход прошлого раунда), enemy_any / env_any / hero_any [теги],
##   traumas_min n, psyche "panic"|"uplift", enemy_count_max n / enemy_count_min n, intent (у врага есть намерение),
##   chance_below n (шанс раунда без навыков ниже n), enemy_stronger (враг сильнее), sky_any [небо].
## effect: bonus (доля силы), add_tags, take_field_tag, cancel_enemy_tags, double_tags + blocked_by_env,
##   enemy_penalty {tags, value}, cancel_intent, reveal_next, best_stat, self_tags, guard (шанс отвести травму, %),
##   echo_guard (Эхо принимает удар и рассыпается).
## once (по умолчанию true) — раз за бой; wear — износ карты за срабатывание; support — способность работает
## и у союзника в поддержке.


## Источники навыков: кармашек и способности ведущего, способности союзников с support.
static func sources(s: CombatSession) -> Array:
	var out: Array = []
	for card: String in s.enh:
		var m: Dictionary = s.content.enhancements.get(card, {}).get("memory", {})
		if not m.is_empty():
			out.append({"card": card, "owner": s.hero, "def": m})
	for aid: String in s.state.character(s.hero).get("abilities", []):
		var m2: Dictionary = s.content.abilities.get(aid, {}).get("memory", {})
		if not m2.is_empty():
			out.append({"card": aid, "owner": s.hero, "def": m2})
	for ally: String in s.allies:
		for aid2: String in s.state.character(ally).get("abilities", []):
			var m3: Dictionary = s.content.abilities.get(aid2, {}).get("memory", {})
			if not m3.is_empty() and bool(m3.get("support", false)):
				out.append({"card": aid2, "owner": ally, "def": m3})
	return out


static func _any(tags: Array, need: Array) -> bool:
	return need.any(func(t: String) -> bool: return tags.has(t))


## Выполнено ли условие навыка сейчас. base — лениво посчитанный расчёт раунда без навыков.
static func _ok(s: CombatSession, w: Dictionary, owner: String, base: Dictionary) -> bool:
	if w.has("any_of"):
		var hit := false
		for alt: Dictionary in w["any_of"]:
			if _ok(s, alt, owner, base):
				hit = true
				break
		if not hit:
			return false
	if w.has("round") and not Array(w["round"]).any(func(r: Variant) -> bool: return int(r) == s.round_no):   # из JSON — дробные
		return false
	if bool(w.get("after_loss", false)) and s.momentum != "enemy":
		return false
	if bool(w.get("after_win", false)) and s.momentum != "hero":
		return false
	if w.has("enemy_any") and not _any(s._enemy_tags({}), w["enemy_any"]):
		return false
	if w.has("env_any") and not _any(s._env_tags(), w["env_any"]):
		return false
	if w.has("hero_any") and not _any(s._hero_tags({}), w["hero_any"]):
		return false
	if w.has("sky_any") and not Array(w["sky_any"]).has(Atmosphere.sky(s.content, s.state)):
		return false
	if w.has("traumas_min") and TraumaRules.counted(s.state.character(owner).get("traumas", [])) < int(w["traumas_min"]):
		return false
	if w.has("psyche") and PsycheRules.crisis(s.state, owner) != str(w["psyche"]):
		return false
	if w.has("enemy_count_max") and s.enemies.size() > int(w["enemy_count_max"]):
		return false
	if w.has("enemy_count_min") and s.enemies.size() < int(w["enemy_count_min"]):
		return false
	if bool(w.get("intent", false)) and s.intent.is_empty():
		return false
	if w.has("chance_below") or bool(w.get("enemy_stronger", false)):
		if base.is_empty():
			base.merge(s.ledger({}))
		if w.has("chance_below") and int(base["chance"]) >= int(w["chance_below"]):
			return false
		if bool(w.get("enemy_stronger", false)) and float(base["enemy"]) <= float(base["hero"]):
			return false
	return true


## Сработавшие навыки фазы и общий эффект: {effect, fired: [{card, owner, name, cond, text, phase}]}.
## commit = true — навык отмечается использованным и платит износ; false — только посмотреть (прогноз, экран).
static func fire(s: CombatSession, phase: String, commit: bool) -> Dictionary:
	var eff := {}
	var fired: Array = []
	var base := {}
	for src: Dictionary in sources(s):
		var d: Dictionary = src["def"]
		if str(d.get("phase", "round")) != phase:
			continue
		var once := bool(d.get("once", true))
		if once and s.used_memories.has(src["card"]):
			continue
		if not _ok(s, d.get("when", {}), str(src["owner"]), base):
			continue
		_merge(eff, d.get("effect", {}), str(d.get("name", "")), str(src["card"]))
		fired.append({"card": src["card"], "owner": src["owner"], "name": str(d.get("name", "")), "cond": str(d.get("cond", "")),
			"text": str(d.get("text", "")), "phase": phase})
		if commit:
			if once:
				s.used_memories.append(src["card"])
			var wear := int(d.get("wear", 0))
			if wear > 0 and WearRules.wears(s.content, s.state, str(src["card"])):
				s.state.wear[src["card"]] = mini(100, WearRules.current(s.state, str(src["card"])) + wear)
			s.entries.append({"kind": "memory", "card": src["card"], "text": "%s: «%s» — %s" % [s.content.card_name(str(src["card"])), d.get("name", ""), d.get("text", "")]})
	return {"effect": eff, "fired": fired}


static func _merge(eff: Dictionary, e: Dictionary, name: String, card: String) -> void:
	if float(e.get("bonus", 0.0)) != 0.0:
		var steps: Array = eff.get("bonus_steps", [])
		steps.append({"label": "Воспоминание: %s" % name, "pct": float(e["bonus"]), "card": card})
		eff["bonus_steps"] = steps
	for k: String in ["add_tags", "cancel_enemy_tags", "double_tags", "blocked_by_env", "self_tags"]:
		if e.has(k):
			var arr: Array = eff.get(k, [])
			for t: String in e[k]:
				if not arr.has(t):
					arr.append(t)
			eff[k] = arr
	for f: String in ["take_field_tag", "reveal_next", "best_stat"]:
		if bool(e.get(f, false)):
			eff[f] = true
	if bool(e.get("cancel_intent", false)):
		eff["cancel_intent"] = true
		eff["cancel_intent_by"] = name
	if e.has("enemy_penalty"):
		var pens: Array = eff.get("enemy_penalties", [])
		var p: Dictionary = Dictionary(e["enemy_penalty"]).duplicate()
		p["name"] = name
		p["card"] = card
		pens.append(p)
		eff["enemy_penalties"] = pens
	if int(e.get("guard", 0)) > int(eff.get("guard", 0)):
		eff["guard"] = int(e["guard"])
	if bool(e.get("echo_guard", false)):
		eff["echo_guard"] = true
		eff["echo_card"] = card


## Все навыки ведущего и отряда — для экрана боя и планшета: [{card, owner, def, used}].
static func listing(s: CombatSession) -> Array:
	var out: Array = []
	for src: Dictionary in sources(s):
		var r := src.duplicate()
		r["used"] = bool(src["def"].get("once", true)) and s.used_memories.has(src["card"])
		out.append(r)
	return out
