class_name MapRules
extends RefCounted
## «Карта Спящего» (docs/16 §11.6): у региона есть карта-план сверху (data/maps/<регион>.json).
## Места стоят на своих точках; меняется их облик — состояние виньетки:
##   · flooded — место под водой (прилив, TideRules);
##   · silt — первые миссии после отлива: мокрый ил, водоросли, выброшенные кости;
##   · ravaged / storm — следы набега и шторма (команда `map_mark`, на N выполненных миссий; шторм — ещё и пока небо штормовое);
##   · dry_b, dry_c — новые проходы: отлив перестраивает коридоры лабиринта (вместо перестановки мест);
##   · появляющиеся места (emerge у места) встают на пустые площадки ила при отливе и несут свою встречу —
##     следующий прилив их уносит; «Гнездовье» поднимает набег (команда `emerge`).
## Всё хранится в state.tide (emerged, variant, silt, marks) и сбрасывается с новой главой.

const SILT := 2                 # выполненных миссий, пока место в иле
const EMERGE_MIN := 1
const EMERGE_MAX := 2


## Карта-план региона главы ({} — у главы старый фон).
static func config(content: Content, chapter: String) -> Dictionary:
	for lid: String in content.locations:
		var loc: Dictionary = content.locations[lid]
		if str(loc.get("chapter", "")) == chapter:
			return content.maps.get(str(loc.get("region", "")), {})
	return {}


static func has_map(content: Content, chapter: String) -> bool:
	return not config(content, chapter).is_empty()


static func is_emerging(content: Content, lid: String) -> bool:
	return bool(content.locations.get(lid, {}).get("emerge", false))


## Появившиеся места: {место: номер площадки}.
static func emerged(state: RunState) -> Dictionary:
	return Dictionary(state.tide.get("emerged", {}))


## Место сейчас есть на карте: обычное — всегда, появляющееся — пока стоит на площадке.
static func present(content: Content, state: RunState, lid: String) -> bool:
	return not is_emerging(content, lid) or emerged(state).has(lid)


## Точка места в долях основы: центр виньетки (появляющееся — его площадка).
static func anchor(content: Content, state: RunState, lid: String) -> Vector2:
	var cfg := config(content, state.chapter)
	var em := emerged(state)
	if em.has(lid):
		var sk: Array = cfg.get("sockets", [])
		var i := int(em[lid])
		if i >= 0 and i < sk.size():
			return Vector2(float(sk[i][0]), float(sk[i][1]))
	var at: Array = cfg.get("places", {}).get(lid, {}).get("at", [0.5, 0.5])
	return Vector2(float(at[0]), float(at[1]))


## Ширина виньетки места в долях ширины основы.
static func size_of(content: Content, state: RunState, lid: String) -> float:
	return float(config(content, state.chapter).get("places", {}).get(lid, {}).get("size", 0.1))


## Какие состояния нарисованы у места.
static func states(content: Content, state: RunState, lid: String) -> Array:
	return Array(config(content, state.chapter).get("places", {}).get(lid, {}).get("states", ["dry"]))


## Облик места сейчас — суффикс файла виньетки (<место>_<облик>).
## Порядок: вода → свежий след (разорено / шторм) → ил → шторм по небу → вариант проходов → сухо.
static func place_state(content: Content, state: RunState, lid: String, sky: String = "") -> String:
	var have := states(content, state, lid)
	if TideRules.flooded(state, lid) and have.has("flooded"):
		return "flooded"
	# угрозы-точки (GateRules): тревога, бой, повреждён, горит, баррикада, ремонт…
	var gs: String = GateRules.visible_state(state, lid, have)
	if gs != "":
		return gs
	# местность (TerrainRules): обрушенный мост, облик по фазе недели
	var ts := TerrainRules.state_of(content, state, lid, have)
	if ts != "":
		return ts
	var mark: Dictionary = Dictionary(state.tide.get("marks", {})).get(lid, {})
	if not mark.is_empty() and have.has(str(mark.get("state", ""))):
		return str(mark["state"])
	# события карты (MapEventRules): фаза недели, неделя, лагерь здесь
	var es := MapEventRules.state_of(content, state, lid, have)
	if es != "":
		return es
	if int(Dictionary(state.tide.get("silt", {})).get(lid, 0)) > 0 and have.has("silt"):
		return "silt"
	if sky == "storm" and have.has("storm"):
		return "storm"
	var v := str(Dictionary(state.tide.get("variant", {})).get(lid, "dry"))
	return v if have.has(v) else "dry"


