class_name MissionResolver
extends RefCounted
## Итог действия прибывшего отряда (docs/15 §7): этапы со скрытыми бросками, автобой, травмы,
## последствия, износ, отдых, открытие следующих миссий. Транзакция: работает на копии состояния
## и возвращает {ok, error, state, report}.

const REST_PER_FAIL := 10.0      # +с отдыха за проваленный этап
const REST_PER_TRAUMA := 15.0    # +с отдыха за каждую полученную травму


static func resolve(content: Content, state_in: RunState, squad_id: int, action_id: String) -> Dictionary:
	var state := state_in.copy()
	var sq := MissionFlow.squad(state, squad_id)
	if sq.is_empty():
		return {"ok": false, "error": "Нет такого отряда"}
	if sq["phase"] != "arrived":
		return {"ok": false, "error": "Отряд ещё в пути"}
	var mid: String = sq["mission"]
	var m: Dictionary = content.missions.get(mid, {})
	var a := MissionFlow.action(content, mid, action_id)
	if a.is_empty():
		return {"ok": false, "error": "Нет такого действия"}
	var heroes: Array = Array(sq["heroes"]).duplicate()
	for entry: Dictionary in MissionFlow.actions_for(content, state, mid, heroes):
		if entry["action"] == a and not entry["available"]:
			return {"ok": false, "error": entry["reason"]}

	var rng := RandomNumberGenerator.new()
	rng.seed = state.rng_seed
	rng.state = state.rng_state
	var report := {"mission": mid, "action": action_id, "heroes": heroes, "stages": [], "outcome": "",
		"entries": [], "traumas": {}, "deaths": [], "rest": {}, "combats": [], "opened": []}
	var entries: Array = report["entries"]
	var fails := 0
	var temp_used := {}

	if bool(a.get("retreat", false)):
		report["outcome"] = "retreat"
		entries.append({"kind": "info", "text": "Отряд отступил. Миссия не выполнена."})
	else:
		var outcomes: Array = []
		for st: Dictionary in a.get("stages", []):
			var alive: Array = heroes.filter(func(c: String) -> bool: return state.is_alive(c))
			var rec := {"name": st.get("name", ""), "hero": "", "chance": 0, "roll": 0, "outcome": "fail", "text": ""}
			if alive.is_empty():
				rec["text"] = "Идти дальше некому."
			elif bool(st.get("auto", false)):
				rec["outcome"] = "ok"
			elif st.has("combat"):
				state = _combat_stage(content, state, m, a, st, alive, rec, report, rng)
			else:
				_check_stage(content, state, m, a, st, alive, rec, report, rng, temp_used)
			if rec["text"] == "":
				rec["text"] = str(st.get({"ok": "ok", "partial": "partial", "fail": "fail"}[rec["outcome"]], ""))
				if rec["text"] == "" and rec["outcome"] == "partial":
					rec["text"] = str(st.get("ok", ""))
			if rec["outcome"] == "fail":
				fails += 1
			outcomes.append(rec["outcome"])
			report["stages"].append(rec)
		report["outcome"] = MissionForecast.combine(outcomes)
		_consume_temps(state, temp_used)
		var executor := _executor(state, heroes)
		var key: String = {"success": "on_success", "partial": "on_partial", "failure": "on_failure"}[report["outcome"]]
		if executor != "" and not state.game_over:
			entries.append_array(EffectApplier.apply_all(content, state, a.get(key, []), executor, rng))
		# износ усилений из кармашков участников
		var pockets: Array = []
		for cid: String in heroes:
			pockets.append_array(MissionFlow.pocket(state, cid))
		TurnResolver.apply_wear(content, state, pockets, rng, entries, {"wear": []})

	# статус миссии и что открывается дальше
	var status: Dictionary = state.missions.get(mid, {"attempts": 0})
	if report["outcome"] in ["success", "partial"]:
		status["status"] = "done"
		entries.append({"kind": "story" if bool(a.get("story", false)) else "info",
			"text": ("Миссия выполнена: %s" if report["outcome"] == "success" else "Миссия выполнена с потерями: %s") % m.get("title", mid)})
		if bool(a.get("story", false)):
			for nid: String in m.get("next", []):
				var opened := MissionFlow.open(content, state, nid)
				entries.append_array(opened)
				if not opened.is_empty():
					report["opened"].append(nid)
		var more := MissionFlow.after_completion(content, state)
		entries.append_array(more)
		for e: Dictionary in more:
			report["opened"].append(e.get("card", ""))
	else:
		status["status"] = "open"
		if report["outcome"] == "failure":
			status["attempts"] = int(status.get("attempts", 0)) + 1
			entries.append({"kind": "info", "text": "Миссия провалена — её можно повторить."})
	state.missions[mid] = status

	# отдых выживших
	var base_rest := float(m.get("rest", MissionFlow.DEFAULT_REST))
	for cid: String in heroes:
		if not state.is_alive(cid):
			if not report["deaths"].has(cid):
				report["deaths"].append(cid)
			continue
		var rest := base_rest
		if report["outcome"] != "retreat":
			rest += REST_PER_FAIL * fails + REST_PER_TRAUMA * Array(report["traumas"].get(cid, [])).size()
		state.rest_until[cid] = state.clock + rest
		report["rest"][cid] = rest

	state.squads = state.squads.filter(func(s: Dictionary) -> bool: return int(s["id"]) != squad_id)
	state.log.append({"clock": state.clock, "mission": mid, "action": action_id, "outcome": report["outcome"], "heroes": heroes})
	state.rng_state = rng.state
	return {"ok": true, "error": "", "state": state, "report": report}


