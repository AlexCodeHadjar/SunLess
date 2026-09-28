class_name Strikes
extends RefCounted
## Удары вместо броска (docs/16 §9е, п.7). У сторон запас силы — расчёт первого раунда (теги, поле, навыки карт).
## Каждый раунд бьют все: каждый герой отряда своим оружием и каждый враг природным; первыми — «Первый удар»,
## лук (каждый раунд) и копьё (в первом раунде). Урон удара = доля силы раунда × оружие × против тегов цели ×
## броня × разброс; случайность — только попадание, крит и разброс. Опасное окружение ранит обе стороны.
## Сторона без силы проигрывает сразу; после трёх раундов побеждает тот, кто потерял меньшую долю своей силы.
## Данные — data/combat/weapons.json.

const RATE := 0.27          # сторона за раунд наносит ударами такую долю «силы схватки»
const OWN_POWER := 0.6      # сила схватки = своя^0.6 × чужая^0.4: сильный бьёт больнее, но слабый не беспомощен
                            # (при чистой пропорции перевес работал бы в квадрате — запас тоже равен силе)
const SPREAD := 0.45        # разброс урона удара: ±45%
const ALLY_WEIGHT := 0.6    # доля союзника в ударах отряда относительно ведущего
const ALLY_SHARE := 0.25    # каждый живой союзник: +25% к запасу и силе схватки отряда
const HIT_MIN := 35
const HIT_MAX := 95
const ROUNDS := 3
const INTENT_AVG := 0.07     # в прогнозе: средняя прибавка врагу от намерений раундов (их заранее не видно)


static func _data(content: Content) -> Dictionary:
	return content.weapons


static func weapon(content: Content, id: String) -> Dictionary:
	for w: Dictionary in _data(content).get("weapons", []):
		if str(w["id"]) == id:
			return w
	return {}


## Оружие героя: из усиления в кармашке (поле weapon), иначе своё (characters.json weapon), иначе «Без оружия».
static func hero_weapon(content: Content, state: RunState, cid: String) -> Dictionary:
	for card: String in MissionFlow.pocket(state, cid):
		var wid := str(content.enhancements.get(card, {}).get("weapon", ""))
		if wid != "" and not weapon(content, wid).is_empty():
			return weapon(content, wid)
	var own := weapon(content, str(content.characters.get(cid, {}).get("weapon", "")))
	return own if not own.is_empty() else weapon(content, "Без оружия")


## Природное оружие врага: первое по порядку в weapons.json, чьи теги есть у врага; иначе «Натиск».
static func enemy_weapon(content: Content, e: Dictionary) -> Dictionary:
	var tags: Array = e.get("tags", [])
	var fallback := {}
	for w: Dictionary in _data(content).get("natural", []):
		var need: Array = w.get("tags", [])
		if need.is_empty():
			fallback = w
		elif need.any(func(t: String) -> bool: return tags.has(t)):
			return w
	return fallback


static func _any(tags: Array, need: Array) -> bool:
	return need.any(func(t: String) -> bool: return tags.has(t))


## Бойцы раунда: [{side, idx, card, weapon, weight, first, tags}] — у героев idx 0 — ведущий, дальше союзники.
static func strikers(s: CombatSession) -> Array:
	var d := _data(s.content)
	var first_tags: Array = d.get("first", {}).get("tags", [])
	var out: Array = []
	var heroes: Array = [s.hero] + s.allies
	for i in heroes.size():
		var cid: String = heroes[i]
		if not s.state.is_alive(cid):
			continue
		var w := hero_weapon(s.content, s.state, cid)
		var tags := MissionFlow.hero_tags(s.content, s.state, cid)
		out.append({"side": "hero", "idx": i, "card": cid, "weapon": w, "weight": 1.0 if i == 0 else ALLY_WEIGHT, "tags": tags,
			"first": bool(w.get("first", false)) or (bool(w.get("first_round", false)) and s.round_no <= 1) or _any(tags, first_tags)})
	for j in s.enemies.size():
		var e: Dictionary = s.enemies[j]
		var we := enemy_weapon(s.content, e)
		var et: Array = e.get("tags", [])
		out.append({"side": "enemy", "idx": j, "card": str(e.get("id", "")), "weapon": we, "weight": s._enemy_base(e), "tags": et,
			"first": bool(we.get("first", false)) or _any(et, first_tags)})
	return out


