class_name MissionFlow
extends RefCounted
## Миссии и отряды (docs/15): открытые миссии, свободные герои, выход отряда (пути нет — сразу на месте),
## действия после прибытия, сроки и встречи мест по дням. Итог действия считает MissionResolver, прогноз —
## MissionForecast; дни, неделя и лагерь-стоянка — DayRules (docs/16 §12).

const SCOUT_TAGS := ["Выслеживание", "Тень"]   # разведчик в отряде раскрывает скрытые теги заранее
const DEFAULT_REST := 20.0


## Новое прохождение в режиме миссий: Санни и сюжетные миссии главы с отметкой start.
static func new_run(content: Content, seed_value: int, chapter: String = "nightmare") -> RunState:
	var s := RunState.new()
	s.mode = "missions"
	s.chapter = chapter
	s.region = "mountain_pass"
	s.resources = {"shards": 10}
	s.rng_seed = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	s.rng_state = rng.state
	EffectApplier.add_card(content, s, "P01")
	open_chapter(content, s, chapter)
	s.log.append({"week": 0, "text": "Начало прохождения"})
	return s


## Открывает стартовые миссии главы и заводит таймеры случайных миссий её локаций.
static func open_chapter(content: Content, state: RunState, chapter: String) -> Array:
	state.chapter = chapter
	TerrainRules.reset(state)
	ZoneRules.reset(state)
	MoverRules.reset(content, state)
	MapEventRules.reset(state)
	DeckRules.ensure(content, state, chapter)   # колода событий главы (docs/16 §11.4)
	var out: Array = []
	for mid: String in _sorted(content.missions):
		var m: Dictionary = content.missions[mid]
		if bool(m.get("start", false)) and chapter_of(content, mid) == chapter:
			out.append_array(open(content, state, mid))
			if state.party_at == "":
				state.party_at = str(m.get("location", ""))   # отряд начинает главу у первой миссии
				TravelRules.visit(state, state.party_at)
	for lid: String in _sorted(content.locations):
		var loc: Dictionary = content.locations[lid]
		var every := int(loc.get("random", {}).get("every", 0))
		if str(loc.get("chapter", "")) == chapter and every > 0:
			state.loc_timers[lid] = state.day + every
	out.append_array(DayPlanner.ensure(content, state))   # в первый же день есть чем заняться (docs/17 §4)
	return out


## Переход к следующей главе после миссии с end_chapter и next_chapter: новая карта, её стартовые миссии.
static func start_chapter(content: Content, state: RunState, chapter: String) -> Array:
	state.demo_complete = false
	state.flags.erase("next_chapter")
	# незавершённое прошлой главы остаётся в прошлом
	for mid: String in state.missions.keys():
		if str(state.missions[mid].get("status", "")) != "done" and chapter_of(content, mid) != chapter:
			state.missions.erase(mid)
	state.squads.clear()
	state.rest_until.clear()
	state.loc_timers.clear()
	state.tide = {}
	state.day = 1            # неделя новой главы начинается сначала
	state.party_at = ""
	state.camp = {}
	for k: String in ["visited", "scouted", "steps", "tasks_done", "watch"]:
		state.flags.erase(k)
	GateRules.reset(state)
	for cid: String in state.characters:
		state.characters[cid]["sorties"] = 0
	for lid: String in _sorted(content.locations):
		if str(content.locations[lid].get("chapter", "")) == chapter:
			state.region = str(content.locations[lid].get("region", state.region))
			break
	state.log.append({"clock": state.clock, "text": "Новая глава: %s" % chapter})
	return open_chapter(content, state, chapter)


static func chapter_of(content: Content, mission_id: String) -> String:
	var lid := str(content.missions.get(mission_id, {}).get("location", ""))
	return str(content.locations.get(lid, {}).get("chapter", ""))


