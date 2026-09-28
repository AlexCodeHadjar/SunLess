class_name ModifierRules
extends RefCounted
## Модификаторы миссий (docs/16 §11.2): у побочных и случайных миссий основных глав при открытии выпадает
## 1–2 модификатора (data/modifiers.json) — видны сразу. Меняют теги врага и места в бою, силу врага,
## число врагов, срок, угрозу, награду и шанс Воспоминания. Каждый бой приходится читать заново.
## Хранятся в state.missions[id].mods; бой (CombatSession.create_for_mission) и прогноз видят их одинаково.


static func defs(content: Content) -> Dictionary:
	var out := {}
	for d: Dictionary in content.modifiers.get("list", []):
		out[str(d.get("id", ""))] = d
	return out


static func def(content: Content, mod_id: String) -> Dictionary:
	for d: Dictionary in content.modifiers.get("list", []):
		if str(d.get("id", "")) == mod_id:
			return d
	return {}


## Модификаторы открытой миссии.
static func of(content: Content, state: RunState, mid: String) -> Array:
	var out: Array = []
	for id: String in state.missions.get(mid, {}).get("mods", []):
		var d := def(content, id)
		if not d.is_empty():
			out.append(d)
	return out


static func has_combat(m: Dictionary) -> bool:
	for a: Dictionary in m.get("actions", []):
		for st: Dictionary in a.get("stages", []):
			if st.has("combat"):
				return true
	return false


static func eligible(content: Content, mid: String) -> bool:
	var m: Dictionary = content.missions.get(mid, {})
	if bool(m.get("no_mods", false)):
		return false
	if not Array(content.modifiers.get("types", [])).has(str(m.get("type", ""))):
		return false
	return Array(content.modifiers.get("chapters", [])).has(MissionFlow.chapter_of(content, mid))


## При открытии миссии: бросок модификаторов (детерминированно от зерна прохождения, миссии и часов).
static func roll(content: Content, state: RunState, mid: String) -> Array:
	if not eligible(content, mid):
		return []
	var m: Dictionary = content.missions[mid]
	var pool: Array = []
	for d: Dictionary in content.modifiers.get("list", []):
		match str(d.get("needs", "")):
			"combat":
				if not has_combat(m):
					continue
			"expires":
				if float(m.get("expires", 0)) <= 0.0:
					continue
		pool.append(str(d["id"]))
	if pool.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = state.rng_seed + mid.hash() + int(state.clock * 10.0) + 31 * int(state.missions.get(mid, {}).get("attempts", 0))
	var n := 2 if rng.randf() < float(content.modifiers.get("two_chance", 0.35)) and pool.size() > 1 else 1
	var out: Array = []
	for i in n:
		var pick: String = pool[rng.randi_range(0, pool.size() - 1)]
		pool.erase(pick)
		out.append(pick)
	return out


## Бой: теги и сила врага, лишний враг, теги места. Сессия уже собрана из спецификации этапа.
static func apply_combat(content: Content, state: RunState, key: String, s: CombatSession) -> void:
	var mods := of(content, state, key)
	if mods.is_empty():
		return
	var field: Dictionary = s.field.duplicate(true)
	var ftags: Array = Array(field.get("tags", [])).duplicate()
	for d: Dictionary in mods:
		if bool(d.get("extra_enemy", false)) and not s.enemies.is_empty():
			var extra: Dictionary = s.enemies[0].duplicate(true)
			extra["power"] = float(extra.get("power", 1.0)) * 0.7   # подкрепление слабее вожака
			s.enemies.append(extra)
		for e: Dictionary in s.enemies:
			e["power"] = float(e.get("power", 1.0)) * float(d.get("enemy_power", 1.0))
			var et: Array = Array(e.get("tags", [])).duplicate()
			for t: String in d.get("enemy_tags", []):
				if not et.has(t):
					et.append(t)
			e["tags"] = et
		for t: String in d.get("field_tags", []):
			if not ftags.has(t):
				ftags.append(t)
	field["tags"] = ftags
	s.field = field


## Проверки: [{source, stat, value}] для StatResolver.
static func check_parts(content: Content, state: RunState, mid: String, tags: Array) -> Array:
	var out: Array = []
	for d: Dictionary in of(content, state, mid):
		for b: Dictionary in d.get("check", []):
			for t: String in b.get("tags", []):
				if tags.has(t):
					out.append({"source": str(d.get("name", "")), "stat": str(b["stat"]), "value": int(b["value"])})
					break
	return out


static func threat(content: Content, state: RunState, mid: String) -> int:
	var t := int(content.missions.get(mid, {}).get("threat", 1))
	for d: Dictionary in of(content, state, mid):
		t += int(d.get("threat", 0))
	return clampi(t, 1, 5)


static func expires(content: Content, state: RunState, mid: String) -> float:
	var e := float(content.missions.get(mid, {}).get("expires", 0))
	for d: Dictionary in of(content, state, mid):
		e *= float(d.get("expires_mult", 1.0))
	return e


static func loot_mult(content: Content, state: RunState, mid: String) -> float:
	var k := 1.0
	for d: Dictionary in of(content, state, mid):
		k *= float(d.get("loot_mult", 1.0))
	return k


static func memory_bonus(content: Content, state: RunState, mid: String) -> float:
	var b := 0.0
	for d: Dictionary in of(content, state, mid):
		b += float(d.get("memory_bonus", 0.0))
	return b


## Успех миссии: награда модификаторов.
static func on_success(content: Content, state: RunState, mid: String, executor: String, rng: RandomNumberGenerator) -> Array:
	var n := 0
	for d: Dictionary in of(content, state, mid):
		n += int(d.get("bonus_shards", 0))
	if n <= 0:
		return []
	return EffectApplier.apply(content, state, {"cmd": "adjust_resource", "resource": "shards", "value": n}, executor, rng)
