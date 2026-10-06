class_name SkBuild
extends RefCounted
## Бойцы «Схватки» из данных (docs/24 §4.5, §6.1): параметры героя — из Силы, Воли и Хитрости (лист героя:
## стадия, ядро души, способности, кармашек), теги — свойства (data/combat/skirmish.json → tag_props);
## враг — тип (обычный / элита / босс), класс существа, ранг, теги, природное оружие, сила этапа.

const HP_BASE := 12
const HP_POWER := 2
const HP_WILL := 1
const ACC_STEP := 2           # точность: 2 × (Хитрость − 5)
const DODGE_BASE := 5         # уклонение: 5 + 2 × Хитрость
const DODGE_STEP := 2
const CRIT_BASE := 2          # крит: 2 + Хитрость, %
const DMG_STEP := 0.06        # урон: × (1 + 0,06 × (Сила − 5))
const RES_BASE := 20          # сопротивления: 20 + 4 × (Воля − 5), %
const RES_STEP := 4
const RES_KEYS := ["bleed", "poison", "stun", "move", "debuff"]
const PROT_MAX := 0.8
const CLASS_HP := 0.5          # класс существа: здоровье × (1 + (множитель − 1) × 0,5)
const CLASS_DMG := 0.35        # …урон × (1 + (множитель − 1) × 0,35)


static func _data(content: Content) -> Dictionary:
	return content.skirmish


## Навык из данных; позиции from / to — целые (JSON даёт дробные), копия кэшируется в content.memo.
static func skill(content: Content, id: String) -> Dictionary:
	var key := "sk_skill_" + id
	if content.memo.has(key):
		return content.memo[key]
	var s: Dictionary = _data(content).get("skills", {}).get(id, {}).duplicate(true)
	for k: String in ["from", "to"]:
		if s.has(k):
			s[k] = Array(s[k]).map(func(x: Variant) -> int: return int(x))
	content.memo[key] = s
	return s


## Свойства тегов бойца (защита — лучшая из тегов, остальное складывается).
static func apply_tags(content: Content, f: SkFighter) -> float:
	var props: Dictionary = _data(content).get("tag_props", {})
	var hp_k := 0.0
	for t: String in f.tags:
		var p: Dictionary = props.get(t, {})
		if p.is_empty():
			continue
		f.prot = maxf(f.prot, float(p.get("prot", 0.0)))
		f.dodge += int(p.get("dodge", 0))
		f.speed += int(p.get("speed", 0))
		f.first_strike += int(p.get("first", 0))
		f.regen += int(p.get("regen", 0))
		hp_k += float(p.get("hp", 0.0))
		f.size = maxi(f.size, int(p.get("size", 1)))
		f.smart = f.smart or bool(p.get("smart", false))
		f.no_corpse = f.no_corpse or bool(p.get("no_corpse", false))
		for k: String in p.get("res", {}):
			f.res[k] = int(f.res.get(k, 0)) + int(p["res"][k])
		for im: String in p.get("immune", []):
			if not f.immune.has(im):
				f.immune.append(im)
		if bool(p.get("stealth_start", false)):
			SkStatus.add(f, {"type": "stealth", "turns": 1})
	f.prot = minf(f.prot, PROT_MAX)
	return hp_k


static func _generic(content: Content) -> Array:
	return [skill(content, "STEP"), skill(content, "PASS")]


## Любимые позиции — откуда бьют его удары (первые две из навыков с уроном).
static func _pref(f: SkFighter) -> Array:
	for s: Dictionary in f.skills:
		if str(s.get("side", "")) == "enemy":
			var fr: Array = s.get("from", [])
			return fr.slice(0, 2) if fr.size() > 2 else fr.duplicate()
	return [1, 2]


