class_name Chronicle
extends RefCounted
## Свободный режим главы — «Хроника с якорями» (docs/12 §8, docs/14).
## Глава — карта мест (узлов). Герой стоит в одном месте; переход в соседнее — 1 неделя.
## События живут в местах и открываются только там, где стоит герой.
## Якоря и нити появляются, когда закрыты события из их «after» (или осталось мало недель);
## финальный якорь наступает сам, когда кончился отсчёт: всё незавершённое упущено.

const REST_TRAUMA_SEVERITIES := ["light"]


static func active(state: RunState) -> bool:
	return state.chapter != ""


static func chapter(content: Content, state: RunState) -> Dictionary:
	return content.chapters.get(state.chapter, {})


static func weeks_left(content: Content, state: RunState) -> int:
	var ch := chapter(content, state)
	return int(ch.get("weeks", 0)) - (state.week - state.chapter_start)


static func node_def(content: Content, state: RunState, nid: String) -> Dictionary:
	for n: Dictionary in chapter(content, state).get("nodes", []):
		if n["id"] == nid:
			return n
	return {}


static func neighbors(ch: Dictionary, nid: String) -> Array:
	var out: Array = []
	for l: Array in ch.get("links", []):
		if l[0] == nid:
			out.append(l[1])
		elif l[1] == nid:
			out.append(l[0])
	return out