## Открывает миссию. Миссии колоды главы, не выпавшие в этом прохождении, не открываются (DeckRules);
## force — открыть всё равно (снимки, тесты).
static func open(content: Content, state: RunState, mission_id: String, force: bool = false) -> Array:
	if not content.missions.has(mission_id):
		return []
	if not force and not DeckRules.allowed(content, state, mission_id):
		return []
	var cur: Dictionary = state.missions.get(mission_id, {})
	if cur.get("status", "") in ["open", "active"]:
		return []
	state.missions[mission_id] = {"status": "open", "attempts": int(cur.get("attempts", 0)), "opened_at": state.clock, "opened_day": state.day}
	# модификаторы (docs/16 §11.2): у побочных и случайных миссий основных глав
	var mods := ModifierRules.roll(content, state, mission_id)
	var extra := ""
	if not mods.is_empty():
		state.missions[mission_id]["mods"] = mods
		extra = " · " + ", ".join(mods.map(func(x: String) -> String: return str(ModifierRules.def(content, x).get("name", x))))
	return [{"kind": "mission", "text": "Новая миссия: %s%s" % [content.missions[mission_id].get("title", mission_id), extra], "card": mission_id}]


static func open_missions(state: RunState) -> Array:
	var out: Array = []
	for mid: String in _sorted(state.missions):
		if state.missions[mid].get("status", "") == "open":
			out.append(mid)
	return out


# --- герои --------------------------------------------------------------------

## Живые персонажи в коллекции.
static func heroes(content: Content, state: RunState) -> Array:
	var out: Array = []
	for card: String in state.collection:
		if content.card_kind(card) == "character" and state.is_alive(card):
			out.append(card)
	return out


## "" — герой свободен; иначе причина («на миссии»).
static func busy_reason(content: Content, state: RunState, cid: String) -> String:
	if not state.is_alive(cid):
		return "погиб"
	for sq: Dictionary in state.squads:
		if Array(sq.get("heroes", [])).has(cid):
			return "на миссии"
	if DayRules.exhausted(content, state, cid):
		return "выдохся — до ночи"
	return ""


static func on_mission(state: RunState, cid: String) -> bool:
	for sq: Dictionary in state.squads:
		if Array(sq.get("heroes", [])).has(cid):
			return true
	return false


## Кармашек героя на миссии не меняется: ни его, ни усилений, которые ушли с другим отрядом.
static func pocket_lock(content: Content, state: RunState, cid: String, card: String) -> String:
	if on_mission(state, cid):
		return "%s на миссии — кармашек не поменять" % content.card_name(cid)
	for other: String in state.characters:
		if other != cid and on_mission(state, other) and Array(state.characters[other].get("pocket", [])).has(card):
			return "%s сейчас на миссии у героя %s" % [content.card_name(card), content.card_name(other)]
	return ""


## Чей кармашек держит усиление ("" — ничей).
static func pocket_owner(state: RunState, card: String) -> String:
	for cid: String in state.characters:
		if Array(state.characters[cid].get("pocket", [])).has(card):
			return cid
	return ""


static func free_heroes(content: Content, state: RunState) -> Array:
	var out: Array = []
	for cid: String in heroes(content, state):
		if busy_reason(content, state, cid) == "":
			out.append(cid)
	return out


## Усиления из кармашка героя, которые ещё в коллекции.
static func pocket(state: RunState, cid: String) -> Array:
	var out: Array = []
	for card: String in state.character(cid).get("pocket", []):
		if state.owns(card):
			out.append(card)
	return out


## Боевые теги героя: стадия + кармашек.
static func hero_tags(content: Content, state: RunState, cid: String) -> Array:
	var out: Array = []
	var c: Dictionary = content.characters.get(cid, {})
	var stage := str(state.character(cid).get("stage", ""))
	for t: String in c.get("stages", {}).get(stage, {}).get("tags", c.get("tags", [])):
		if not out.has(t):
			out.append(t)
	for card: String in pocket(state, cid):
		for t: String in content.enhancements.get(card, {}).get("tags", []):
			if not out.has(t):
				out.append(t)
	# развитие тегов может снять или дать тег (docs/16 §8)
	var ch := GrowthRules.tag_changes(content, state, cid)
	for t: String in ch["remove"]:
		out.erase(t)
	for t: String in ch["add"]:
		if not out.has(t):
			out.append(t)
	return out