## След на месте на N выполненных миссий (`map_mark`: ravaged | storm).
static func mark(content: Content, state: RunState, lid: String, st: String, missions: int) -> Array:
	if not content.locations.has(lid):
		return []
	var marks: Dictionary = Dictionary(state.tide.get("marks", {})).duplicate()
	marks[lid] = {"state": st, "left": maxi(1, missions)}
	state.tide["marks"] = marks
	var what: String = {"ravaged": "разорено", "storm": "после шторма"}.get(st, st)
	return [{"kind": "info", "text": "%s — %s" % [content.locations[lid].get("name", lid), what]}]


## Выполнена миссия: ил подсыхает, следы стираются.
static func count(state: RunState) -> void:
	var silt: Dictionary = Dictionary(state.tide.get("silt", {})).duplicate()
	for lid: String in silt.keys():
		silt[lid] = int(silt[lid]) - 1
		if int(silt[lid]) <= 0:
			silt.erase(lid)
	if silt.is_empty():
		state.tide.erase("silt")
	else:
		state.tide["silt"] = silt
	var marks: Dictionary = Dictionary(state.tide.get("marks", {})).duplicate()
	for lid: String in marks.keys():
		var m: Dictionary = Dictionary(marks[lid]).duplicate()
		m["left"] = int(m.get("left", 1)) - 1
		if int(m["left"]) <= 0:
			marks.erase(lid)
		else:
			marks[lid] = m
	if marks.is_empty():
		state.tide.erase("marks")
	else:
		state.tide["marks"] = marks


## Поднять место на свободную площадку (ближайшую к near) и открыть его встречу.
static func emerge(content: Content, state: RunState, lid: String, rng: RandomNumberGenerator, near: String = "") -> Array:
	var cfg := config(content, state.chapter)
	var sk: Array = cfg.get("sockets", [])
	var em := emerged(state).duplicate()
	if cfg.is_empty() or em.has(lid) or not is_emerging(content, lid):
		return []
	var taken := {}
	for other: String in em:
		taken[int(em[other])] = true
	var free: Array = []
	# у места своя группа площадок (котловины пепла, островки Чёрной воды — TerrainRules.emerge_groups)
	var group := str(content.locations.get(lid, {}).get("socket_group", ""))
	# места отлива (без своей группы) — только на площадках ила (ebb_sockets); площадки в море и на скалах — для событий
	var src: Array = cfg.get("emerge_groups", {}).get(group, {}).get("sockets", []) if group != "" else cfg.get("ebb_sockets", [])
	var allowed: Array = src.map(func(x: Variant) -> int: return int(x))   # номера из JSON — дробные: [0.0].has(0) == false
	for i in sk.size():
		if not taken.has(i) and (allowed.is_empty() or allowed.has(i)):
			free.append(i)
	if free.is_empty():
		return []
	var pick: int = free[rng.randi_range(0, free.size() - 1)]
	if near != "" and cfg.get("places", {}).has(near):
		var at: Array = cfg["places"][near].get("at", [0.5, 0.5])
		var best := INF
		for i: int in free:
			var d := Vector2(float(sk[i][0]), float(sk[i][1])).distance_to(Vector2(float(at[0]), float(at[1])))
			if d < best:
				best = d
				pick = i
	em[lid] = pick
	state.tide["emerged"] = em
	var out: Array = [{"kind": "emerge", "card": lid, "text": "На карте: %s" % content.locations[lid].get("name", lid)}]
	for mid: String in content.locations[lid].get("random", {}).get("pool", []):
		var opened := MissionFlow.open(content, state, mid)
		if not opened.is_empty():
			out.append_array(opened)
			break
	return out


## Вода сошла на карте-плане: смытые появившиеся места уходят, коридоры перестраиваются, остаётся ил.
static func on_ebb(content: Content, state: RunState, was_flooded: Array, rng: RandomNumberGenerator) -> Array:
	var cfg := config(content, state.chapter)
	var out: Array = []
	var em := emerged(state).duplicate()
	for lid: String in was_flooded:
		if em.has(lid):
			em.erase(lid)
	state.tide["emerged"] = em
	var variants: Dictionary = Dictionary(state.tide.get("variant", {})).duplicate()
	var silt: Dictionary = Dictionary(state.tide.get("silt", {})).duplicate()
	for lid: String in was_flooded:
		var vs: Array = cfg.get("variants", {}).get(lid, [])
		if vs.size() > 1:
			var cur := str(variants.get(lid, "dry"))
			var others: Array = vs.filter(func(v: String) -> bool: return v != cur)
			variants[lid] = others[rng.randi_range(0, others.size() - 1)]
		elif states(content, state, lid).has("silt"):
			silt[lid] = SILT
	state.tide["variant"] = variants
	if not silt.is_empty():
		state.tide["silt"] = silt
	return out


