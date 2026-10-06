class_name SkPack
extends RefCounted
## Состав строя врагов (docs/24 §6.4): в данных этапа — враги события, здесь строй добирается до боевого.
## Стая, Рой, Приспешник — 3–4 таких же; одиночка — пара; элита — со свитой (enemies.escort), босс — с приспешниками
## (enemies.minions). Строй не больше четырёх позиций (крупные занимают две). Уже полный строй не меняется.
## Честность: врагов не больше, чем героев + 1 (но не меньше, чем записано в событии) — одиночку не задавят числом.

const SIZE := 4
const PACK_TAGS := ["Стая", "Рой", "Приспешник"]


static func _size(content: Content, eid: String) -> int:
	var tags: Array = content.enemies.get(eid, {}).get("tags", [])
	var big := tags.has("Гигант") or int(content.skirmish.get("enemies", {}).get(eid, {}).get("size", 1)) > 1
	return 2 if big else 1


static func fill(content: Content, ids: Array, rng: RandomNumberGenerator, party: int = 4) -> Array:
	var out: Array = ids.filter(func(x: String) -> bool: return content.enemies.has(x))
	if out.is_empty():
		return out
	var used := 0
	for eid: String in out:
		used += _size(content, eid)
	if used >= SIZE or out.size() >= 3:
		return out
	var lead := str(out[0])
	var e: Dictionary = content.enemies.get(lead, {})
	var ed: Dictionary = content.skirmish.get("enemies", {}).get(lead, {})
	var add: Array = []
	match str(e.get("kind", "normal")):
		"elite":
			add = Array(ed.get("escort", [])).duplicate()
		"boss":
			add = Array(ed.get("minions", [])).duplicate()
		_:
			var tags: Array = e.get("tags", [])
			if PACK_TAGS.any(func(t: String) -> bool: return tags.has(t)):
				for i in rng.randi_range(2, 3):
					add.append(lead)
			elif out.size() == 1:
				add.append(lead)
	var cap := maxi(out.size(), party + 1)
	for eid2: String in add:
		var sz := _size(content, eid2)
		if used + sz <= SIZE and out.size() < cap:
			out.append(eid2)
			used += sz
	return out
