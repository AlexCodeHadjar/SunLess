class_name SkStrike
extends RefCounted
## Расчёт удара «Схватки» (docs/24 §4.4): шанс попадания, разброс урона, крит, шансы эффектов и строки «почему».
## Прогноз (preview) — без случайности: его показывает подсказка по наведению; бросок (roll) использует его же.

const HIT_MIN := 5
const HIT_MAX := 95
const CRIT_MULT := 1.5
const RANK_UP := 1.25         # старший ранг бьёт сильнее — за каждый ранг разницы
const RANK_DOWN := 0.8        # …и получает меньше урона (вместе ≈ ×1,6, как RANK_STEP)
const PANIC := {"dmg": -0.3, "acc": -10, "dodge": 0}
const FORESIGHT := 10         # Предвидение на враге: союзникам +10 уклонения от его ударов
const DARK := ["dusk", "dark"]
const UPLIFT := {"dmg": 0.25, "acc": 10, "dodge": 10}


## Поправка кризиса психики героя (паника / подъём духа).
static func crisis_mod(sk: Skirmish, f: SkFighter, key: String) -> float:
	if not f.is_hero():
		return 0.0
	match PsycheRules.crisis(sk.state, f.card):
		"panic":
			return float(PANIC.get(key, 0))
		"uplift":
			return float(UPLIFT.get(key, 0))
	return 0.0


static func rank_k(a: SkFighter, t: SkFighter) -> float:
	var d := a.rank - t.rank
	return pow(RANK_UP, maxi(0, d)) * pow(RANK_DOWN, maxi(0, -d))


static func _pct(v: float) -> String:
	return ("+%d%%" if v >= 0 else "−%d%%") % absi(int(round(v * 100.0)))


## Прогноз удара навыком s бойца a по цели t:
## {hit, min, max, crit, effects: [{type, chance, self}], why: [строки]}.
static func preview(sk: Skirmish, a: SkFighter, s: Dictionary, t: SkFighter) -> Dictionary:
	var why: Array = []
	var side := str(s.get("side", "enemy"))
	var hostile := side == "enemy"
	var hit := 100
	if hostile:
		var acc := float(s.get("acc", 85)) + a.acc + SkStatus.mod(a, "acc") + sk.light_mod(a, "acc") + crisis_mod(sk, a, "acc")
		var dod := 0.0
		if not t.corpse:
			dod = t.dodge + SkStatus.mod(t, "dodge") + sk.light_mod(t, "dodge") + crisis_mod(sk, t, "dodge")
			if a.has_status("foresight"):
				dod += FORESIGHT
				why.append("Предвидение: уклонение +%d" % FORESIGHT)
		hit = clampi(int(round(acc - dod)), HIT_MIN, HIT_MAX)
		if a.has_status("sure"):
			hit = 100
			why.append("верный удар")
		if sk.light_mod(a, "acc") > 0:
			why.append("%s: враг точнее +%d" % [sk.light_name(), int(sk.light_mod(a, "acc"))])
		if a.has_status("blind") and not a.tags.has("Слепота"):
			why.append("ослеплён: точность %d" % SkStatus.BLIND)
	var lo := 0
	var hi := 0
	var base: Array = s.get("dmg", a.dmg)
	if hostile and int(base[1]) > 0:
		var k := float(s.get("mult", 1.0)) * a.dmg_mult
		var rk := rank_k(a, t)
		if rk != 1.0:
			why.append("ранг: %s" % _pct(rk - 1.0))
		k *= rk
		var buff := SkStatus.mod(a, "dmg") + sk.light_mod(a, "dmg") + crisis_mod(sk, a, "dmg")
		if buff != 0.0:
			why.append("усиление и обстановка: %s" % _pct(buff))
		k *= maxf(0.1, 1.0 + buff)
		var stealthy := a.has_status("stealth") and s.has("from_stealth")
		if stealthy:
			k *= float(s["from_stealth"].get("mult", 1.0))
			why.append("из тени: %s" % _pct(float(s["from_stealth"].get("mult", 1.0)) - 1.0))
		if s.has("dark_bonus") and sk.light in DARK:
			k *= 1.0 + float(s["dark_bonus"].get("mult", 0.0))
			why.append("в темноте: %s" % _pct(float(s["dark_bonus"].get("mult", 0.0))))
		if a.has_status("empower"):
			k *= 2.0
			why.append("раскрытый Аспект: вдвое")
		var vs: Dictionary = s.get("vs", {})
		for tag: String in vs:
			if t.tags.has(tag):
				k *= float(vs[tag])
				why.append("%s: %s" % [tag, _pct(float(vs[tag]) - 1.0)])
		if t.has_status("mark") and float(s.get("vs_mark", 0.0)) > 0.0:
			k *= 1.0 + float(s["vs_mark"])
			why.append("по Метке: %s" % _pct(float(s["vs_mark"])))
		var prot := 0.0
		if not t.corpse:
			prot = clampf(t.prot + SkStatus.mod(t, "prot"), 0.0, SkBuild.PROT_MAX) * (1.0 - float(s.get("ignore_prot", 0.0)))
			if Array(s.get("ignore_prot_vs", [])).any(func(x: String) -> bool: return t.tags.has(x)):
				prot = 0.0
				why.append("броня не в счёт")
		if prot > 0.0:
			why.append("защита цели: %s" % _pct(-prot))
		k *= 1.0 - prot
		lo = maxi(1, int(floor(float(base[0]) * k)))
		hi = maxi(lo, int(floor(float(base[1]) * k)))
	var crit := 0
	if hi > 0:
		crit = a.crit + int(s.get("crit", 0)) + int(SkStatus.mod(a, "crit")) + int(sk.light_mod(a, "crit"))
		crit += int(a.status("sure").get("crit", 0))
		if s.has("dark_bonus") and sk.light in DARK:
			crit += int(s["dark_bonus"].get("crit", 0))
		if a.has_status("stealth") and s.has("from_stealth"):
			crit = maxi(crit, int(s["from_stealth"].get("crit", 0)))
		crit = clampi(crit, 0, 100)
	var effects: Array = []
	for e: Dictionary in s.get("effects", []):
		var on_self := bool(e.get("self", false))
		var target := a if on_self else t
		var ch := int(e.get("chance", 100))
		var et := str(e["type"])
		if not effect_applies(sk, e, target):
			ch = 0
		elif hostile and not on_self:
			if target.immune.has(et):
				ch = 0
				why.append("%s: не действует" % SkStatus.NAMES.get(et, et))
			else:
				ch -= SkStatus.resist(target, et)
		effects.append({"type": et, "chance": clampi(ch, 0, 100), "self": on_self})
	return {"hit": hit, "min": lo, "max": hi, "crit": crit, "effects": effects, "why": why}