## Герой из состояния прохождения. Здоровье — из state.characters[cid].hp (нет — полное); на грани — 0.
static func hero(content: Content, state: RunState, cid: String) -> SkFighter:
	var f := SkFighter.new()
	f.side = "hero"
	f.card = cid
	f.name = content.card_name(cid)
	var sh := StatResolver.sheet(content, state, cid, MissionFlow.pocket(state, cid))
	var pw := int(sh["power"]["total"])
	var wl := int(sh["will"]["total"])
	var cu := int(sh["cunning"]["total"])
	f.tags = MissionFlow.hero_tags(content, state, cid)
	f.speed = int(cu / 2.0)
	f.acc = ACC_STEP * (cu - 5)
	f.dodge = DODGE_BASE + DODGE_STEP * cu
	f.crit = CRIT_BASE + cu
	f.dmg_mult = 1.0 + DMG_STEP * (pw - 5)
	for k: String in RES_KEYS:
		f.res[k] = RES_BASE + RES_STEP * (wl - 5)
	var hp_k := apply_tags(content, f)
	f.size = 1
	f.hp_max = maxi(1, int(round((HP_BASE + HP_POWER * pw + HP_WILL * wl) * (1.0 + hp_k))))
	f.rank = CoreRules.rank(content, state, cid)
	var w := Strikes.hero_weapon(content, state, cid)
	var wd: Dictionary = _data(content).get("weapons", {}).get(str(w.get("id", "")), _data(content).get("weapons", {}).get("Без оружия", {}))
	f.dmg = wd.get("dmg", [1, 3]).duplicate()
	f.skills = [skill(content, str(wd.get("skill", "W_FIST")))]
	f.skills.append_array(_generic(content))
	f.pref = _pref(f)
	var ch := state.character(cid)
	f.hp = clampi(int(ch.get("hp", f.hp_max)), 0, f.hp_max)
	if EdgeRules.on_edge(state, cid):
		f.edge = true
		f.hp = 0
	elif f.hp <= 0:
		f.hp = 1
	return f


## Враг: тип, класс, ранг, теги, природное оружие; power — сила этапа (combat.power), множит здоровье и урон.
static func enemy(content: Content, eid: String, power: float = 1.0) -> SkFighter:
	var e: Dictionary = content.enemies.get(eid, {})
	var f := SkFighter.new()
	f.side = "enemy"
	f.card = eid
	f.name = str(e.get("name", eid))
	var kinds: Dictionary = _data(content).get("kinds", {})
	var kind := str(e.get("kind", "normal"))
	var k: Dictionary = kinds.get(kind, kinds.get("normal", {}))
	var cm: float = CombatSession.CLASS_MULT[clampi(int(e.get("class", 1)), 0, CombatSession.CLASS_MULT.size() - 1)]
	f.tags = Array(e.get("tags", [])).duplicate()
	f.speed = int(k.get("speed", 4))
	f.acc = int(k.get("acc", 0))
	f.dodge = int(k.get("dodge", 5))
	f.crit = int(k.get("crit", 5))
	for key: String in RES_KEYS:
		f.res[key] = int(k.get("res", 20))
	var hp_k := apply_tags(content, f)
	f.size = maxi(f.size, int(e.get("size", 1)))
	f.hp_max = maxi(1, int(round(float(k.get("hp", 14)) * (1.0 + (cm - 1.0) * CLASS_HP) * (1.0 + hp_k) * power)))
	f.hp = f.hp_max
	f.rank = int(e.get("rank", 0))
	f.smart = f.smart or kind == "boss"
	var nat := str(Strikes.enemy_weapon(content, e).get("id", "Натиск"))
	var natural: Dictionary = _data(content).get("natural", {})
	var nd: Dictionary = natural.get(nat, natural.get("Натиск", {}))
	f.dmg = nd.get("dmg", [3, 5]).duplicate()
	f.dmg_mult = float(k.get("dmg", 1.0)) * (1.0 + (cm - 1.0) * CLASS_DMG) * power
	f.skills = [skill(content, str(nd.get("skill", "N_RUSH")))]
	for ts: Dictionary in _data(content).get("tag_skills", []):
		if f.skills.size() >= 3:
			break
		var s := skill(content, str(ts["skill"]))
		if not s.is_empty() and Array(ts["tags"]).any(func(t: String) -> bool: return f.tags.has(t)):
			f.skills.append(s)
	f.skills.append_array(_generic(content))
	var ranged: Array = _data(content).get("ranged_tags", [])
	f.pref = [3, 4] if f.tags.any(func(t: String) -> bool: return ranged.has(t)) else _pref(f)
	return f