## Шанс попадания удара, %: оружие + точность бойца − увёртливость цели + погода/место для оружия.
static func hit_chance(content: Content, st: Dictionary, def_tags: Array, env: Array) -> int:
	var d := _data(content)
	var w: Dictionary = st["weapon"]
	var h := int(w.get("hit", 75))
	if _any(st["tags"], d.get("precision", {}).get("tags", [])):
		h += int(d["precision"].get("hit", 0))
	if _any(def_tags, d.get("evasion", {}).get("tags", [])):
		h += int(d["evasion"].get("hit", 0))
	var we: Dictionary = w.get("env", {})
	for t: String in we:
		if env.has(t):
			h += int(we[t])
	return clampi(h, HIT_MIN, HIT_MAX)


## Множитель урона по цели: оружие против тегов цели × броня (если оружие не пробивает).
static func dmg_mult(content: Content, w: Dictionary, def_tags: Array) -> float:
	var m := float(w.get("dmg", 1.0))
	var vs: Dictionary = w.get("vs", {})
	for t: String in vs:
		if def_tags.has(t):
			m *= float(vs[t])
	var arm: Dictionary = _data(content).get("armor", {})
	if not bool(w.get("pierce", false)) and _any(def_tags, arm.get("tags", [])):
		m *= float(arm.get("mult", 1.0))
	return m


## Сила сторон для ударов и запаса: у отряда — сила ведущего × (1 + 35% за каждого живого союзника).
static func side_power(s: CombatSession, led: Dictionary) -> Dictionary:
	var allies := s.allies.filter(func(a: String) -> bool: return s.state.is_alive(a)).size()
	return {"hero": maxf(1.0, float(led["hero"]) * (1.0 + ALLY_SHARE * allies)), "enemy": maxf(1.0, float(led["enemy"]))}


## Урон бойца до поправок: RATE × сила схватки стороны × вес / сумма весов стороны.
static func _budgets(list: Array, pw: Dictionary) -> Dictionary:
	var sum := {"hero": 0.0, "enemy": 0.0}
	for st: Dictionary in list:
		sum[st["side"]] += float(st["weight"])
	var out := {}
	for k in list.size():
		var st: Dictionary = list[k]
		var own := float(pw[st["side"]])
		var other := float(pw["enemy" if st["side"] == "hero" else "hero"])
		var power := pow(own, OWN_POWER) * pow(other, 1.0 - OWN_POWER)
		out[k] = RATE * power * float(st["weight"]) / maxf(0.001, float(sum[st["side"]]))
	return out


## Обмен ударами одного раунда: меняет s.pool, возвращает удары по порядку.
## Удар: {side, idx, card, weapon, verb, target_idx, hit_chance, hit, crit, dmg, pool_after}.
static func exchange(s: CombatSession, led: Dictionary) -> Array:
	var list := strikers(s)
	var budget := _budgets(list, side_power(s, led))
	var order: Array = []
	for k in list.size():
		var st: Dictionary = list[k]
		order.append([(2.0 if st["first"] else 1.0) + (0.3 if st["side"] == "hero" else 0.0) + s.rng.randf() * 0.25, k])
	order.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var out: Array = []
	var env: Array = led.get("env_tags", [])
	var alive_heroes: Array = list.filter(func(x: Dictionary) -> bool: return x["side"] == "hero")
	for pair: Array in order:
		var st: Dictionary = list[int(pair[1])]
		var side: String = st["side"]
		var other := "enemy" if side == "hero" else "hero"
		if float(s.pool[side]) <= 0.0 or float(s.pool[other]) <= 0.0:
			break
		var def_tags: Array = led["enemy_tags"] if side == "hero" else led["hero_tags"]
		var w: Dictionary = st["weapon"]
		var hc := hit_chance(s.content, st, def_tags, env)
		var hit := s.rng.randi_range(1, 100) <= hc
		var crit := hit and s.rng.randi_range(1, 100) <= int(w.get("crit", 10))
		var dmg := 0.0
		if hit:
			dmg = float(budget[int(pair[1])]) * dmg_mult(s.content, w, def_tags) * s.rng.randf_range(1.0 - SPREAD, 1.0 + SPREAD)
			if crit:
				dmg *= float(w.get("crit_mult", 1.8))
			s.pool[other] = maxf(0.0, float(s.pool[other]) - dmg)
		var target := 0
		if side == "hero":
			target = s.rng.randi_range(0, maxi(0, s.enemies.size() - 1))
		elif alive_heroes.size() > 1 and s.rng.randf() < 0.35:
			target = int(alive_heroes[s.rng.randi_range(1, alive_heroes.size() - 1)]["idx"])
		out.append({"side": side, "idx": st["idx"], "card": st["card"], "weapon": str(w.get("id", "")), "verb": str(w.get("verb", "бьёт")),
			"target_idx": target, "hit_chance": hc, "hit": hit, "crit": crit, "dmg": snappedf(dmg, 0.1), "pool_after": snappedf(float(s.pool[other]), 0.1)})
	return out


