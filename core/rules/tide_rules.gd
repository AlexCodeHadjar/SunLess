class_name TideRules
extends RefCounted
## Прилив Забытого Берега (docs/16 §11.1): море возвращается по сюжету — команда `tide` в последствиях миссии.
## Сначала предупреждение (warn с): видно, какие места уйдут под воду. Потом прилив (flood с):
##   · места уходят под воду — низины (height: low) всегда, средние (mid) — с шансом, высоты (high) — никогда;
##   · отряд, которого вода застала в таком месте (в пути или на месте), бежит: проверка Хитрости —
##     удача: только психика, провал: один герой — поражение (грань смерти, на грани — бросок смерти);
##   · открытые побочные и случайные миссии там смыты; сюжетные ждут отлива (отправить нельзя).
## Отлив: лабиринт перестроен — затопленные места меняются местами на карте (новые проходы), в них — новые встречи.
## Натиск не тонет: угроза приходит сама.

const MID_CHANCE := 0.5
const WARN := 40.0
const FLOOD := 80.0
const FLEE_REQ := {"cunning": 6}
const FLEE_TAGS := ["survival", "climb", "chase"]
const FLEE_PSY := -8          # выбрались — психика
const FAIL_PSY := -12         # не все выбрались — психика всего отряда
const JITTER := 0.03          # новые проходы: место сдвигается ещё и чуть в сторону
const HEIGHT_NAMES := {"low": "низина", "mid": "средняя высота", "high": "высота"}


static func phase(state: RunState) -> String:
	return str(state.tide.get("phase", ""))


static func places(state: RunState) -> Array:
	return Array(state.tide.get("places", []))


static func height(content: Content, lid: String) -> String:
	return str(content.locations.get(lid, {}).get("height", ""))


## Место сейчас под водой.
static func flooded(state: RunState, lid: String) -> bool:
	return phase(state) == "flood" and places(state).has(lid)


## Место уйдёт под воду, когда придёт объявленный прилив.
static func threatened(state: RunState, lid: String) -> bool:
	return phase(state) == "warn" and places(state).has(lid)


## Секунды до прихода воды (warn) или до отлива (flood); -1 — прилива нет.
static func left(state: RunState) -> float:
	match phase(state):
		"warn":
			return maxf(0.0, float(state.tide.get("at", 0.0)) - state.clock)
		"flood":
			return maxf(0.0, float(state.tide.get("until", 0.0)) - state.clock)
	return -1.0


## Миссия недоступна: её место под водой (натиск не тонет).
static func mission_flooded(content: Content, state: RunState, mid: String) -> bool:
	var m: Dictionary = content.missions.get(mid, {})
	return str(m.get("type", "")) != "onslaught" and flooded(state, str(m.get("location", "")))


## Отряд, отправленный сейчас, не успеет: вода придёт раньше, чем он прибудет и сделает дело.
static func risky(content: Content, state: RunState, mid: String) -> bool:
	var m: Dictionary = content.missions.get(mid, {})
	if str(m.get("type", "")) == "onslaught" or not threatened(state, str(m.get("location", ""))):
		return false
	return float(m.get("duration", 8)) + 2.0 >= left(state)


## Точка места на карте с учётом новых проходов после отлива: место стоит в чужой «ячейке» (исходной точке
## другого места) со сдвигом. Ячейки только переставляются — два места никогда не встанут в одну точку.
static func pos(content: Content, state: RunState, lid: String) -> Array:
	var cell := slot(state, lid)
	var p: Array = content.locations.get(cell, content.locations.get(lid, {})).get("pos", [0.5, 0.5])
	var dx := float(state.tide.get("shift", {}).get(lid, 0.0))
	return [clampf(float(p[0]) + dx, 0.02, 0.98), float(p[1])]


static func slot(state: RunState, lid: String) -> String:
	return str(state.tide.get("slot", {}).get(lid, lid))


