class_name TraumaRules
extends RefCounted
## Случайная травма, смягчение, шанс смерти (файл 04).

const SEVERITY_ORDER: Array[String] = ["light", "heavy", "critical"]


## n — число травм после получения новой (T09 не считается).
static func death_chance(n: int) -> int:
	if n <= 2:
		return 0
	return mini(100, 15 + 20 * (n - 3))


## Травмы, которые учитываются в счётчике смерти.
static func counted(traumas: Array) -> int:
	var n := 0
	for t: String in traumas:
		if t != "T09":
			n += 1
	return n


## Выбирает случайную травму. pool: "all" | "physical" | "environment" | "mental".
## Возвращает "" если выдать нечего.
static func pick(content: Content, pool: String, owned: Array, rng: RandomNumberGenerator) -> String:
	var candidates := _candidates(content, pool, owned)
	if candidates.is_empty() and pool != "all":
		candidates = _candidates(content, "all", owned)
	if candidates.is_empty():
		return ""
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _candidates(content: Content, pool: String, owned: Array) -> Array:
	var out: Array = []
	for tid: String in content.traumas:
		var t: Dictionary = content.traumas[tid]
		if not bool(t.get("random", true)):
			continue
		if owned.has(tid):
			continue
		if pool != "all" and t.get("category", "") != pool:
			continue
		out.append(tid)
	out.sort()
	return out


## Смягчение на одну ступень: травма той же категории на ступень легче.
## Возвращает "" если травма исчезает (лёгкая смягчается до «нет травмы»).
static func soften(content: Content, trauma_id: String, owned: Array, rng: RandomNumberGenerator) -> String:
	var t: Dictionary = content.traumas.get(trauma_id, {})
	var cat: String = t.get("category", "")
	var idx := SEVERITY_ORDER.find(t.get("severity", "light"))
	while idx > 0:
		idx -= 1
		var options: Array = []
		for tid: String in content.traumas:
			var d: Dictionary = content.traumas[tid]
			if d.get("category", "") == cat and d.get("severity", "") == SEVERITY_ORDER[idx] \
					and bool(d.get("random", true)) and not owned.has(tid):
				options.append(tid)
		if not options.is_empty():
			options.sort()
			return options[rng.randi_range(0, options.size() - 1)]
	return ""
