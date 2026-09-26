class_name GrowthRules
extends RefCounted
## Рост героев по тегам (docs/16 §8): тег «участвовал» в миссии — копит опыт (characters[cid].tag_xp).
## 3 опыта — «Опытный»: +1 к характеристике тега в его проверках (или +3% в бою, если тег боевой).
## 6 опыта — развитие: эволюция (80%) или мутация (20%) из data/tag_growth.json; итог — characters[cid].growth[tag].
## Эффекты развития — словарь ключей, их читают правила: check, check_night, item_bonus, combat, combat_night,
## combat_day, combat_round1, combat_round3, reveal, panic_cap, panic_immune, panic_no_decay, panic_mission,
## panic_threat_immune, brave, flees_on_fail, trust_gain_mult, trust_after(+unless), no_bonds, trauma_avoid,
## trauma_avoid_checks, death_save, heal_ally, wear_mult, rest_add, self_trauma, add_tag, remove_tag.

const VETERAN := 3.0
const EVOLVE := 6.0
const MUTATION := 0.20
const VET_COMBAT := 0.03
const XP_OK := 1.0
const XP_PARTIAL := 0.5
const XP_ANY := 0.5        # «any»: тег растёт от любой удачной миссии, медленнее
const BRAVE := 3


static func xp(state: RunState, cid: String, tag: String) -> float:
	return float(state.character(cid).get("tag_xp", {}).get(tag, 0.0))


## "" | "vet" | "evo" | "mut"
static func stage(state: RunState, cid: String, tag: String) -> String:
	var g := str(state.character(cid).get("growth", {}).get(tag, ""))
	if g != "":
		return g
	return "vet" if xp(state, cid, tag) >= VETERAN else ""


## Описание развития тега {name, text, ...эффекты} или пусто.
static func grown(content: Content, state: RunState, cid: String, tag: String) -> Dictionary:
	var g := str(state.character(cid).get("growth", {}).get(tag, ""))
	if g == "":
		return {}
	return content.tag_growth.get(tag, {}).get(g, {})


## Все эффекты развитий героя.
static func effects(content: Content, state: RunState, cid: String) -> Array:
	var out: Array = []
	for tag: String in state.character(cid).get("growth", {}):
		var e := grown(content, state, cid, tag)
		if not e.is_empty():
			out.append(e)
	return out


static func has(content: Content, state: RunState, cid: String, key: String) -> bool:
	return effects(content, state, cid).any(func(e: Dictionary) -> bool: return bool(e.get(key, false)))


static func total(content: Content, state: RunState, cid: String, key: String) -> float:
	var v := 0.0
	for e: Dictionary in effects(content, state, cid):
		v += float(e.get(key, 0.0))
	return v


## Множитель (произведение) — для *_mult.
static func mult(content: Content, state: RunState, cid: String, key: String) -> float:
	var v := 1.0
	for e: Dictionary in effects(content, state, cid):
		if e.has(key):
			v *= float(e[key])
	return v


## Наименьший потолок паники (или MAX).
static func panic_cap(content: Content, state: RunState, cid: String) -> int:
	var cap := PanicRules.MAX
	for e: Dictionary in effects(content, state, cid):
		if e.has("panic_cap"):
			cap = mini(cap, int(e["panic_cap"]))
	return cap


## Изменения тегов героя от развития: {add: [], remove: []}.
static func tag_changes(content: Content, state: RunState, cid: String) -> Dictionary:
	var out := {"add": [], "remove": []}
	for e: Dictionary in effects(content, state, cid):
		if str(e.get("add_tag", "")) != "":
			out["add"].append(str(e["add_tag"]))
		if str(e.get("remove_tag", "")) != "":
			out["remove"].append(str(e["remove_tag"]))
	return out


static func reveals(content: Content, state: RunState, heroes: Array) -> bool:
	return heroes.any(func(c: String) -> bool: return state.is_alive(c) and has(content, state, c, "reveal"))


# --- проверки и бой -----------------------------------------------------------------

static func _night(content: Content, state: RunState) -> bool:
	return Atmosphere.sky(content, state) != "day"


static func _match(need: Array, tags: Array) -> bool:
	return need.is_empty() or need.any(func(t: String) -> bool: return tags.has(t))