static func _rng(state: RunState, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = state.rng_seed + int(state.clock * 10.0) + 7919 * (int(state.tide.get("count", 0)) + 1) + salt
	return rng


## Команда `tide`: объявить прилив. Места выбираются сразу — игрок видит, что уйдёт под воду.
## Если вода уже стоит — прилив затягивается; если уже объявлен — второй не наслаивается.
static func schedule(content: Content, state: RunState, warn: float, flood: float, text: String = "") -> Array:
	match phase(state):
		"flood":
			state.tide["until"] = maxf(float(state.tide.get("until", 0.0)), state.clock + flood)
			return [{"kind": "tide", "text": "Вода не уходит: отлив позже"}]
		"warn":
			return []
	var rng := _rng(state, 1)
	var chosen: Array = []
	var lids: Array = content.locations.keys()
	lids.sort()
	for lid: String in lids:
		if str(content.locations[lid].get("chapter", "")) != state.chapter:
			continue
		var h := height(content, lid)
		if h == "low" or (h == "mid" and rng.randf() < MID_CHANCE):
			chosen.append(lid)
	if chosen.is_empty():
		return []
	state.tide["phase"] = "warn"
	state.tide["at"] = state.clock + maxf(1.0, warn)
	state.tide["flood"] = maxf(1.0, flood)
	state.tide["places"] = chosen
	return [{"kind": "tide_warn", "text": (text + " " if text != "" else "") + "Через %d с — прилив" % int(warn)}]


## Часы прилива: пришла вода, ушла вода. Возвращает события для интерфейса.
static func tick(content: Content, state: RunState) -> Array:
	match phase(state):
		"warn":
			if state.clock >= float(state.tide.get("at", 0.0)):
				return _flood(content, state)
		"flood":
			if state.clock >= float(state.tide.get("until", 0.0)):
				return _ebb(content, state)
	return []


static func _flood(content: Content, state: RunState) -> Array:
	state.tide["phase"] = "flood"
	state.tide["until"] = float(state.tide.get("at", state.clock)) + float(state.tide.get("flood", FLOOD))
	var here := places(state)
	var names := ", ".join(here.map(func(l: String) -> String: return str(content.locations.get(l, {}).get("name", l))))
	var out: Array = [{"kind": "tide_flood", "text": "Прилив! Под водой: %s" % names}]
	var rng := _rng(state, 2)
	for sq: Dictionary in state.squads.duplicate():
		var lid := str(content.missions.get(sq["mission"], {}).get("location", ""))
		if here.has(lid) and str(content.missions.get(sq["mission"], {}).get("type", "")) != "onslaught":
			out.append_array(_caught(content, state, sq, rng))
	for mid: String in MissionFlow.open_missions(state):
		var m: Dictionary = content.missions.get(mid, {})
		if not here.has(str(m.get("location", ""))) or not str(m.get("type", "")) in ["side", "random"]:
			continue
		state.missions[mid]["status"] = "expired"
		out.append({"kind": "expired", "card": mid, "text": "Смыто приливом: %s" % m.get("title", mid)})
	return out


## Вода застала отряд: бегство. Отряд возвращается, миссия сорвана (сюжетная останется ждать отлива).
static func _caught(content: Content, state: RunState, sq: Dictionary, rng: RandomNumberGenerator) -> Array:
	var mid := str(sq["mission"])
	var m: Dictionary = content.missions.get(mid, {})
	var heroes: Array = Array(sq["heroes"]).filter(func(c: String) -> bool: return state.is_alive(c))
	var entries: Array = []
	var ok := true
	var actor := ""
	var chance := 100
	var roll := 0
	if not heroes.is_empty():
		var st := {"name": "Бегство от воды", "req": FLEE_REQ, "tags": FLEE_TAGS}
		var best := MissionForecast.stage_actor(content, state, m, {}, st, heroes)
		actor = str(best["hero"])
		chance = int(best["chance"])
		roll = rng.randi_range(1, 100)
		ok = roll <= chance
		for cid: String in heroes:
			entries.append_array(PsycheRules.change(content, state, cid, FLEE_PSY if ok else FAIL_PSY, "прилив", heroes, rng))
		if not ok:
			var victim: String = heroes[rng.randi_range(0, heroes.size() - 1)]
			EdgeRules.defeat(content, state, victim, MissionFlow.pocket(state, victim), rng, {}, entries)
	state.squads = state.squads.filter(func(s: Dictionary) -> bool: return int(s["id"]) != int(sq["id"]))
	var st2: Dictionary = state.missions.get(mid, {})
	st2["status"] = "open" if str(m.get("type", "")) == "story" else "expired"
	state.missions[mid] = st2
	var who := ", ".join(heroes.map(func(c: String) -> String: return content.card_name(c)))
	var text := ""
	if ok:
		text = "Прилив застал отряд (%s) в «%s» — все выбрались" % [who, m.get("title", mid)]
	else:
		text = "Прилив застал отряд (%s) в «%s» — выбрались не без потерь" % [who, m.get("title", mid)]
	state.log.append({"clock": state.clock, "mission": mid, "text": text})
	return [{"kind": "tide_caught", "squad": int(sq["id"]), "mission": mid, "ok": ok, "hero": actor, "chance": chance,
		"roll": roll, "text": text, "entries": entries}]


## Отлив: новые проходы и новые встречи в местах, где стояла вода.
static func _ebb(content: Content, state: RunState) -> Array:
	var old := places(state)
	var rng := _rng(state, 3)
	var cells: Array = old.map(func(l: String) -> String: return slot(state, l))
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = cells[i]
		cells[i] = cells[j]
		cells[j] = t
	var slots: Dictionary = Dictionary(state.tide.get("slot", {})).duplicate()
	var shift: Dictionary = Dictionary(state.tide.get("shift", {})).duplicate()
	for i in old.size():
		slots[old[i]] = cells[i]
		shift[old[i]] = snappedf(rng.randf_range(-JITTER, JITTER), 0.001)
	state.tide = {"phase": "", "places": [], "slot": slots, "shift": shift, "count": int(state.tide.get("count", 0)) + 1}
	var out: Array = [{"kind": "tide_ebb", "text": "Вода ушла. Лабиринт уже не тот: новые проходы, новые встречи"}]
	for lid: String in old:
		out.append_array(MissionFlow.spawn_random(content, state, lid))
	return out
