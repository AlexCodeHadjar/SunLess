class_name OnslaughtRules
extends RefCounted
## Натиск Кошмара (docs/16 §9): раз в every[0]–every[1] секунд на карту главы приходит угроза — миссия
## type "onslaught" из пула (data/onslaught.json). У неё короткий срок (`expires`); не ответили — последствия
## (`on_expire` — команды, `expire_panic` — паника всем героям). Отбили — награда миссии и +1 доверия в отряде.
## Состояние — state.flags["onslaught_at"] (время следующего натиска).

const TRUST_BONUS := 1


static func config(content: Content, chapter: String) -> Dictionary:
	for oid: String in content.onslaught:
		if str(content.onslaught[oid].get("chapter", "")) == chapter:
			return content.onslaught[oid]
	return {}


static func done_in_chapter(content: Content, state: RunState) -> int:
	var n := 0
	for mid: String in state.missions:
		if str(state.missions[mid].get("status", "")) == "done" and MissionFlow.chapter_of(content, mid) == state.chapter:
			n += 1
	return n


static func active(content: Content, state: RunState) -> String:
	for mid: String in MissionFlow._sorted(state.missions):
		if str(content.missions.get(mid, {}).get("type", "")) == "onslaught" and str(state.missions[mid].get("status", "")) in ["open", "active"]:
			return mid
	return ""


## Когда следующий натиск (0 — ещё не назначен).
static func next_at(state: RunState) -> float:
	return float(state.flags.get("onslaught_at", 0.0))


## Часы натиска: назначить, прийти. Возвращает записи (тосты).
static func tick(content: Content, state: RunState) -> Array:
	var cfg := config(content, state.chapter)
	if cfg.is_empty() or state.demo_complete or done_in_chapter(content, state) < int(cfg.get("first_after", 0)):
		return []
	var every: Array = cfg.get("every", [240, 360])
	var rng := RandomNumberGenerator.new()
	rng.seed = state.rng_seed + int(state.clock * 10.0)
	if next_at(state) <= 0.0:
		state.flags["onslaught_at"] = state.clock + rng.randf_range(float(every[0]), float(every[1]))
		return []
	if state.clock < next_at(state) or active(content, state) != "":
		return []
	state.flags["onslaught_at"] = state.clock + rng.randf_range(float(every[0]), float(every[1]))
	var pool: Array = cfg.get("pool", [])
	if pool.is_empty():
		return []
	var mid := str(pool[rng.randi_range(0, pool.size() - 1)])
	var out := MissionFlow.open(content, state, mid)
	for e: Dictionary in out:
		e["kind"] = "onslaught"
		e["text"] = "Натиск Кошмара: %s" % content.missions[mid].get("title", mid)
	return out


## Натиск не отбит вовремя: последствия.
static func expire(content: Content, state: RunState, mid: String) -> Array:
	var m: Dictionary = content.missions.get(mid, {})
	var out: Array = []
	var heroes := MissionFlow.heroes(content, state)
	if heroes.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = state.rng_seed
	rng.state = state.rng_state
	out.append_array(EffectApplier.apply_all(content, state, m.get("on_expire", []), str(heroes[0]), rng))
	var p := int(m.get("expire_panic", 0))
	if p > 0:
		for cid: String in heroes:
			out.append_array(PsycheRules.change(content, state, cid, -p, "натиск не отбит", [], null, "mission", false))
	state.rng_state = rng.state
	return out


## Отбили натиск: доверие в отряде.
static func reward(content: Content, state: RunState, m: Dictionary, heroes: Array, outcome: String) -> Array:
	if str(m.get("type", "")) != "onslaught" or outcome != "success":
		return []
	var out: Array = []
	var alive: Array = heroes.filter(func(c: String) -> bool: return state.is_alive(c))
	for i in alive.size():
		for j in range(i + 1, alive.size()):
			out.append_array(TrustRules.change(content, state, alive[i], alive[j], TRUST_BONUS, "вместе отбили натиск"))
	return out
