class_name SkAI
extends RefCounted
## ИИ «Схватки» (docs/24 §6.3): оценивает каждый доступный навык и цель — ожидаемый урон, эффекты, добивание,
## метки, психика — и выбирает: «Разумный» и боссы — лучшее, звери — случайное из хороших (не хуже половины лучшего).
## Если ударить нечем с этой позиции — шагает к любимым позициям. Тот же ИИ играет за героев у бота и в тестах.

const GOOD_SHARE := 0.5


static func choose(sk: Skirmish, f: SkFighter) -> Dictionary:
	# Эхо при смерти уводят из боя — иначе карта рассыплется
	if f.echo and f.hp * 10 < f.hp_max * 3 and not f.skill("ECHO_RECALL").is_empty():
		return {"skill": "ECHO_RECALL", "target": f.uid, "score": 9.0}
	var opts: Array = []
	var can_hit := false
	for o: Dictionary in sk.options(f):
		var s: Dictionary = o["skill"]
		if str(o["why"]) != "":
			continue
		var kind := str(s.get("kind", ""))
		if kind == "pass" or kind == "step":
			continue
		if str(s.get("side", "")) == "enemy":
			can_hit = true
		for tg: String in o["targets"]:
			var sc := score(sk, f, s, tg)
			if sc > 0.0:
				opts.append({"skill": str(s["id"]), "target": tg, "score": sc})
	if not can_hit:
		var st := _step_toward(sk, f)
		if not st.is_empty():
			return st
	if opts.is_empty():
		return {}
	opts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	if f.smart:
		return opts[0]
	var best := float(opts[0]["score"])
	var good := opts.filter(func(x: Dictionary) -> bool: return float(x["score"]) >= best * GOOD_SHARE)
	return good[sk.rng.randi_range(0, good.size() - 1)]


## Бот отступает, когда на грани половина отряда (один герой — когда он сам на грани): смерть — от жадности.
static func should_retreat(sk: Skirmish) -> bool:
	var hs := sk.heroes_alive()
	var on_edge := hs.filter(func(h: SkFighter) -> bool: return h.edge).size()
	return on_edge > 0 and on_edge * 2 >= hs.size() and sk.retreat_chance() > 0


## Польза навыка s по цели tg (uid или "all").
static func score(sk: Skirmish, f: SkFighter, s: Dictionary, tg: String) -> float:
	var side := str(s.get("side", "enemy"))
	if side == "enemy":
		var list := sk._hit_list(f, s, tg)
		var total := 0.0
		for t: SkFighter in list:
			total += _hostile(sk, f, s, t)
		return total
	if side == "self":
		return _support(sk, f, s, f)
	var sum := 0.0
	for t2: SkFighter in sk._hit_list(f, s, tg):
		sum += _support(sk, f, s, t2)
	return sum


static func _hostile(sk: Skirmish, f: SkFighter, s: Dictionary, t: SkFighter) -> float:
	var pv := SkStrike.preview(sk, f, s, t)
	var p := float(pv["hit"]) / 100.0
	var avg := (float(pv["min"]) + float(pv["max"])) / 2.0
	var v := p * avg * (1.0 + float(pv["crit"]) / 200.0)
	for e: Dictionary in pv["effects"]:
		if bool(e["self"]):
			continue
		var ch := float(e["chance"]) / 100.0 * p
		var src := _effect(s, str(e["type"]))
		match str(e["type"]):
			"bleed", "poison":
				v += ch * float(src.get("power", 1)) * float(src.get("turns", 3))
			"stun":
				v += ch * 4.0
			"push", "pull":
				v += ch * 0.8
			"mark", "debuff":
				v += ch * 1.5
			"blind":
				v += ch * 2.0
			"fear":
				v += ch * 1.5
			"foresight":
				v += ch * (0.3 if t.has_status("foresight") else 1.2)
			"burn":
				v += ch * float(src.get("power", 2)) * float(src.get("turns", 2))
			"remove_buffs":
				v += 1.5 * t.statuses.filter(func(x: Dictionary) -> bool: return SkStatus.BUFFS.has(str(x["type"]))).size()
			"unstealth":
				v += 2.0 if t.has_status("stealth") else 0.0
			"unstealth_all":
				v += 2.0 * sk.living(t.side).filter(func(x: SkFighter) -> bool: return x.has_status("stealth")).size()
			"psyche":
				if t.is_hero():
					var low := 1.0 + (100.0 - float(PsycheRules.psyche(sk.state, t.card))) / 100.0
					v += ch * absf(float(src.get("value", 0))) / 3.0 * low
	if t.corpse:
		return v * 0.25
	if avg > 0.0 and avg * p >= float(t.hp) * 0.8:
		v *= 1.5       # можно добить
	if t.is_hero() and t.edge:
		v *= 2.5 if f.smart else 1.3
	if t.has_status("mark") and f.side == "enemy":
		v *= 1.3
	return v