static func squad_tags(content: Content, state: RunState, heroes_ids: Array) -> Array:
	var out: Array = []
	for cid: String in heroes_ids:
		for t: String in hero_tags(content, state, cid):
			if not out.has(t):
				out.append(t)
	return out


static func has_scout(content: Content, state: RunState, heroes_ids: Array) -> bool:
	if BondRules.reveals(content, state, heroes_ids) or GrowthRules.reveals(content, state, heroes_ids):
		return true
	var tags := squad_tags(content, state, heroes_ids)
	for t: String in SCOUT_TAGS:
		if tags.has(t):
			return true
	return false


# --- запуск и часы --------------------------------------------------------------------

## Сколько героев нужно в отряд: у сюжета — не больше, чем живых героев (спутники погибли — сюжет не встаёт, docs/17).
static func squad_min(content: Content, state: RunState, mission_id: String) -> int:
	var m: Dictionary = content.missions.get(mission_id, {})
	var need := int(m.get("squad", {}).get("min", 1))
	if str(m.get("type", "")) == "story":
		need = mini(need, maxi(1, heroes(content, state).size()))
	return need


## "" — отряд можно отправить; иначе причина для игрока.
static func can_launch(content: Content, state: RunState, mission_id: String, heroes_ids: Array) -> String:
	if state.game_over:
		return "Прохождение окончено"
	if state.missions.get(mission_id, {}).get("status", "") != "open":
		return "Миссия недоступна"
	var m: Dictionary = content.missions.get(mission_id, {})
	if TideRules.mission_flooded(content, state, mission_id):
		return "Под водой — ждите отлива"
	if not state.squads.is_empty():
		return "Отряд уже на миссии — сначала решите, что он делает"
	# фигура (docs/18): события — только там, где она стоит (Натиск приходит к ней сам)
	if FigureRules.on(content, state) and FigureRules.reach(content, state, mission_id) != 0:
		return "Событие не здесь — поставьте фигуру на этот участок (шаг — полдня)"
	if not DayRules.mission_reachable(content, state, mission_id):
		return TravelRules.why_not(content, state, str(m.get("location", "")))
	var sq: Dictionary = m.get("squad", {})
	var min_n := squad_min(content, state, mission_id)
	if heroes_ids.size() < min_n:
		return "Нужно героев: не меньше %d" % min_n
	if heroes_ids.size() > int(sq.get("max", 1)):
		return "Мест в отряде: %d" % int(sq.get("max", 1))
	var seen := {}
	for cid: String in heroes_ids:
		if seen.has(cid):
			return "Герой указан дважды"
		seen[cid] = true
		if not heroes(content, state).has(cid):
			return "%s не может идти" % content.card_name(cid)
		if excluded(content, mission_id, cid):
			return "%s не может идти на эту миссию" % content.card_name(cid)
		var why := busy_reason(content, state, cid)
		if why != "":
			return "%s: %s" % [content.card_name(cid), why]
	for need: String in m.get("requires_heroes", []):
		if not heroes_ids.has(need):
			return "Нужен в отряде: %s" % content.card_name(need)
	# вражда (доверие −3) не пускает в один отряд — кроме сюжета: там идут через силу, иначе глава встанет
	if str(m.get("type", "")) == "story":
		return ""
	return TrustRules.refusal(content, state, heroes_ids)


## Отправляет отряд: пути нет — он сразу на месте (фаза arrived), лагерь переезжает туда,
## герои устают (DayRules.on_launch). Возвращает {ok, error, squad, entries}.
static func launch(content: Content, state: RunState, mission_id: String, heroes_ids: Array) -> Dictionary:
	var err := can_launch(content, state, mission_id, heroes_ids)
	if err != "":
		return {"ok": false, "error": err}
	var sq := {
		"id": state.next_squad, "mission": mission_id, "heroes": heroes_ids.duplicate(),
		"launched_at": state.clock, "arrive_at": state.clock, "day": state.day, "phase": "arrived",
	}
	state.next_squad += 1
	for cid: String in heroes_ids:
		CampRules.take(state, cid)
	# миссия дальше лагеря: отряд идёт по маршруту (шаги дня, марш-бросок сверх бесплатных) — docs/17 §2
	var entries: Array = []
	var lid := str(content.missions.get(mission_id, {}).get("location", ""))
	if DayRules.restricted(content, state) and lid != state.party_at and str(content.missions[mission_id].get("type", "")) != "onslaught" \
			and not FigureRules.on(content, state):
		TravelRules.travel(content, state, lid, entries)
	entries.append_array(DayRules.on_launch(content, state, mission_id, heroes_ids))
	state.squads.append(sq)
	state.missions[mission_id]["status"] = "active"
	return {"ok": true, "error": "", "squad": sq, "entries": entries}