## Большой отлив (фаза «Рассвет», DayRules): на свободных площадках ила поднимаются 1–2 новых места
## (из тех, что сейчас не стоят на карте; Гнездовье поднимает только набег).
static func low_tide(content: Content, state: RunState, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	if not has_map(content, state.chapter):
		return out
	var em := emerged(state)
	var pool: Array = []
	for lid: String in _sorted(content.locations):
		var loc: Dictionary = content.locations[lid]
		if str(loc.get("chapter", "")) == state.chapter and is_emerging(content, lid) and not em.has(lid) \
				and not bool(loc.get("raid_only", false)):
			pool.append(lid)
	var n := rng.randi_range(EMERGE_MIN, EMERGE_MAX)
	for i in n:
		if pool.is_empty():
			break
		var lid: String = pool[rng.randi_range(0, pool.size() - 1)]
		pool.erase(lid)
		out.append_array(emerge(content, state, lid, rng))
	return out


## Тропы главы: пары мест из карты-плана и тропа от каждого поднявшегося места к ближайшему обычному.
static func links(content: Content, state: RunState) -> Array:
	var cfg := config(content, state.chapter)
	var out: Array = []
	# постоянные тропы + сеть бури и водные тропы (TerrainRules); заваленные обвалом — закрыты
	for pair: Array in Array(cfg.get("paths", [])) + TerrainRules.extra_paths(content, state):
		if present(content, state, str(pair[0])) and present(content, state, str(pair[1])) \
				and TerrainRules.path_open(content, state, str(pair[0]), str(pair[1])):
			out.append([str(pair[0]), str(pair[1])])
	for lid: String in emerged(state):
		var a := anchor(content, state, lid)
		var best := ""
		var bd := INF
		for other: String in cfg.get("places", {}):
			if other == lid or is_emerging(content, other) or not content.locations.has(other):
				continue
			var d := anchor(content, state, other).distance_to(a)
			if d < bd:
				bd = d
				best = other
		if best != "":
			out.append([lid, best])
	return out


## Соседи места по тропам.
static func neighbors(content: Content, state: RunState, lid: String) -> Array:
	var out: Array = []
	for pair: Array in links(content, state):
		if pair[0] == lid and not out.has(pair[1]):
			out.append(pair[1])
		elif pair[1] == lid and not out.has(pair[0]):
			out.append(pair[0])
	return out


## Место открыто на карте (туман неизвестного расступился) — docs/17 §2. Видно:
## лавки; где отряд бывал и куда сюжет приводил; соседей этих мест (тропы от знакомых мест видны);
## весь путь до каждой открытой миссии (игрок всегда видит, как дойти); разведанное (дело лагеря «Разведка»);
## с высоты (служба view у лагеря) — ещё и места в двух переходах. Появившееся место — пока оно на карте.
static func revealed(content: Content, state: RunState, lid: String) -> bool:
	if is_emerging(content, lid):
		return emerged(state).has(lid)
	if content.shops.has(lid):
		return true
	return known(content, state).has(lid)


## Все открытые места разом (для отрисовки и проверок).
static func known(content: Content, state: RunState) -> Dictionary:
	var out := {}
	var cfg := config(content, state.chapter)
	var places: Dictionary = cfg.get("places", {})
	var seen: Array = TravelRules.visited(state).duplicate()
	seen.append_array(Array(state.flags.get("scouted", [])))
	if state.party_at != "":
		seen.append(state.party_at)
	for lid: String in places:
		if content.locations.has(lid) and MissionFlow.reached(content, state, lid):
			seen.append(lid)
	var adj := TravelRules.adjacency(content, state)
	for lid: String in seen:
		if not places.has(lid) or not present(content, state, lid):
			continue
		out[lid] = true
		for n: String in adj.get(lid, []):
			out[n] = true
	# с высоты — ещё кольцо дальше
	if DayRules.camp(content, state).get("services", []).has("view"):
		for n: String in adj.get(state.party_at, []):
			for n2: String in adj.get(n, []):
				out[n2] = true
	# путь к каждой открытой миссии главы (и через воду — чтобы было видно, что отрезано)
	if state.party_at != "":
		for mid: String in MissionFlow.open_missions(state):
			var loc := str(content.missions.get(mid, {}).get("location", ""))
			if MissionFlow.chapter_of(content, mid) != state.chapter or not places.has(loc):
				continue
			out[loc] = true
			for p: String in TravelRules.route(content, state, state.party_at, loc, false):
				out[p] = true
	for lid: String in out.keys():
		if is_emerging(content, lid) and not emerged(state).has(lid):
			out.erase(lid)
	return out


static func _sorted(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k