## Опасное окружение (падение, лава, буран…) ранит каждую сторону, у которой нет защиты. [{tag, side, dmg, text}]
static func hazards(s: CombatSession, led: Dictionary) -> Array:
	var out: Array = []
	var env: Array = led.get("env_tags", [])
	for hz: Dictionary in _data(s.content).get("hazards", []):
		if not env.has(str(hz["tag"])):
			continue
		for side: String in ["hero", "enemy"]:
			var tags: Array = led["hero_tags"] if side == "hero" else led["enemy_tags"]
			if _any(tags, hz.get("spare", [])) or float(s.pool[side]) <= 0.0:
				continue
			var dmg := float(hz.get("share", 0.0)) * float(s.pool_max[side])
			s.pool[side] = maxf(0.0, float(s.pool[side]) - dmg)
			out.append({"tag": hz["tag"], "side": side, "dmg": snappedf(dmg, 0.1), "text": str(hz.get("text", hz["tag"]))})
	return out


## Шанс победы в бою по расчёту раунда (для прогноза): нормальное приближение суммы долей урона за три раунда —
## те же бойцы, попадание, крит, разброс, броня и окружение, что и в настоящем бою.
static func odds(s: CombatSession, led: Dictionary) -> float:
	var list := strikers(s)
	var pool := side_power(s, led)
	var budget := _budgets(list, pool)
	var env: Array = led.get("env_tags", [])
	var mu := 0.0
	var var_sum := 0.0
	var spread2 := 1.0 + SPREAD * SPREAD / 3.0
	for k in list.size():
		var st: Dictionary = list[k]
		var side: String = st["side"]
		var other := "enemy" if side == "hero" else "hero"
		var def_tags: Array = led["enemy_tags"] if side == "hero" else led["hero_tags"]
		var w: Dictionary = st["weapon"]
		var h := hit_chance(s.content, st, def_tags, env) / 100.0
		var c := int(w.get("crit", 10)) / 100.0
		var km := float(w.get("crit_mult", 1.8))
		var b := float(budget[k]) * dmg_mult(s.content, w, def_tags) / float(pool[other])
		if side == "enemy":
			b *= 1.0 + INTENT_AVG
		var m1 := b * h * (1.0 - c + c * km)
		var m2 := b * b * h * (1.0 - c + c * km * km) * spread2
		var dir := 1.0 if side == "hero" else -1.0   # урон героев — доля врага (в плюс), урон врагов — доля отряда (в минус)
		mu += dir * m1 * ROUNDS
		var_sum += (m2 - m1 * m1) * ROUNDS
	for hz: Dictionary in _data(s.content).get("hazards", []):
		if env.has(str(hz["tag"])):
			if not _any(led["hero_tags"], hz.get("spare", [])):
				mu -= float(hz.get("share", 0.0)) * ROUNDS
			if not _any(led["enemy_tags"], hz.get("spare", [])):
				mu += float(hz.get("share", 0.0)) * ROUNDS
	var sigma := sqrt(maxf(var_sum, 0.0001))
	return clampf(_phi(mu / sigma), 0.02, 0.98)


## Функция нормального распределения (приближение Абрамовица — Стиган).
static func _phi(x: float) -> float:
	var t := 1.0 / (1.0 + 0.2316419 * absf(x))
	var d := 0.3989423 * exp(-x * x / 2.0)
	var p := d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))))
	return 1.0 - p if x > 0.0 else p
