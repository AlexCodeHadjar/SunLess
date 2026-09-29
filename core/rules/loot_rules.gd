class_name LootRules
extends RefCounted
## Воспоминания-добыча (docs/16 §11.3): после выигранного боя основных глав — шанс по силе врагов;
## боссы, ключевые сюжетные миссии и концы цепочек квестов (поле миссии `memory`) — всегда.
## Выпало — выбор 1 из 3 усилений (пул: усиления с `loot: true`, которых у игрока нет). Уровень каждой из трёх —
## по весам источника: слабые твари — обычные, иногда редкие; сильные — до эпических; легендарные — только
## боссы, сюжет и цепочки. Настройки — data/loot.json. Выборы ждут в очереди state.flags.pending_memory, пока игрок не возьмёт карту.

const TIERS := ["weak", "mid", "strong", "boss"]
const TIER_NAMES := {"weak": "слабая тварь", "mid": "опасная тварь", "strong": "сильный враг", "boss": "босс или ключевое событие"}
const RARITY_ORDER := ["common", "rare", "epic", "legendary"]


static func cfg(content: Content) -> Dictionary:
	return content.loot


static func active(content: Content, chapter: String) -> bool:
	return Array(cfg(content).get("chapters", [])).has(chapter)


## Сила врагов для добычи — не зависит от героя: 1.6^ранг × класс × power (как в бою при ранге героя 0).
static func strength(content: Content, enemies: Array) -> float:
	var t := 0.0
	for e: Variant in enemies:
		var d: Dictionary = e if e is Dictionary else content.enemies.get(str(e), {})
		var cls := clampi(int(d.get("class", 1)), 1, 7)
		t += pow(CombatSession.RANK_STEP, int(d.get("rank", 0))) * CombatSession.CLASS_MULT[cls] * float(d.get("power", 1.0))
	return t


## Уровень источника по врагам боя.
static func tier_of(content: Content, enemies: Array) -> String:
	var c := cfg(content)
	var elite := false
	for e: Variant in enemies:
		var d: Dictionary = e if e is Dictionary else content.enemies.get(str(e), {})
		match str(d.get("kind", "normal")):
			"boss":
				return "boss"
			"elite":
				elite = true
	var s := strength(content, enemies)
	if elite or s >= float(c.get("strong_from", 3.0)):
		return "strong"
	if s >= float(c.get("mid_from", 2.0)):
		return "mid"
	return "weak"


static func better(a: String, b: String) -> String:
	return a if TIERS.find(a) >= TIERS.find(b) else b


## Пул карт уровня rarity, которых нет у игрока и которых ещё нет среди предложенных.
static func _pool(content: Content, state: RunState, rarity: String, taken: Array) -> Array:
	var out: Array = []
	var ids: Array = content.enhancements.keys()
	ids.sort()
	for id: String in ids:
		var e: Dictionary = content.enhancements[id]
		if bool(e.get("loot", false)) and str(e.get("rarity", "common")) == rarity and not state.owns(id) and not taken.has(id):
			out.append(id)
	return out


static func _pick_rarity(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for r: String in weights:
		total += float(weights[r])
	var x := rng.randf() * total
	for r: String in RARITY_ORDER:
		if not weights.has(r):
			continue
		x -= float(weights[r])
		if x <= 0.0:
			return r
	return str(weights.keys()[0])


## Три карты на выбор для уровня tier. Если нужного уровня не осталось — ближайший из разрешённых источнику.
static func options(content: Content, state: RunState, tier: String, rng: RandomNumberGenerator) -> Array:
	var weights: Dictionary = cfg(content).get("tiers", {}).get(tier, {"common": 1})
	var allowed: Array = RARITY_ORDER.filter(func(r: String) -> bool: return weights.has(r))
	var out: Array = []
	for i in int(cfg(content).get("choices", 3)):
		var want := _pick_rarity(weights, rng)
		# сначала нужный уровень, потом разрешённые пониже, потом повыше
		var order: Array = [want]
		var wi := RARITY_ORDER.find(want)
		for k in range(wi - 1, -1, -1):
			if allowed.has(RARITY_ORDER[k]):
				order.append(RARITY_ORDER[k])
		for k2 in range(wi + 1, RARITY_ORDER.size()):
			if allowed.has(RARITY_ORDER[k2]):
				order.append(RARITY_ORDER[k2])
		for r2: String in order:
			var pool := _pool(content, state, r2, out)
			if not pool.is_empty():
				out.append(pool[rng.randi_range(0, pool.size() - 1)])
				break
	return out


## Бросок после выигранного боя: "" — не выпало, иначе уровень источника.
static func roll_fight(content: Content, state: RunState, mid: String, enemies: Array, rng: RandomNumberGenerator) -> String:
	if not active(content, MissionFlow.chapter_of(content, mid)):
		return ""
	var tier := tier_of(content, enemies)
	var chance := float(cfg(content).get("chance", {}).get(tier, 0.0)) + ModifierRules.memory_bonus(content, state, mid)
	if Atmosphere.sky(content, state) == "blood_moon":
		chance *= Atmosphere.BLOOD_MEMORY
	return tier if rng.randf() < chance else ""


## Итог миссии: выбор Воспоминания, если выпало в боях или его обещает сама миссия (поле memory).
## Ставит выбор в очередь state.flags.pending_memory и возвращает его (пусто — ничего).
static func offer(content: Content, state: RunState, mid: String, tier: String, rng: RandomNumberGenerator) -> Dictionary:
	var m: Dictionary = content.missions.get(mid, {})
	var fixed := str(m.get("memory", ""))
	if fixed != "":
		tier = better(fixed, tier) if tier != "" else fixed
	if tier == "":
		return {}
	var opts := options(content, state, tier, rng)
	if opts.is_empty():
		return {}
	var p := {"tier": tier, "options": opts, "mission": mid, "title": str(m.get("title", mid))}
	var q := queue(state)
	q.append(p)
	state.flags["pending_memory"] = q
	return p


static func queue(state: RunState) -> Array:
	var q: Variant = state.flags.get("pending_memory", [])
	return Array(q).duplicate(true) if q is Array else []


## Первый выбор, который ждёт игрока (пусто — нет).
static func pending(state: RunState) -> Dictionary:
	var q := queue(state)
	return q[0] if not q.is_empty() else {}


## Игрок берёт одну из трёх карт (card "" — «распылить на осколки»: +dust осколков из loot.json). Возвращает записи для интерфейса.
static func take(content: Content, state: RunState, card: String) -> Array:
	var q := queue(state)
	if q.is_empty():
		return []
	var p: Dictionary = q.pop_front()
	if q.is_empty():
		state.flags.erase("pending_memory")
	else:
		state.flags["pending_memory"] = q
	if card == "":
		# «Распылить на осколки»: ни одной карты — зато осколки душ
		var n := int(cfg(content).get("dust", 5))
		return EffectApplier.apply(content, state, {"cmd": "adjust_resource", "resource": "shards", "value": n}, "", null)
	if not Array(p.get("options", [])).has(card):
		return []
	state.note(card, "Воспоминание: «%s»" % str(p.get("title", "")))
	return EffectApplier.add_card(content, state, card)