## Условия эффекта: теги цели (if_tag / if_not_tag) и свет (light_only / light_not).
static func effect_applies(sk: Skirmish, e: Dictionary, t: SkFighter) -> bool:
	var need: Array = e.get("if_tag", [])
	if not need.is_empty() and not need.any(func(x: String) -> bool: return t.tags.has(x)):
		return false
	if Array(e.get("if_not_tag", [])).any(func(x: String) -> bool: return t.tags.has(x)):
		return false
	if e.has("light_only") and not Array(e["light_only"]).has(sk.light):
		return false
	if e.has("light_not") and Array(e["light_not"]).has(sk.light):
		return false
	return true


## Бросок удара: {hit: bool, crit: bool, dmg: int, effects: [индексы сработавших эффектов]}.
static func roll(sk: Skirmish, pv: Dictionary) -> Dictionary:
	var out := {"hit": true, "crit": false, "dmg": 0, "effects": []}
	if int(pv["hit"]) < 100 and sk.rng.randi_range(1, 100) > int(pv["hit"]):
		out["hit"] = false
		# промах: эффекты на себя всё равно срабатывают (например, уйти в тень после удара)
		for i in pv["effects"].size():
			if bool(pv["effects"][i]["self"]) and int(pv["effects"][i]["chance"]) > 0:
				out["effects"].append(i)
		return out
	if int(pv["max"]) > 0:
		out["crit"] = sk.rng.randi_range(1, 100) <= int(pv["crit"])
		out["dmg"] = int(floor(int(pv["max"]) * CRIT_MULT)) if out["crit"] else sk.rng.randi_range(int(pv["min"]), int(pv["max"]))
	for i in pv["effects"].size():
		var ch := int(pv["effects"][i]["chance"])
		if ch >= 100 or (ch > 0 and sk.rng.randi_range(1, 100) <= ch):
			out["effects"].append(i)
	return out