static func _support(sk: Skirmish, f: SkFighter, s: Dictionary, t: SkFighter) -> float:
	var v := 0.0
	for e: Dictionary in s.get("effects", []):
		var et := str(e["type"])
		match et:
			"heal":
				var miss := t.hp_max - t.hp
				if miss * 10 >= t.hp_max * 3 or t.edge:
					v += minf(float(miss), (float(e.get("min", 2)) + float(e.get("max", 4))) / 2.0) * 1.2 + (6.0 if t.edge else 0.0)
			"buff", "riposte", "stealth", "dodge", "block", "sure", "empower", "ignite":
				v += 0.3 if t.has_status(et) else 2.0
			"taunt":
				v += 1.5 if t.hp * 2 > t.hp_max and not t.has_status("taunt") else 0.1
			"heal_pct":
				var miss2 := t.hp_max - t.hp
				if miss2 * 10 >= t.hp_max * 3 or t.edge:
					v += minf(float(miss2), t.hp_max * float(e.get("value", 0.25))) * 1.2 + (6.0 if t.edge else 0.0)
			"cleanse":
				for ct: String in e.get("types", []):
					v += 2.5 if t.has_status(ct) else 0.0
			"extra_turn":
				v += 3.0
			"summon":
				v += 4.0
			"light_ward":
				v += 1.0 if sk.light in SkStrike.DARK else 0.1
			"swap", "steady":
				v += 0.05
			"guard":
				if t != f:
					v += 2.5 if t.hp * 2 < t.hp_max else 0.6
			"psyche":
				if t.is_hero() and int(e.get("value", 0)) > 0:
					v += float(100 - PsycheRules.psyche(sk.state, t.card)) / 20.0
	return v


static func _effect(s: Dictionary, t: String) -> Dictionary:
	for e: Dictionary in s.get("effects", []):
		if str(e["type"]) == t:
			return e
	return {}


## Шаг к любимой позиции, если ударить неоткуда. Не меняется местами с тем, кто после обмена сам потеряет удар
## (иначе двое без конца толкаются в строю).
static func _step_toward(sk: Skirmish, f: SkFighter) -> Dictionary:
	if f.pref.has(f.pos):
		return {}
	var want := -1 if f.pos > int(f.pref.max()) else 1
	var step := f.skill("STEP")
	if step.is_empty() or sk.usable_why(f, step) != "":
		return {}
	for uid: String in sk.targets(f, step):
		var t := sk.by_uid(uid)
		if t != null and signi(t.pos - f.pos) == want and not _loses_attack(t, f.pos):
			return {"skill": "STEP", "target": uid, "score": 1.0}
	return {}


## Боец t, встав на позицию p, останется без удара, хотя сейчас он у него есть.
static func _loses_attack(t: SkFighter, p: int) -> bool:
	var now := false
	var then := false
	for s: Dictionary in t.skills:
		if str(s.get("side", "")) != "enemy":
			continue
		var fr: Array = s.get("from", [])
		now = now or t.positions().any(func(x: int) -> bool: return fr.has(x))
		then = then or fr.has(p)
	return now and not then
