class_name SimBot
extends RefCounted
## Простой бот для симуляции прохождения среза: проверяет, что игра не застревает,
## и собирает статистику для баланса (Фаза 1).


static func play(c: Content, seed_value: int, max_turns: int = 300) -> Dictionary:
	var s := EventFlow.new_run(c, seed_value)
	var rng := RandomNumberGenerator.new()
	rng.seed = s.rng_seed
	rng.state = s.rng_state
	EventFlow.use_initiator(c, s, "I01", rng)
	s.rng_state = rng.state
	var turns := 0
	var stuck := false
	var max_traumas := 0
	while turns < max_turns and not s.game_over and not s.demo_complete:
		_use_initiators(c, s)
		var move := _choose(c, s)
		if move.is_empty():
			stuck = true
			break
		var r: Dictionary
		if str(c.option(move["event"], move["option"]).get("check", "")) == "combat":
			r = play_combat(c, s, move["event"], move["option"], move["draft"])
		else:
			r = TurnResolver.resolve(c, s, move["event"], move["option"], move["draft"], move["extras"])
		if not r["ok"]:
			stuck = true
			break
		s = r["state"]
		turns += 1
		max_traumas = maxi(max_traumas, Array(s.characters["P01"]["traumas"]).size())
	return {"turns": turns, "weeks": s.week, "dead": s.game_over, "done": s.demo_complete,
		"stuck": stuck, "max_traumas": max_traumas, "shards": s.resources["shards"], "mana": s.resources["mana"],
		"lost_items": _count_lost(s)}


static func _count_lost(s: RunState) -> int:
	var n := 0
	for e: Dictionary in s.log:
		if e.has("broken"):
			n += 1
	return n


static func _use_initiators(c: Content, s: RunState) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = s.rng_seed
	rng.state = s.rng_state
	var traumas: Array = s.characters["P01"]["traumas"]
	if s.owns("I02") and traumas.size() >= 2:
		EventFlow.use_initiator(c, s, "I02", rng)
	if s.owns("I03"):
		EventFlow.use_initiator(c, s, "I03", rng)
	s.rng_state = rng.state


## Выбирает ход: сюжет, если шанс приличный; иначе подготовка или лечение.
static func _choose(c: Content, s: RunState) -> Dictionary:
	var enh: Array = []
	for card: String in s.collection:
		if c.card_kind(card) == "enhancement" and enh.size() < 3:
			enh.append(card)
	var best := {}
	var best_score := -1.0
	var traumas: int = Array(s.characters["P01"]["traumas"]).size()
	for eid: String in s.active_event_ids():
		var ev: Dictionary = c.events[eid]
		for executor: String in _executors(c, s):
			var d := {"character": executor, "enhancements": enh}
			for info: Dictionary in TurnResolver.preview(c, s, eid, d):
				var o: Dictionary = info["option"]
				if info["done"] or not Array(info["blockers"]).is_empty():
					continue
				if TurnResolver.can_resolve(c, s, eid, o["id"], d) != "":
					continue
				var chance := float(info["chance"])
				var score := chance
				if bool(o.get("story", false)) or ev.get("type", "") == "reward":
					score += 40.0 if chance >= 60 else 0.0
				elif ev.get("type", "") == "side" or ev.get("type", "") == "random":
					score += 25.0 if traumas >= 2 and eid == "SE01" else 0.0
				if score > best_score:
					best_score = score
					best = {"event": eid, "option": o["id"], "draft": d, "extras": {"ward": traumas >= 2}}
	return best


static func _executors(c: Content, s: RunState) -> Array:
	var out: Array = []
	for card: String in s.collection:
		if c.card_kind(card) == "character" and s.is_alive(card):
			out.append(card)
	return out


## Бой ботом: каждый раунд выбирает приём с лучшим шансом.
static func play_combat(c: Content, s: RunState, eid: String, oid: String, draft: Dictionary) -> Dictionary:
	var why := TurnResolver.can_resolve(c, s, eid, oid, draft)
	if why != "":
		return {"ok": false, "reason": why}
	var cs := CombatSession.create(c, s, eid, oid, draft)
	while not cs.finished:
		cs.begin_round()
		var best := ""
		var best_ch := int(cs.ledger({})["chance"])
		for t: String in cs.hand:
			var ch := int(cs.ledger(c.tactics[t])["chance"])
			if ch > best_ch:
				best_ch = ch
				best = t
		cs.play_round(best)
	return cs.finish()
