class_name SkStatus
extends RefCounted
## Состояния «Схватки» (docs/24 §4.7). Сроки — в своих ходах бойца: убывают в начале его хода.
## Кровотечение и яд складываются (каждое наложение — своя запись), остальные обновляют срок.
## Ф1 — состояния Darkest Dungeon: bleed, poison, stun, mark, guard (+ guarding у защитника), riposte, stealth,
## buff / debuff {stat, value}, weak («Слабость после грани»); свои состояния SunLess — фаза 3.

const STACKING := ["bleed", "poison"]
const STUN_GUARD := 40        # после оглушения: +40% сопротивления оглушению
const NAMES := {"bleed": "Кровотечение", "poison": "Яд", "stun": "Оглушение", "mark": "Метка", "guard": "Под защитой",
	"guarding": "Защищает", "riposte": "Контратака", "stealth": "Скрытность", "buff": "Усиление", "debuff": "Ослабление",
	"weak": "Слабость после грани", "stun_guard": "Стойкость к оглушению"}
const RESIST := {"bleed": "bleed", "poison": "poison", "stun": "stun", "debuff": "debuff", "mark": "debuff", "push": "move", "pull": "move"}


## Наложить состояние (уже прошедшее бросок). false — иммунитет.
static func add(f: SkFighter, st: Dictionary) -> bool:
	var t := str(st["type"])
	if f.immune.has(t):
		return false
	if t in STACKING:
		f.statuses.append(st.duplicate())
		return true
	for i in f.statuses.size():
		var s: Dictionary = f.statuses[i]
		if str(s["type"]) == t and str(s.get("stat", "")) == str(st.get("stat", "")):
			var keep := st.duplicate()
			keep["turns"] = maxi(int(s.get("turns", 0)), int(st.get("turns", 1)))
			f.statuses[i] = keep
			return true
	f.statuses.append(st.duplicate())
	return true


static func remove(f: SkFighter, t: String) -> void:
	f.statuses = f.statuses.filter(func(s: Dictionary) -> bool: return str(s["type"]) != t)


## Сопротивление бойца эффекту (%).
static func resist(f: SkFighter, effect_type: String) -> int:
	var key := str(RESIST.get(effect_type, ""))
	if key == "":
		return 0
	var r := int(f.res.get(key, 0))
	if effect_type == "stun" and f.has_status("stun_guard"):
		r += STUN_GUARD
	return r


## Сумма усилений и ослаблений параметра: dmg, acc, dodge, speed, prot, crit.
static func mod(f: SkFighter, stat: String) -> float:
	var v := 0.0
	for s: Dictionary in f.statuses:
		var t := str(s["type"])
		if (t == "buff" or t == "debuff") and str(s.get("stat", "")) == stat:
			v += float(s.get("value", 0))
		elif t == "weak":
			if stat == "dmg":
				v -= 0.15
			elif stat == "speed":
				v -= 2
	return v


## Начало хода бойца: урон от кровотечения и яда, регенерация, оглушение; сроки убывают.
## {dot, regen, stunned}
static func tick(f: SkFighter) -> Dictionary:
	var dot := 0
	for s: Dictionary in f.statuses:
		if str(s["type"]) in STACKING:
			dot += int(s.get("power", 1))
	var stunned := f.has_status("stun")
	var keep: Array = []
	for s: Dictionary in f.statuses:
		var t := str(s["type"])
		if t == "stun":
			continue
		var n := int(s.get("turns", 1)) - 1
		if n > 0:
			var s2 := s.duplicate()
			s2["turns"] = n
			keep.append(s2)
	f.statuses = keep
	if stunned:
		add(f, {"type": "stun_guard", "turns": 2})
	return {"dot": dot, "regen": f.regen, "stunned": stunned}
