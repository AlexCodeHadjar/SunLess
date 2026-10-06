class_name SkStatus
extends RefCounted
## Состояния «Схватки» (docs/24 §4.7). Сроки — в своих ходах бойца: убывают в начале его хода.
## Кровотечение и яд складываются (каждое наложение — своя запись), остальные обновляют срок.
## Состояния Darkest Dungeon: bleed, poison, stun, mark, guard (+ guarding у защитника), riposte, stealth,
## buff / debuff {stat, value}. Свои SunLess (Ф2): burn (Горение — урон, снимает скрытность), dodge / block —
## жетоны с зарядами (Уклон: 50% промаха по следующему удару; Панцирь: следующий удар вполовину), taunt (Приманка),
## foresight (Предвидение: союзникам +10 уклонения от этого врага), blind (Ослепление: точность −25), fear (Страх:
## точность −10, в начале хода 50% — шаг назад), sure (верный удар: следующий удар попадает, крит +N), empower
## (следующий удар вдвое), ignite (удары поджигают), steady (не сдвинуть), weak («Слабость после грани»).

const STACKING := ["bleed", "poison", "acid"]
const DOT := ["bleed", "poison", "burn", "grab"]
const CHARGES := ["dodge", "block", "rage"]     # жетоны: не истекают, тратятся (Ярость копится)
const ACID := -0.1            # Разъедание: защита −10% за наложение, до трёх
const RAGE := 0.1             # Ярость: урон +10% за удар, до трёх
const CHARGES_MAX := 3
const STUN_GUARD := 40        # после оглушения: +40% сопротивления оглушению
const BLIND := -25
const FEAR := -10
const NAMES := {"bleed": "Кровотечение", "poison": "Яд", "burn": "Горение", "stun": "Оглушение", "mark": "Метка",
	"guard": "Под защитой", "guarding": "Защищает", "riposte": "Контратака", "stealth": "Скрытность", "buff": "Усиление",
	"debuff": "Ослабление", "weak": "Слабость после грани", "stun_guard": "Стойкость к оглушению", "dodge": "Уклон",
	"block": "Панцирь", "taunt": "Приманка", "foresight": "Предвидение", "blind": "Ослепление", "fear": "Страх",
	"sure": "Верный удар", "empower": "Раскрытый Аспект", "ignite": "Пламя на клинке", "steady": "Не сдвинуть",
	"charm": "Очарование", "grab": "Захват", "whisper": "Кошмарный шёпот", "acid": "Разъедание", "rage": "Ярость"}
const RESIST := {"bleed": "bleed", "poison": "poison", "stun": "stun", "debuff": "debuff", "mark": "debuff", "push": "move",
	"pull": "move", "blind": "debuff", "fear": "debuff", "charm": "debuff", "whisper": "debuff", "grab": "move"}
const BUFFS := ["buff", "riposte", "dodge", "block", "sure", "empower", "ignite", "taunt", "rage"]   # «снять усиления»


## Наложить состояние (уже прошедшее бросок). false — иммунитет.
static func add(f: SkFighter, st: Dictionary) -> bool:
	var t := str(st["type"])
	if f.immune.has(t):
		return false
	if t in STACKING:
		if t == "acid" and f.statuses.filter(func(s: Dictionary) -> bool: return str(s["type"]) == "acid").size() >= 3:
			return false
		f.statuses.append(st.duplicate())
		return true
	for i in f.statuses.size():
		var s: Dictionary = f.statuses[i]
		if str(s["type"]) == t and str(s.get("stat", "")) == str(st.get("stat", "")):
			var keep := st.duplicate()
			if t in CHARGES:
				keep["charges"] = mini(CHARGES_MAX, int(s.get("charges", 0)) + int(st.get("charges", 1)))
			else:
				keep["turns"] = maxi(int(s.get("turns", 0)), int(st.get("turns", 1)))
			f.statuses[i] = keep
			return true
	var nw := st.duplicate()
	if t in CHARGES:
		nw["charges"] = mini(CHARGES_MAX, int(st.get("charges", 1)))
	f.statuses.append(nw)
	return true


static func remove(f: SkFighter, t: String) -> void:
	f.statuses = f.statuses.filter(func(s: Dictionary) -> bool: return str(s["type"]) != t)


## Потратить один заряд жетона (Уклон, Панцирь). false — жетона нет.
static func spend(f: SkFighter, t: String) -> bool:
	for i in f.statuses.size():
		var s: Dictionary = f.statuses[i]
		if str(s["type"]) == t:
			var n := int(s.get("charges", 1)) - 1
			if n <= 0:
				f.statuses.remove_at(i)
			else:
				s["charges"] = n
			return true
	return false


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
		elif t == "blind" and stat == "acc" and not f.tags.has("Слепота"):
			v += BLIND
		elif t == "fear" and stat == "acc":
			v += FEAR
		elif t == "acid" and stat == "prot":
			v += ACID
		elif t == "rage":
			if stat == "dmg":
				v += RAGE * int(s.get("charges", 1))
			elif stat == "prot":
				v -= 0.05 * int(s.get("charges", 1))
	return v


## Начало хода бойца: урон от кровотечения, яда и горения, регенерация, оглушение; сроки убывают (жетоны — нет).
## {dot, regen, stunned}
static func tick(f: SkFighter) -> Dictionary:
	var dot := 0
	var whisper := 0
	for s: Dictionary in f.statuses:
		if str(s["type"]) in DOT:
			dot += int(s.get("power", 1))
		elif str(s["type"]) == "whisper":
			whisper += int(s.get("power", 3))
	var stunned := f.has_status("stun")
	var regen := f.regen if not f.has_status("burn") and not f.has_status("acid") else 0   # огонь и кислота гасят регенерацию
	var keep: Array = []
	for s: Dictionary in f.statuses:
		var t := str(s["type"])
		if t == "stun":
			continue
		if t in CHARGES:
			keep.append(s)
			continue
		var n := int(s.get("turns", 1)) - 1
		if n > 0:
			var s2 := s.duplicate()
			s2["turns"] = n
			keep.append(s2)
	f.statuses = keep
	if stunned:
		add(f, {"type": "stun_guard", "turns": 2})
	return {"dot": dot, "regen": regen, "stunned": stunned, "whisper": whisper}