static func squad(state: RunState, squad_id: int) -> Dictionary:
	for sq: Dictionary in state.squads:
		if int(sq["id"]) == squad_id:
			return sq
	return {}


## Игровые часы идут вперёд на dt секунд: отряды прибывают, герои отдыхают, появляются случайные миссии.
## Возвращает события для интерфейса: [{kind: "arrived"|"rested"|"mission", ...}].
## (устар.) Часов больше нет — время идёт днями (DayRules.end_day), отряд сразу на месте. Оставлено для
## старых вызовов (тесты, снимки): ничего не делает.
static func tick(_content: Content, _state: RunState, _dt: float) -> Array:
	return []


## Сроки по дням (DayRules.end_day): миссия уходит, когда прошло её `expires` дней с открытия.
static func expire_day(content: Content, state: RunState) -> Array:
	var out: Array = []
	for mid: String in _sorted(state.missions):
		var stt: Dictionary = state.missions[mid]
		var exp := ModifierRules.expires(content, state, mid)
		if exp > 0 and str(stt.get("status", "")) == "open" and state.day >= int(stt.get("opened_day", 1)) + exp:
			stt["status"] = "expired"
			out.append({"kind": "expired", "card": mid, "text": "Упущено: %s" % content.missions[mid].get("title", mid)})
			if str(content.missions[mid].get("type", "")) == "onslaught":
				out.append_array(OnslaughtRules.expire(content, state, mid))
	return out


## Встречи мест раз в `random.every` дней (DayRules.end_day).
static func spawn_day(content: Content, state: RunState) -> Array:
	var out: Array = []
	for lid: String in _sorted(state.loc_timers):
		if int(state.loc_timers[lid]) <= state.day:
			var loc: Dictionary = content.locations.get(lid, {})
			out.append_array(spawn_random(content, state, lid))
			state.loc_timers[lid] = state.day + maxi(1, int(loc.get("random", {}).get("every", 2)))
	return out


## Локация «достигнута»: сюжет уже открывал здесь хотя бы одну не случайную миссию.
static func reached(content: Content, state: RunState, lid: String) -> bool:
	for mid: String in state.missions:
		var m: Dictionary = content.missions.get(mid, {})
		if str(m.get("location", "")) == lid and str(m.get("type", "")) != "random":
			return true
	return false


## Случайная миссия локации: первая по порядку из пула, которая сейчас не открыта и выпала в колоде.
## Только там, куда сюжет уже привёл (не спойлерим места раньше времени).
static func spawn_random(content: Content, state: RunState, lid: String) -> Array:
	if not reached(content, state, lid):
		return []
	for mid: String in content.locations.get(lid, {}).get("random", {}).get("pool", []):
		var st := str(state.missions.get(mid, {}).get("status", ""))
		var m: Dictionary = content.missions.get(mid, {})
		if st in ["open", "active"]:
			continue
		if st in ["done", "expired", "closed"] and str(m.get("type", "")) != "random":
			continue
		if not DeckRules.allowed(content, state, mid):
			continue
		return open(content, state, mid)
	return []


