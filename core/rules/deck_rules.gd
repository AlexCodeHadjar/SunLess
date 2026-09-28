class_name DeckRules
extends RefCounted
## Колода событий главы (docs/16 §11.4): побочных и случайных миссий написано больше, чем игрок увидит.
## При открытии главы из каждой группы data/deck.json выпадает pick единиц (миссия, пара-выбор или
## цепочка целиком; min_chains цепочек — всегда). Выпавшие миссии — state.flags.deck[глава];
## остальные MissionFlow.open не открывает. Колода зависит только от зерна прохождения.


## Группы колоды главы: [{name, pick, min_chains, units}]; пусто — у главы колоды нет.
static func groups(content: Content, chapter: String) -> Array:
	var g: Variant = content.deck.get(chapter, [])
	return g if g is Array else []


## Единица колоды как словарь: {id, name, chain, missions}.
static func unit(u: Variant) -> Dictionary:
	if u is Dictionary:
		return {"id": str(u.get("id", "")), "name": str(u.get("name", "")), "chain": bool(u.get("chain", false)),
			"missions": Array(u.get("missions", []))}
	return {"id": str(u), "name": "", "chain": false, "missions": [str(u)]}


## Единица, в которую входит миссия ({} — миссия не в колоде).
static func unit_of(content: Content, mission_id: String) -> Dictionary:
	for g: Dictionary in groups(content, MissionFlow.chapter_of(content, mission_id)):
		for u: Variant in g.get("units", []):
			var d := unit(u)
			if d["missions"].has(mission_id):
				return d
	return {}


## Выпавшие миссии главы; колода тянется при первом обращении (и для старых сохранений).
static func ensure(content: Content, state: RunState, chapter: String) -> Array:
	var all: Dictionary = state.flags.get("deck", {})
	if not all.has(chapter):
		all[chapter] = roll(content, state.rng_seed, chapter)
		state.flags["deck"] = all
	return all[chapter]


## Тянет колоду главы: список id миссий. Одно зерно — одна колода.
static func roll(content: Content, seed_value: int, chapter: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + chapter.hash()
	var out: Array = []
	for g: Dictionary in groups(content, chapter):
		var units: Array = g.get("units", []).map(func(u: Variant) -> Dictionary: return unit(u))
		_shuffle(units, rng)
		var pick := mini(int(g.get("pick", units.size())), units.size())
		var chosen: Array = []
		# сначала — обязательные цепочки
		for d: Dictionary in units:
			if chosen.size() >= int(g.get("min_chains", 0)):
				break
			if d["chain"]:
				chosen.append(d)
		for d: Dictionary in units:
			if chosen.size() >= pick:
				break
			if not chosen.has(d):
				chosen.append(d)
		for d: Dictionary in chosen:
			out.append_array(d["missions"])
	out.sort()
	return out


## Можно ли открыть миссию: она вне колоды главы или выпала в этом прохождении.
static func allowed(content: Content, state: RunState, mission_id: String) -> bool:
	if unit_of(content, mission_id).is_empty():
		return true
	return ensure(content, state, MissionFlow.chapter_of(content, mission_id)).has(mission_id)


## Цепочка миссии для брифинга: {name, index (с 1), total}; {} — не цепочка.
static func chain_info(content: Content, mission_id: String) -> Dictionary:
	var d := unit_of(content, mission_id)
	if d.is_empty() or not d["chain"]:
		return {}
	return {"name": d["name"], "index": d["missions"].find(mission_id) + 1, "total": d["missions"].size()}


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t