## Прибавки к проверке: опыт тегов, развитие, предметы, храбрость. tags — теги проверки (id контекста).
static func check_parts(content: Content, state: RunState, cid: String, tags: Array, pocket: Array) -> Array:
	var out: Array = []
	var ch := state.character(cid)
	for tag: String in ch.get("tag_xp", {}):
		var d: Dictionary = content.tag_growth.get(tag, {})
		var ct: Array = d.get("check_tags", [])
		if xp(state, cid, tag) >= VETERAN and not ct.is_empty() and _match(ct, tags):
			out.append({"source": "Опытный: %s" % tag, "stat": str(d.get("stat", "cunning")), "value": 1})
	var night := _night(content, state)
	for e: Dictionary in effects(content, state, cid):
		var name := str(e.get("name", ""))
		for b: Dictionary in Array(e.get("check", [])) + (Array(e.get("check_night", [])) if night else []):
			if _match(b.get("tags", []), tags):
				out.append({"source": name, "stat": str(b["stat"]), "value": int(b["value"])})
		var ib := int(e.get("item_bonus", 0))
		if ib != 0:
			for card: String in pocket:
				var bon: Array = content.enhancements.get(card, {}).get("bonuses", [])
				if not bon.is_empty() and _match(bon[0].get("tags", []), tags):
					out.append({"source": "%s: %s" % [name, content.card_name(card)], "stat": str(bon[0]["stat"]), "value": ib})
		if bool(e.get("brave", false)) and PanicRules.value(state, cid) >= PanicRules.REACT:
			for s: String in ["power", "will", "cunning"]:
				out.append({"source": name, "stat": s, "value": BRAVE})
	return out


## Шаги боя от роста героя: [{label, pct}].
static func combat_steps(content: Content, state: RunState, hero: String, round_no: int) -> Array:
	var out: Array = []
	var own := MissionFlow.hero_tags(content, state, hero)
	var vet := 0.0
	for tag: String in state.character(hero).get("tag_xp", {}):
		var d: Dictionary = content.tag_growth.get(tag, {})
		if own.has(tag) and xp(state, hero, tag) >= VETERAN and Array(d.get("check_tags", [])).is_empty():
			vet += VET_COMBAT
	if vet > 0.0:
		out.append({"label": "Опыт тегов", "pct": vet})
	var night := _night(content, state)
	for e: Dictionary in effects(content, state, hero):
		var v := float(e.get("combat", 0.0))
		v += float(e.get("combat_night", 0.0)) if night else float(e.get("combat_day", 0.0))
		if round_no == 1:
			v += float(e.get("combat_round1", 0.0))
		elif round_no == 3:
			v += float(e.get("combat_round3", 0.0))
		if absf(v) > 0.0001:
			out.append({"label": str(e.get("name", "")), "pct": v})
	return out


# --- опыт за миссию ------------------------------------------------------------------

## Отметить участие тегов героя (в run["tag_xp"] — лучшее за миссию).
static func mark(run: Dictionary, cid: String, tag: String, amount: float) -> void:
	if amount <= 0.0:
		return
	var per: Dictionary = run.get("tag_xp", {})
	var h: Dictionary = per.get(cid, {})
	h[tag] = maxf(float(h.get(tag, 0.0)), amount)
	per[cid] = h
	run["tag_xp"] = per


static func _grows(content: Content, tag: String, how: String) -> bool:
	return Array(content.tag_growth.get(tag, {}).get("grow", [])).has(how)


## Этап-проверка: теги исполнителя, чьи проверки совпали с тегами этапа.
static func mark_check(content: Content, state: RunState, run: Dictionary, cid: String, tags: Array, outcome: String) -> void:
	var amount: float = {"ok": XP_OK, "partial": XP_PARTIAL}.get(outcome, 0.0)
	for tag: String in MissionFlow.hero_tags(content, state, cid):
		if _grows(content, tag, "check") and _match(content.tag_growth[tag].get("check_tags", []), tags):
			mark(run, cid, tag, amount)


## Бой: теги участников, сработавшие в связях на стороне героя.
static func mark_combat(content: Content, state: RunState, run: Dictionary, fighters: Array, rounds: Array, won: bool) -> void:
	var fired := {}
	for r: Dictionary in rounds:
		for l: Dictionary in r.get("ledger", {}).get("links", []):
			if str(l.get("side", "hero")) == "hero" and float(l.get("value", 0.0)) >= 0.0:
				for t: String in l.get("tags", []):
					fired[t] = true
	var amount := XP_OK if won else XP_PARTIAL * 0.5
	for cid: String in fighters:
		for tag: String in MissionFlow.hero_tags(content, state, cid):
			if fired.has(tag) and _grows(content, tag, "combat"):
				mark(run, cid, tag, amount)