static func _check_stage(content: Content, state: RunState, m: Dictionary, a: Dictionary, st: Dictionary,
		alive: Array, rec: Dictionary, report: Dictionary, rng: RandomNumberGenerator, temp_used: Dictionary) -> void:
	var actor := MissionForecast.stage_actor(content, state, m, a, st, alive)
	var cid: String = actor["hero"]
	var chance := int(actor["chance"])
	var roll := rng.randi_range(1, 100)
	rec["hero"] = cid
	rec["chance"] = chance
	rec["roll"] = roll
	for i: int in actor["temp_used"]:
		temp_used[i] = true
	if roll <= chance:
		rec["outcome"] = "ok"
		return
	rec["outcome"] = "partial" if roll <= chance + MissionForecast.PARTIAL_BAND else "fail"
	var hurt: bool = rec["outcome"] == "fail" or rng.randi_range(1, 100) <= MissionForecast.PARTIAL_TRAUMA
	if hurt:
		_hurt(content, state, m, cid, report, rng)


static func _hurt(content: Content, state: RunState, m: Dictionary, cid: String, report: Dictionary, rng: RandomNumberGenerator) -> void:
	var res := {"traumas": [], "death": {}}
	TurnResolver.give_traumas(content, state, cid, MissionFlow.pocket(state, cid), 1, str(m.get("trauma_pool", "all")),
		false, rng, res, report["entries"])
	if not res["traumas"].is_empty():
		var got: Array = report["traumas"].get(cid, [])
		got.append_array(res["traumas"])
		report["traumas"][cid] = got


## Бой этапа: автобой; состояние после боя (травмы, раны врага) становится текущим.
static func _combat_stage(content: Content, state: RunState, m: Dictionary, a: Dictionary, st: Dictionary,
		alive: Array, rec: Dictionary, report: Dictionary, rng: RandomNumberGenerator) -> RunState:
	var setup := MissionForecast.combat_setup(content, state, m, a, st, alive, true)
	var hero: String = setup["hero"]
	var support: Array = alive.filter(func(c: String) -> bool: return c != hero)
	state.rng_state = rng.state
	var s := CombatSession.create_for_mission(content, state, str(m.get("id", "")), st.get("combat", {}), hero,
		MissionFlow.pocket(state, hero), support, MissionForecast.ctx_event(m), MissionForecast.ctx_option(a, st))
	s.auto_play()
	var after := s.state
	rng.state = s.rng.state
	var key := str(m.get("id", ""))
	var won := s.outcome == "win"
	rec["hero"] = hero
	rec["chance"] = setup["round"]
	rec["outcome"] = "ok" if won else "fail"
	rec["combat"] = {"outcome": s.outcome, "hero_wins": s.hero_wins, "enemy_wins": s.enemy_wins, "allies": s.allies}
	report["combats"].append({"stage": rec["name"], "hero": hero, "allies": s.allies, "rounds": s.rounds_log,
		"outcome": s.outcome, "discovered": s.discovered})
	report["entries"].append_array(s.entries)
	if not Array(s.result["traumas"]).is_empty():
		var got: Array = report["traumas"].get(hero, [])
		got.append_array(s.result["traumas"])
		report["traumas"][hero] = got
	if won:
		var shards := 0
		for e: Dictionary in s.enemies:
			shards += int(e.get("shards", 0))
			var echo: Dictionary = e.get("echo", {})
			if not echo.is_empty() and rng.randf() < float(echo.get("chance", 0.0)):
				report["entries"].append_array(EffectApplier.add_card(content, after, str(echo["card"])))
		if shards > 0:
			report["entries"].append_array(EffectApplier.apply(content, after, {"cmd": "adjust_resource", "resource": "shards", "value": shards}, hero, rng))
		after.enemy_wounds.erase(key)
		after.enemy_alert.erase(key)
	elif s.session_wounds > 0:
		# враги помнят: раны сохраняются до следующей попытки
		after.enemy_wounds[key] = int(after.enemy_wounds.get(key, 0)) + s.session_wounds
	for e: Dictionary in s.enemies:
		after.note(str(e.get("id", "")), "Бой «%s» · %s" % [m.get("title", key), "победа" if won else "поражение"])
	return after


static func _executor(state: RunState, heroes: Array) -> String:
	for cid: String in heroes:
		if state.is_alive(cid):
			return cid
	return ""


## Временные бонусы, сработавшие на этапах, тратятся (как после события).
static func _consume_temps(state: RunState, used: Dictionary) -> void:
	var idx: Array = used.keys()
	idx.sort()
	idx.reverse()
	for i: int in idx:
		if i >= state.temp_effects.size():
			continue
		var te: Dictionary = state.temp_effects[i]
		te["remaining"] = int(te.get("remaining", 1)) - 1
		if int(te["remaining"]) <= 0:
			state.temp_effects.remove_at(i)