## После завершения миссии: счётчик, миссии «после N миссий», случайные «после N» у локаций.
static func after_completion(content: Content, state: RunState) -> Array:
	var out: Array = []
	state.completed_missions += 1
	var n := state.completed_missions
	for mid: String in _sorted(content.missions):
		var m: Dictionary = content.missions[mid]
		var need := int(m.get("unlock", {}).get("after_missions", 0))
		if need > 0 and n >= need and not state.missions.has(mid) and chapter_of(content, mid) == state.chapter:
			out.append_array(open(content, state, mid))
		# «после всех»: миссия открывается, когда выполнены все перечисленные (и закрыто Врат / зачищено районов)
		if not state.missions.has(mid) and chapter_of(content, mid) == state.chapter and _after_all_done(state, m) \
				and _unlock_short(state, m) == "":
			out.append_array(open(content, state, mid))
	for lid: String in _sorted(content.locations):
		var loc: Dictionary = content.locations[lid]
		var every_n := int(loc.get("random", {}).get("after_missions", 0))
		if every_n > 0 and str(loc.get("chapter", "")) == state.chapter and n % every_n == 0:
			out.append_array(spawn_random(content, state, lid))
	return out


static func _after_all_done(state: RunState, m: Dictionary) -> bool:
	var all: Array = m.get("unlock", {}).get("after_all", [])
	return not all.is_empty() and all.all(func(x: String) -> bool: return str(state.missions.get(x, {}).get("status", "")) == "done")


## Чего не хватает миссии с unlock.after_all ("" — хватает): закрытых Врат (Город, GateRules), зачищенных районов
## (Мрачный город, ZoneRules) — для строки «сюжет ждёт».
static func _unlock_short(state: RunState, m: Dictionary) -> String:
	var u: Dictionary = m.get("unlock", {})
	var g := int(u.get("gates_closed", 0))
	var gh := int(state.flags.get("gates_closed", 0))
	if gh < g:
		return "закрыть Врата: %d из %d" % [gh, g]
	var z := int(u.get("zones_cleared", 0))
	var zh := ZoneRules.cleared_total(state)
	if zh < z:
		return "зачистить районы: %d из %d" % [zh, z]
	return ""


## Чего ждёт сюжет главы ("" — ничего не ждёт): следующая сюжетная миссия готова, но не хватает Врат или районов.
static func story_wait(content: Content, state: RunState) -> String:
	for mid: String in _sorted(content.missions):
		var m: Dictionary = content.missions[mid]
		if state.missions.has(mid) or chapter_of(content, mid) != state.chapter or not _after_all_done(state, m):
			continue
		var w := _unlock_short(state, m)
		if w != "":
			return "Сюжет ждёт — " + w
	return ""


# --- действия после прибытия -------------------------------------------------------------

## Сколько дней осталось до ухода миссии, считая сегодняшний (-1 — не устаревает). 1 — уйдёт этой ночью.
static func expires_in(content: Content, state: RunState, mission_id: String) -> int:
	var exp := ModifierRules.expires(content, state, mission_id)
	var st: Dictionary = state.missions.get(mission_id, {})
	if exp <= 0 or str(st.get("status", "")) != "open":
		return -1
	return maxi(1, int(st.get("opened_day", state.day)) + exp - state.day)


static func boss_stage(state: RunState, m: Dictionary, st: Dictionary) -> Dictionary:
	var phases: Array = m.get("boss", {}).get("phases", [])
	if phases.is_empty() or not st.has("combat"):
		return st
	var ph: Dictionary = phases[clampi(int(state.missions.get(str(m.get("id", "")), {}).get("phase", 0)), 0, phases.size() - 1)]
	if not ph.has("field"):
		return st
	var out := st.duplicate(true)
	out["combat"]["field"] = str(ph["field"])
	return out


## Какую карту отряд отдаст за действие с ценой-жертвой ("" — нечего отдать).
static func sacrifice_card(content: Content, state: RunState, a: Dictionary, heroes_ids: Array) -> String:
	var cost: Dictionary = a.get("cost", {})
	if not cost.has("sacrifice") and not cost.has("sacrifice_tag"):
		return ""
	for cid: String in heroes_ids:
		for card: String in pocket(state, cid):
			if cost.has("sacrifice") and card == str(cost["sacrifice"]):
				return card
			if cost.has("sacrifice_tag") and Array(content.enhancements.get(card, {}).get("tags", [])).has(str(cost["sacrifice_tag"])):
				return card
	return ""