## Паника: теги характера растут, когда герой прошёл этап в панике.
static func mark_panic(content: Content, state: RunState, run: Dictionary, cid: String) -> void:
	if PanicRules.value(state, cid) < PanicRules.REACT:
		return
	for tag: String in MissionFlow.hero_tags(content, state, cid):
		if _grows(content, tag, "panic"):
			mark(run, cid, tag, XP_OK)


## Итог миссии: «any» за удачу, начисление, «Опытный» и развитие. Возвращает записи отчёта.
static func apply(content: Content, state: RunState, run: Dictionary, heroes: Array, outcome: String, rng: RandomNumberGenerator) -> Array:
	var entries: Array = []
	if outcome in ["success", "partial"]:
		for cid: String in heroes:
			if state.is_alive(cid):
				for tag: String in MissionFlow.hero_tags(content, state, cid):
					if _grows(content, tag, "any"):
						mark(run, cid, tag, XP_ANY if outcome == "success" else XP_ANY * 0.5)
	var per: Dictionary = run.get("tag_xp", {})
	for cid: String in MissionFlow._sorted(per):
		if not state.is_alive(cid):
			continue
		var ch := state.character(cid)
		var bag: Dictionary = ch.get("tag_xp", {})
		var growth: Dictionary = ch.get("growth", {})
		for tag: String in MissionFlow._sorted(per[cid]):
			var before := float(bag.get(tag, 0.0))
			var after := before + float(per[cid][tag])
			bag[tag] = after
			if before < VETERAN and after >= VETERAN:
				entries.append({"kind": "growth", "card": cid, "text": "%s: опытный — «%s»" % [content.card_name(cid), tag]})
			if after >= EVOLVE and not growth.has(tag) and content.tag_growth.has(tag):
				var kind := "mut" if rng.randf() < MUTATION else "evo"
				growth[tag] = kind
				var e: Dictionary = content.tag_growth[tag][kind]
				entries.append({"kind": "growth", "card": cid, "mutation": kind == "mut",
					"text": "%s: «%s» %s — %s (%s)" % [content.card_name(cid), tag, "мутирует" if kind == "mut" else "развивается",
						e.get("name", ""), e.get("text", "")]})
				state.note(cid, "%s: %s" % ["Мутация" if kind == "mut" else "Развитие", e.get("name", "")])
				var st := str(e.get("self_trauma", ""))
				if st != "" and not Array(ch["traumas"]).has(st):
					ch["traumas"].append(st)
					entries.append({"kind": "trauma", "card": st, "text": "%s: %s" % [content.card_name(cid), content.card_name(st)]})
		ch["tag_xp"] = bag
		ch["growth"] = growth
	return entries


## После миссии: лечение союзника пламенем, недоверие от мутаций. Возвращает записи отчёта.
static func after_mission(content: Content, state: RunState, heroes: Array, outcome: String, rng: RandomNumberGenerator) -> Array:
	var entries: Array = []
	var alive: Array = heroes.filter(func(c: String) -> bool: return state.is_alive(c))
	for cid: String in alive:
		for e: Dictionary in effects(content, state, cid):
			var heal := float(e.get("heal_ally", 0.0))
			if heal > 0.0 and rng.randf() < heal:
				for other: String in alive:
					var tr: Array = state.character(other).get("traumas", [])
					if other != cid and not tr.is_empty():
						var tid: String = tr.pop_back()
						entries.append({"kind": "card", "card": other, "text": "%s: «%s» снимает травму «%s» у %s" % [
							content.card_name(cid), e.get("name", ""), content.card_name(tid), content.card_name(other)]})
						break
			var ta := int(e.get("trust_after", 0))
			if ta != 0 and outcome != "retreat":
				var unless := str(e.get("trust_after_unless", ""))
				for other: String in alive:
					if other != cid and (unless == "" or not MissionFlow.hero_tags(content, state, other).has(unless)):
						entries.append_array(TrustRules.change(content, state, cid, other, ta, str(e.get("name", ""))))
	return entries