## Кратчайший путь (без стартового места, с целью). Пусто — недостижимо. Закрытое финальное место — только целью.
static func path(content: Content, state: RunState, to: String) -> Array:
	var ch := chapter(content, state)
	var from := state.node
	if from == to:
		return []
	var prev := {from: ""}
	var queue: Array = [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == to:
			break
		if cur != from and _locked(content, state, cur):
			continue
		for nb: String in neighbors(ch, cur):
			if not prev.has(nb):
				prev[nb] = cur
				queue.append(nb)
	if not prev.has(to):
		return []
	var out: Array = []
	var step := to
	while step != from:
		out.push_front(step)
		step = prev[step]
	return out


## Финальное место закрыто до наступления финального якоря.
static func _locked(content: Content, state: RunState, nid: String) -> bool:
	return str(node_def(content, state, nid).get("kind", "")) == "final" and not state.events.has(str(chapter(content, state).get("final", "")))


static func event_node(content: Content, state: RunState, eid: String) -> String:
	var st: Dictionary = state.events.get(eid, {})
	if st.has("node"):
		return str(st["node"])
	return str(content.events.get(eid, {}).get("node", ""))


## Событие можно открыть: вне хроники — всегда, в хронике — только в месте героя.
static func can_open(content: Content, state: RunState, eid: String) -> bool:
	return not active(state) or event_node(content, state, eid) == state.node


static func is_camp(content: Content, state: RunState) -> bool:
	return active(state) and str(node_def(content, state, state.node).get("kind", "")) == "camp"


# --- ход главы ----------------------------------------------------------------

## Начало главы: старые события уходят с карты, герой — в стартовом месте, появляются стартовые якоря.
static func start_chapter(content: Content, state: RunState, cid: String, rng: RandomNumberGenerator) -> Array:
	var ch: Dictionary = content.chapters.get(cid, {})
	if ch.is_empty():
		push_error("Нет главы %s" % cid)
		return []
	for eid: String in state.active_event_ids():
		state.events[eid]["status"] = "expired"
	state.pending_story = {}
	state.chapter = cid
	state.region = str(ch.get("region", state.region))
	state.arc = str(ch.get("arc", state.arc))
	state.node = str(ch.get("start_node", ""))
	# отсчёт идёт с первой недели главы (ход, открывший главу, ещё сдвинет неделю)
	state.chapter_start = state.week + 1
	state.log.append({"week": state.week, "text": "Новая глава: %s" % ch.get("title", cid)})
	var out: Array = [{"kind": "story", "text": "Новая глава: %s · до срока %d нед." % [ch.get("title", cid), int(ch.get("weeks", 0))]}]
	out.append_array(unlock(content, state, rng))
	return out


## Открывает якоря и нити, чьи условия выполнены; по окончании отсчёта — финальный якорь.
static func unlock(content: Content, state: RunState, rng: RandomNumberGenerator) -> Array:
	var ch := chapter(content, state)
	var out: Array = []
	var left := weeks_left(content, state)
	var final_id := str(ch.get("final", ""))
	if final_id != "" and state.events.has(final_id):
		return out   # финал наступил — глава больше не растёт
	if final_id != "" and left <= 0:
		return _final(content, state, final_id, rng)
	for a: Dictionary in Array(ch.get("anchors", [])) + Array(ch.get("threads", [])):
		var eid := str(a["event"])
		if state.events.has(eid) or not content.events.has(eid):
			continue
		var ready := true
		for dep: String in a.get("after", []):
			if str(state.events.get(dep, {}).get("status", "")) != "closed":
				ready = false
		if a.has("or_weeks_left") and left <= int(a["or_weeks_left"]):
			ready = true
		if ready:
			out.append_array(EventFlow.spawn(content, state, eid, rng))
	return out


static func _final(content: Content, state: RunState, final_id: String, rng: RandomNumberGenerator) -> Array:
	var missed: Array = []
	for eid: String in state.active_event_ids():
		state.events[eid]["status"] = "missed"
		missed.append(str(content.events.get(eid, {}).get("title", eid)))
	var out: Array = []
	var fnode := str(content.events.get(final_id, {}).get("node", state.node))
	state.node = fnode
	out.append({"kind": "story", "text": "Срок настал. Всех ведут в «%s»." % node_def(content, state, fnode).get("name", fnode)})
	if not missed.is_empty():
		out.append({"kind": "lost", "text": "Упущено: %s" % ", ".join(missed)})
	out.append_array(EventFlow.spawn(content, state, final_id, rng))
	return out


## Переход героя в место to (по кратчайшему пути, неделя за шаг).
static func move(content: Content, state: RunState, to: String, rng: RandomNumberGenerator) -> Dictionary:
	if not active(state):
		return {"ok": false, "reason": "Свободного режима нет"}
	if node_def(content, state, to).is_empty():
		return {"ok": false, "reason": "Нет такого места"}
	if _locked(content, state, to):
		return {"ok": false, "reason": "«%s» закрыт до срока" % node_def(content, state, to).get("name", to)}
	var steps := path(content, state, to)
	if steps.is_empty():
		return {"ok": false, "reason": "Туда не пройти"}
	var entries: Array = []
	var walked := 0
	for step: String in steps:
		state.node = step
		walked += 1
		var final_id := str(chapter(content, state).get("final", ""))
		var had_final := state.events.has(final_id)
		entries.append_array(EventFlow.advance_week(content, state, rng, false))
		if not had_final and state.events.has(final_id):
			break   # наступил срок — героя увели в финальное место
	state.log.append({"week": state.week, "text": "Переход: %s" % node_def(content, state, state.node).get("name", state.node)})
	state.rng_state = rng.state
	return {"ok": true, "entries": entries, "weeks": walked, "state": state}


## Отдых в лагере: неделя проходит, у живых персонажей снимается одна лёгкая травма.
static func rest(content: Content, state: RunState, rng: RandomNumberGenerator) -> Dictionary:
	if not is_camp(content, state):
		return {"ok": false, "reason": "Отдыхать можно только в лагере"}
	var entries: Array = []
	for cid: String in state.collection:
		if content.card_kind(cid) == "character" and state.is_alive(cid):
			var had: int = state.character(cid).get("traumas", []).size()
			var r := EffectApplier.apply(content, state, {"cmd": "remove_trauma", "severities": REST_TRAUMA_SEVERITIES, "target": cid}, cid, rng)
			if state.character(cid).get("traumas", []).size() < had:
				entries.append_array(r)
	entries.append_array(EventFlow.advance_week(content, state, rng, false))
	state.log.append({"week": state.week, "text": "Отдых в лагере"})
	state.rng_state = rng.state
	return {"ok": true, "entries": entries, "weeks": 1, "state": state}
