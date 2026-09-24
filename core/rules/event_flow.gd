class_name EventFlow
extends RefCounted
## Появление событий: сюжет (с задержкой 0–2 недели), случайные (30% в неделю),
## инициаторы (одно конкретное событие). Новое прохождение.

const RANDOM_EVENT_CHANCE := 30
const STORY_DELAY_MAX := 2


static func new_run(content: Content, seed_value: int) -> RunState:
	var s := RunState.new()
	var start: Dictionary = content.regions.get("mountain_pass", {})
	s.arc = str(start.get("arc", "nightmare"))
	s.region = "mountain_pass"
	s.resources = {"shards": 10, "mana": 10}
	s.rng_seed = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	s.rng_state = rng.state
	for card: String in ["P01", "I01"]:
		EffectApplier.add_card(content, s, card)
	s.log.append({"week": 1, "text": "Начало прохождения"})
	return s


## Ставит событие на карту и применяет его on_appear.
static func spawn(content: Content, state: RunState, event_id: String, rng: RandomNumberGenerator) -> Array:
	var ev: Dictionary = content.events.get(event_id, {})
	if ev.is_empty():
		push_error("Событие %s не найдено" % event_id)
		return []
	state.events[event_id] = {"status": "active", "done_options": [], "spawned_week": state.week}
	# в свободном режиме событие без своего места появляется там, где стоит герой
	if Chronicle.active(state) and str(ev.get("node", "")) == "":
		state.events[event_id]["node"] = state.node
	var out: Array = [{"kind": "event", "text": "Новое событие: %s" % str(ev.get("title", event_id)), "card": event_id}]
	out.append_array(EffectApplier.apply_all(content, state, ev.get("on_appear", []), "P01", rng))
	return out


static func schedule_story(content: Content, state: RunState, next_id: String, immediate: bool,
		rng: RandomNumberGenerator) -> Array:
	if next_id == "" or not content.events.has(next_id):
		return []
	var delay := 0 if immediate else rng.randi_range(0, STORY_DELAY_MAX)
	if delay == 0:
		state.pending_story = {}
		return spawn(content, state, next_id, rng)
	state.pending_story = {"event_id": next_id, "weeks_left": delay}
	return [{"kind": "pending", "text": "Надвигается следующая глава…"}]


## Прошла неделя: отсчёт ожидающего сюжета и шанс случайного события.
## story_scheduled_now — сюжет был назначен в этом же ходу (его отсчёт начнётся со следующего).
static func advance_week(content: Content, state: RunState, rng: RandomNumberGenerator,
		story_scheduled_now: bool) -> Array:
	var out: Array = []
	state.week += 1
	if not state.pending_story.is_empty() and not story_scheduled_now:
		state.pending_story["weeks_left"] = int(state.pending_story["weeks_left"]) - 1
		if int(state.pending_story["weeks_left"]) <= 0:
			var eid: String = state.pending_story["event_id"]
			state.pending_story = {}
			out.append_array(spawn(content, state, eid, rng))
	if rng.randi_range(1, 100) <= RANDOM_EVENT_CHANCE:
		out.append_array(spawn_random(content, state, rng))
	if Chronicle.active(state):
		out.append_array(Chronicle.unlock(content, state, rng))
	out.append_array(ensure_not_stuck(content, state, rng))
	return out


## Защита от тупика: если на карте нет ни одного доступного варианта,
## ожидающее сюжетное событие появляется сразу.
static func ensure_not_stuck(content: Content, state: RunState, rng: RandomNumberGenerator) -> Array:
	if not state.pending_story.is_empty() and not has_actionable_event(content, state):
		var eid: String = state.pending_story["event_id"]
		state.pending_story = {}
		return spawn(content, state, eid, rng)
	return []


## Есть ли на карте вариант, который можно выбрать хоть каким-то живым персонажем.
## Условие «приложите карту» считается выполнимым, если карта есть в коллекции.
static func has_actionable_event(content: Content, state: RunState) -> bool:
	var owned_chars: Array = []
	for card: String in state.collection:
		if content.card_kind(card) == "character" and state.is_alive(card):
			owned_chars.append(card)
	var owned_enh: Array = []
	for card: String in state.collection:
		if content.card_kind(card) == "enhancement":
			owned_enh.append(card)
	for eid: String in state.active_event_ids():
		for o: Dictionary in content.events.get(eid, {}).get("options", []):
			if state.is_option_done(eid, str(o["id"])):
				continue
			for cid: String in owned_chars:
				if ConditionChecker.blockers(content, state, o, cid, owned_enh).is_empty():
					return true
	return false


static func spawn_random(content: Content, state: RunState, rng: RandomNumberGenerator) -> Array:
	var pool: Array = content.regions.get(state.region, {}).get("random_pool", [])
	if pool.is_empty():
		return []
	var used: Array = state.random_used.get(state.region, [])
	var candidates := _random_candidates(content, state, pool, used)
	if candidates.is_empty():
		# Круг пула исчерпан — перемешиваем заново (кроме одноразовых).
		used = []
		for eid: String in state.random_used.get(state.region, []):
			if bool(content.events.get(eid, {}).get("once", false)):
				used.append(eid)
		candidates = _random_candidates(content, state, pool, used)
	if candidates.is_empty():
		return []
	var pick: String = candidates[rng.randi_range(0, candidates.size() - 1)]
	used.append(pick)
	state.random_used[state.region] = used
	return spawn(content, state, pick, rng)


static func _random_candidates(content: Content, state: RunState, pool: Array, used: Array) -> Array:
	var out: Array = []
	for eid: String in pool:
		if used.has(eid) or state.is_event_active(eid) or not content.events.has(eid):
			continue
		out.append(eid)
	return out


## Инициатор: исчезает и создаёт одно конкретное событие. Время не идёт.
static func use_initiator(content: Content, state: RunState, card: String, rng: RandomNumberGenerator) -> Dictionary:
	var ini: Dictionary = content.initiators.get(card, {})
	if ini.is_empty() or not state.owns(card):
		return {"ok": false, "reason": "Нет такого инициатора"}
	var eid: String = ini.get("event", "")
	if state.is_event_active(eid):
		return {"ok": false, "reason": "Это событие уже на карте"}
	state.collection.erase(card)
	state.note(card, "Применён: появилось событие «%s»" % content.events.get(eid, {}).get("title", eid))
	var entries := spawn(content, state, eid, rng)
	state.log.append({"week": state.week, "text": "Применён инициатор «%s»" % content.card_name(card)})
	return {"ok": true, "event_id": eid, "entries": entries}