## Незавершённая сюжетная миссия главы, без которой не обойтись без этого героя (`requires_heroes`).
## Его гибель обрывает сюжет — прохождение окончено. "" — герой сюжету не обязателен.
static func key_mission_for(content: Content, state: RunState, cid: String) -> String:
	for mid: String in _sorted(content.missions):
		var m: Dictionary = content.missions[mid]
		if str(m.get("type", "")) != "story" or chapter_of(content, mid) != state.chapter:
			continue
		if str(state.missions.get(mid, {}).get("status", "")) == "done":
			continue
		if Array(m.get("requires_heroes", [])).has(cid):
			return str(m.get("title", mid))
	return ""


## Герой не может идти на эту миссию (`exclude_heroes`: сюжет — например, беда случилась с ним самим).
static func excluded(content: Content, mission_id: String, cid: String) -> bool:
	return Array(content.missions.get(mission_id, {}).get("exclude_heroes", [])).has(cid)


## [{action, available, reason}] для прибывшего отряда: особые действия открывают теги отряда
## (`requires_any`) или конкретный герой в отряде (`requires_hero`).
static func actions_for(content: Content, state: RunState, mission_id: String, heroes_ids: Array) -> Array:
	var tags := squad_tags(content, state, heroes_ids)
	var out: Array = []
	for a: Dictionary in content.missions.get(mission_id, {}).get("actions", []):
		var need: Array = a.get("requires_any", [])
		var ok := need.is_empty()
		for t: String in need:
			if tags.has(t):
				ok = true
				break
		var reason := "" if ok else "Нужен тег: %s" % " или ".join(need)
		var who: Array = a.get("requires_hero", [])
		if ok and not who.is_empty():
			ok = who.any(func(cid: String) -> bool: return heroes_ids.has(cid))
			if not ok:
				reason = "Нужен в отряде: %s" % " или ".join(who.map(func(cid: String) -> String: return content.card_name(cid)))
		# доверие в отряде (docs/16 §5)
		var tneed: Dictionary = a.get("requires_trust", {})
		if ok and not tneed.is_empty() and not TrustRules.meets(state, heroes_ids, tneed):
			ok = false
			reason = "Нужно доверие %d%s" % [int(tneed.get("min", TrustRules.HIGH)),
				(" между %s и %s" % [content.card_name(tneed["pair"][0]), content.card_name(tneed["pair"][1])]) if Array(tneed.get("pair", [])).size() == 2 else " в отряде"]
		# Гордыня в панике не даёт отступить (docs/16 §7)
		if ok and bool(a.get("retreat", false)):
			var proud := PsycheRules.refuses_retreat(content, state, heroes_ids)
			if proud != "":
				ok = false
				reason = "%s в панике и не отступит" % proud
		# жертва карты из кармашка отряда (docs/16 §3)
		var cost: Dictionary = a.get("cost", {})
		if ok and (cost.has("sacrifice") or cost.has("sacrifice_tag")) and sacrifice_card(content, state, a, heroes_ids) == "":
			ok = false
			reason = "Нужно отдать: %s" % (content.card_name(str(cost["sacrifice"])) if cost.has("sacrifice") else "усиление с тегом «%s»" % cost["sacrifice_tag"])
		# условия и цена — как у вариантов событий (ConditionChecker); исполнитель — первый в отряде
		if ok and (a.has("conditions") or a.has("cost")):
			var pockets: Array = []
			for cid: String in heroes_ids:
				pockets.append_array(pocket(state, cid))
			var block := ConditionChecker.blockers(content, state, a, str(heroes_ids[0]) if not heroes_ids.is_empty() else "", pockets)
			if not block.is_empty():
				ok = false
				reason = "; ".join(block)
		out.append({"action": a, "available": ok, "reason": reason})
	return out


static func action(content: Content, mission_id: String, action_id: String) -> Dictionary:
	for a: Dictionary in content.missions.get(mission_id, {}).get("actions", []):
		if str(a.get("id", "")) == action_id:
			return a
	return {}


static func _sorted(d: Dictionary) -> Array:
	var keys: Array = d.keys()
	keys.sort()
	return keys
