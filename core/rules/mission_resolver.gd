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
		return {"ok": false, "error": "Отряд ещё в пути" if sq["phase"] == "travel" else "Отряд ждёт решения на развилке"}
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
		"entries": [], "traumas": {}, "deaths": [], "rest": {}, "combats": [], "opened": [], "forks": []}
	var run := {"action": action_id, "stages": Array(a.get("stages", [])).duplicate(true), "done": 0, "outcomes": [],
		"fails": 0, "temp_used": [], "extra_rest": 0.0, "extra_success": [], "guaranteed": bool(a.get("guaranteed", false))}
	if bool(a.get("retreat", false)):
		report["outcome"] = "retreat"
		report["entries"].append({"kind": "info", "text": "Отряд отступил. Миссия не выполнена."})
		return _finish(content, state, m, sq, run, report, rng)
	_pay_cost(content, state, a, heroes, run, report, rng)
	# угроза пугает с порога (docs/16 §7)
	var threat_gain := PanicRules.GAIN_THREAT * maxi(0, int(m.get("threat", 1)) - 2)
	for cid: String in heroes:
		var g := 0 if GrowthRules.has(content, state, cid, "panic_threat_immune") else threat_gain
		g += int(GrowthRules.total(content, state, cid, "panic_mission"))
		report["entries"].append_array(PanicRules.add(content, state, cid, g, "угроза"))
	return _advance(content, state, m, sq, run, report, rng)


## Действие целиком: на развилках — первый вариант (продолжить). Для бота, тестов и прогноза.
static func resolve_through(content: Content, state_in: RunState, squad_id: int, action_id: String) -> Dictionary:
	var r := resolve(content, state_in, squad_id, action_id)
	var guard := 0
	while r["ok"] and r.has("fork") and guard < 5:
		r = resume(content, r["state"], squad_id, str(r["fork"]["options"][0]["id"]))
		guard += 1
	return r


## Выбор на развилке (docs/16 §2): продолжить, сменить путь (свои этапы) или отступить с добытым.
static func resume(content: Content, state_in: RunState, squad_id: int, option_id: String) -> Dictionary:
	var state := state_in.copy()
	var sq := MissionFlow.squad(state, squad_id)
	if sq.is_empty() or sq["phase"] != "fork":
		return {"ok": false, "error": "Отряд не ждёт решения"}
	var m: Dictionary = content.missions.get(str(sq["mission"]), {})
	var run: Dictionary = sq["pending"]["run"]
	var report: Dictionary = sq["pending"]["report"]
	var fork: Dictionary = run["stages"][int(run["done"]) - 1].get("fork", {})
	var opt: Dictionary = {}
	for o: Dictionary in fork.get("options", []):
		if str(o.get("id", "")) == option_id:
			opt = o
	if opt.is_empty():
		return {"ok": false, "error": "Нет такого выбора"}
	sq.erase("pending")
	sq["phase"] = "arrived"
	report.erase("fork")
	var rng := RandomNumberGenerator.new()
	rng.seed = state.rng_seed
	rng.state = state.rng_state
	report["forks"].append({"text": str(fork.get("text", "")), "choice": str(opt.get("label", ""))})
	if str(opt.get("then", "continue")) == "retreat":
		var proud := PanicRules.refuses_retreat(content, state, Array(sq["heroes"]))
		if proud != "":
			return {"ok": false, "error": "%s в панике и не отступит" % proud}
		report["outcome"] = "retreat"
		var executor := _executor(state, Array(sq["heroes"]))
		if executor != "":
			report["entries"].append_array(EffectApplier.apply_all(content, state, opt.get("keep", []), executor, rng))
		report["entries"].append({"kind": "info", "text": "Отряд отступил с тем, что успел добыть. Миссия не выполнена."})
		return _finish(content, state, m, sq, run, report, rng)
	if opt.has("stages"):
		# сменить путь: оставшиеся этапы заменяются своими
		var done: Array = Array(run["stages"]).slice(0, int(run["done"]))
		run["stages"] = done + Array(opt["stages"]).duplicate(true)
	run["extra_success"] = Array(run["extra_success"]) + Array(opt.get("on_success", []))
	return _advance(content, state, m, sq, run, report, rng)


## Цена действия (docs/16 §3): осколки, жертва карты из кармашка отряда, лишний отдых, травма.
static func _pay_cost(content: Content, state: RunState, a: Dictionary, heroes: Array, run: Dictionary,
		report: Dictionary, rng: RandomNumberGenerator) -> void:
	var cost: Dictionary = a.get("cost", {})
	var entries: Array = report["entries"]
	if cost.has("shards"):
		state.resources["shards"] = int(state.resources.get("shards", 0)) - int(cost["shards"])
		entries.append({"kind": "resource", "text": "Потрачено: %d осколков душ" % int(cost["shards"])})
	var victim := MissionFlow.sacrifice_card(content, state, a, heroes)
	if victim != "":
		EffectApplier._remove_card(state, victim)
		state.wear.erase(victim)
		entries.append({"kind": "broken", "text": "Отдано ради успеха: %s" % content.card_name(victim), "card": victim})
	if cost.has("rest"):
		run["extra_rest"] = float(cost["rest"])
	if int(cost.get("trauma", 0)) > 0:
		var who := _executor(state, heroes)
		if who != "":
			var res := {"traumas": [], "death": {}}
			InjuryRules.give_traumas(content, state, who, MissionFlow.pocket(state, who), int(cost["trauma"]), "physical", rng, res, entries)
			if not res["traumas"].is_empty():
				report["traumas"][who] = Array(report["traumas"].get(who, [])) + Array(res["traumas"])


## Этапы по порядку до конца или до развилки: на развилке отряд ждёт решения игрока.
static func _advance(content: Content, state: RunState, m: Dictionary, sq: Dictionary, run: Dictionary,
		report: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var a := MissionFlow.action(content, str(m.get("id", "")), str(run["action"]))
	var heroes: Array = Array(sq["heroes"])
	var temp_used := {}
	for i: int in run["temp_used"]:
		temp_used[i] = true
	var stages: Array = run["stages"]
	var fled: Array = run.get("fled", [])
	while int(run["done"]) < stages.size():
		var st: Dictionary = stages[int(run["done"])]
		# Трус в панике сбегает перед этапом (docs/16 §7)
		for cid: String in heroes:
			if state.is_alive(cid) and not fled.has(cid) and PanicRules.flees(content, state, cid):
				fled.append(cid)
				report["entries"].append({"kind": "panic", "card": cid, "text": "%s сбегает, не выдержав страха" % content.card_name(cid)})
				for other: String in heroes:
					if other != cid and state.is_alive(other):
						report["entries"].append_array(TrustRules.change(content, state, cid, other, -1, "сбежал с миссии"))
		run["fled"] = fled
		var alive: Array = heroes.filter(func(c: String) -> bool: return state.is_alive(c) and not fled.has(c))
		var trauma_before := {}
		for cid: String in alive:
			trauma_before[cid] = Array(report["traumas"].get(cid, [])).size()
		var rec := {"name": st.get("name", ""), "hero": "", "chance": 0, "roll": 0, "outcome": "fail", "text": ""}
		if alive.is_empty():
			rec["text"] = "Идти дальше некому."
		elif bool(st.get("auto", false)) or bool(run["guaranteed"]):
			rec["outcome"] = "ok"
		elif st.has("combat"):
			var after := _combat_stage(content, state, m, a, MissionFlow.boss_stage(state, m, st), alive, rec, report, rng)
			_copy_into(state, after)
			sq = MissionFlow.squad(state, int(sq["id"]))
			GrowthRules.mark_combat(content, state, run, alive, Array(report["combats"]).back()["rounds"], rec["outcome"] == "ok")
		else:
			_check_stage(content, state, m, a, st, alive, rec, report, rng, temp_used)
		if rec["text"] == "":
			rec["text"] = str(st.get({"ok": "ok", "partial": "partial", "fail": "fail"}[rec["outcome"]], ""))
			if rec["text"] == "" and rec["outcome"] == "partial":
				rec["text"] = str(st.get("ok", ""))
		if rec["outcome"] == "fail":
			run["fails"] = int(run["fails"]) + 1
			# Вечный беглец уходит после проваленного этапа
			for cid: String in alive:
				if state.is_alive(cid) and not fled.has(cid) and GrowthRules.has(content, state, cid, "flees_on_fail"):
					fled.append(cid)
					report["entries"].append({"kind": "panic", "card": cid, "text": "%s сбегает после неудачи" % content.card_name(cid)})
		# опыт тегов (docs/16 §8)
		if rec["hero"] != "" and not st.has("combat"):
			GrowthRules.mark_check(content, state, run, str(rec["hero"]), Array(m.get("context", [])) + Array(st.get("tags", [])), str(rec["outcome"]))
		for cid: String in alive:
			if state.is_alive(cid):
				GrowthRules.mark_panic(content, state, run, cid)
		# паника от этапа: провал и частичный успех пугают всех, травма — раненого, гибель — остальных
		var gain: int = {"fail": PanicRules.GAIN_FAIL, "partial": PanicRules.GAIN_PARTIAL}.get(rec["outcome"], 0)
		for cid: String in alive:
			if not state.is_alive(cid):
				for other: String in alive:
					if other != cid:
						report["entries"].append_array(PanicRules.add(content, state, other, PanicRules.GAIN_DEATH, "гибель товарища"))
				continue
			var got := Array(report["traumas"].get(cid, [])).size() - int(trauma_before.get(cid, 0))
			report["entries"].append_array(PanicRules.add(content, state, cid, int(gain) + PanicRules.GAIN_TRAUMA * got, "этап «%s»" % rec["name"]))
		run["outcomes"].append(rec["outcome"])
		report["stages"].append(rec)
		run["done"] = int(run["done"]) + 1
		# развилка после этапа: если ещё есть кому решать и что решать
		if st.has("fork") and not alive.is_empty() and not state.game_over and not bool(st.get("_fork_passed", false)):
			st["_fork_passed"] = true
			run["temp_used"] = temp_used.keys()
			sq["phase"] = "fork"
			sq["pending"] = {"run": run, "report": report}
			report["fork"] = st["fork"]
			state.rng_state = rng.state
			return {"ok": true, "error": "", "state": state, "report": report, "fork": st["fork"]}
	run["temp_used"] = temp_used.keys()
	report["outcome"] = MissionForecast.combine(run["outcomes"])
	_consume_temps(state, temp_used)
	var executor := _executor(state, heroes)
	var key: String = {"success": "on_success", "partial": "on_partial", "failure": "on_failure"}[report["outcome"]]
	var entries: Array = report["entries"]
	if executor != "" and not state.game_over:
		entries.append_array(EffectApplier.apply_all(content, state, a.get(key, []), executor, rng))
		if report["outcome"] in ["success", "partial"]:
			entries.append_array(EffectApplier.apply_all(content, state, run["extra_success"], executor, rng))
	# износ усилений из кармашков участников
	var pockets: Array = []
	for cid: String in heroes:
		pockets.append_array(MissionFlow.pocket(state, cid))
	InjuryRules.apply_wear(content, state, pockets, rng, entries, {"wear": []})
	# Ломатель и Живая сталь: предметы изнашиваются быстрее
	for cid: String in heroes:
		var wm := GrowthRules.mult(content, state, cid, "wear_mult")
		if wm > 1.0:
			for card: String in MissionFlow.pocket(state, cid):
				if state.wear.has(card):
					state.wear[card] = mini(100, int(state.wear[card]) + int(WearRules.STEP * (wm - 1.0)))
	return _finish(content, state, m, sq, run, report, rng)


## Итог миссии: статус, следующее по сюжету, взаимоисключения, фазы босса, отдых, отряд распущен.
static func _finish(content: Content, state: RunState, m: Dictionary, sq: Dictionary, run: Dictionary,
		report: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var mid := str(m.get("id", ""))
	var heroes: Array = Array(sq["heroes"])
	var squad_id := int(sq["id"])
	var entries: Array = report["entries"]
	var a := MissionFlow.action(content, mid, str(run["action"]))
	var status: Dictionary = state.missions.get(mid, {"attempts": 0})
	var boss: Array = m.get("boss", {}).get("phases", [])
	var phase := int(status.get("phase", 0))
	var won_combat := Array(report["combats"]).any(func(c: Dictionary) -> bool: return c["outcome"] == "win")
	var executor := _executor(state, heroes)
	if report["outcome"] in ["success", "partial"] and not boss.is_empty() and won_combat and phase < boss.size() - 1:
		# босс в несколько заходов: победа снимает фазу, миссия остаётся
		status["phase"] = phase + 1
		status["status"] = "open"
		report["boss_phase"] = phase + 1
		entries.append({"kind": "story", "text": "%s ранен и отступил — заход %d из %d. %s" % [
			m.get("title", mid), phase + 2, boss.size(), str(boss[phase + 1].get("text", ""))]})
	elif report["outcome"] in ["success", "partial"]:
		if executor != "" and not state.game_over:
			entries.append_array(EffectApplier.apply_all(content, state, m.get("on_complete", []), executor, rng))
		status["status"] = "done"
		var story := bool(a.get("story", false)) or str(m.get("type", "")) == "story"
		entries.append({"kind": "story" if story else "info",
			"text": ("Миссия выполнена: %s" if report["outcome"] == "success" else "Миссия выполнена с потерями: %s") % m.get("title", mid)})
		# сюжетная миссия продвигает сюжет любым удачным действием: действия — разные пути к одной цели
		if story:
			for nid: String in m.get("next", []):
				var opened := MissionFlow.open(content, state, nid)
				entries.append_array(opened)
				if not opened.is_empty():
					report["opened"].append(nid)
		# миссия-выбор: выполненная закрывает свою пару
		for other: String in m.get("exclusive", []):
			if str(state.missions.get(other, {}).get("status", "")) == "open":
				state.missions[other]["status"] = "closed"
				entries.append({"kind": "lost", "text": "Упущено: %s" % content.missions.get(other, {}).get("title", other)})
		var more := MissionFlow.after_completion(content, state)
		entries.append_array(more)
		for e: Dictionary in more:
			report["opened"].append(e.get("card", ""))
		if bool(m.get("end_chapter", false)) and not state.game_over:
			state.demo_complete = true
			report["chapter_done"] = MissionFlow.chapter_of(content, mid)
			if str(m.get("next_chapter", "")) != "":
				state.flags["next_chapter"] = str(m["next_chapter"])
			entries.append({"kind": "story", "text": "Глава пройдена"})
	else:
		status["status"] = "open"
		if report["outcome"] == "failure":
			status["attempts"] = int(status.get("attempts", 0)) + 1
			entries.append({"kind": "info", "text": "Миссия провалена — её можно повторить."})
	state.missions[mid] = status

	# доверие и ссоры в связках (docs/16 §5–6)
	if report["outcome"] != "retreat":
		entries.append_array(TrustRules.after_mission(content, state, heroes.filter(func(c: String) -> bool: return not Array(run.get("fled", [])).has(c)),
			str(report["outcome"]), str(m.get("title", mid)), rng))
		entries.append_array(BondRules.quarrels(content, state, heroes, rng))
	# рост тегов и эффекты развитий (docs/16 §8)
	entries.append_array(GrowthRules.apply(content, state, run, heroes, str(report["outcome"]), rng))
	entries.append_array(GrowthRules.after_mission(content, state, heroes, str(report["outcome"]), rng))
	# натиск отбит: доверие; бестиарий и слухи (docs/16 §9)
	entries.append_array(OnslaughtRules.reward(content, state, m, heroes, str(report["outcome"])))
	entries.append_array(JournalRules.after_mission(content, state, m, report, heroes))

	# отдых выживших
	var base_rest := float(m.get("rest", MissionFlow.DEFAULT_REST)) + float(run.get("extra_rest", 0.0))
	for cid: String in heroes:
		if not state.is_alive(cid):
			if not report["deaths"].has(cid):
				report["deaths"].append(cid)
			continue
		var rest := maxf(5.0, base_rest + GrowthRules.total(content, state, cid, "rest_add"))
		if report["outcome"] != "retreat":
			rest += REST_PER_FAIL * int(run["fails"]) + REST_PER_TRAUMA * Array(report["traumas"].get(cid, [])).size()
		state.rest_until[cid] = state.clock + rest
		report["rest"][cid] = rest

	state.squads = state.squads.filter(func(s: Dictionary) -> bool: return int(s["id"]) != squad_id)
	state.log.append({"clock": state.clock, "mission": mid, "action": str(run["action"]), "outcome": report["outcome"], "heroes": heroes})
	state.rng_state = rng.state
	return {"ok": true, "error": "", "state": state, "report": report}


## Бой возвращает новое состояние — переносим его в текущее (ссылки на state у вызывающих не меняются).
static func _copy_into(dst: RunState, src: RunState) -> void:
	var d := src.to_dict()
	var fresh := RunState.from_dict(d)
	for p: Dictionary in dst.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			dst.set(p["name"], fresh.get(p["name"]))


static func _check_stage(content: Content, state: RunState, m: Dictionary, a: Dictionary, st: Dictionary,
		alive: Array, rec: Dictionary, report: Dictionary, rng: RandomNumberGenerator, temp_used: Dictionary) -> void:
	var actor := MissionForecast.stage_actor(content, state, m, a, st, alive)
	var cid: String = actor["hero"]
	var chance := int(actor["chance"])
	var roll := rng.randi_range(1, 100)
	rec["hero"] = cid
	rec["chance"] = chance
	rec["roll"] = roll
	rec["why"] = MissionDebrief.check_why(content, state, m, a, st, alive, cid)
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
	InjuryRules.give_traumas(content, state, cid, MissionFlow.pocket(state, cid), 1, str(m.get("trauma_pool", "all")),
		rng, res, report["entries"])
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
	# всё, что нужно, чтобы экран боя воспроизвёл этот автобой точь-в-точь
	var replay_setup := {"state": state.to_dict(), "key": str(m.get("id", "")), "spec": st.get("combat", {}), "hero": hero,
		"enh": MissionFlow.pocket(state, hero), "support": support,
		"ctx_event": MissionForecast.ctx_event(m), "ctx_option": MissionForecast.ctx_option(a, st)}
	var s := replay_session(content, replay_setup)
	s.auto_play()
	var after := s.state
	rng.state = s.rng.state
	var key := str(m.get("id", ""))
	var won := s.outcome == "win"
	rec["hero"] = hero
	rec["chance"] = setup["round"]
	rec["outcome"] = "ok" if won else "fail"
	rec["combat"] = {"outcome": s.outcome, "hero_wins": s.hero_wins, "enemy_wins": s.enemy_wins, "allies": s.allies}
	rec["why"] = MissionDebrief.combat_why(s.rounds_log, s.hero_wins, s.enemy_wins)
	report["combats"].append({"stage": rec["name"], "hero": hero, "allies": s.allies, "rounds": s.rounds_log,
		"outcome": s.outcome, "discovered": s.discovered, "setup": replay_setup})
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
		if shards > 0 and Atmosphere.sky(content, after) == "blood_moon":
			shards = int(ceil(shards * Atmosphere.BLOOD_LOOT))
		if shards > 0:
			report["entries"].append_array(EffectApplier.apply(content, after, {"cmd": "adjust_resource", "resource": "shards", "value": shards}, hero, rng))
		after.enemy_wounds.erase(key)
	elif s.session_wounds > 0:
		# враги помнят: раны сохраняются до следующей попытки
		after.enemy_wounds[key] = int(after.enemy_wounds.get(key, 0)) + s.session_wounds
	for e: Dictionary in s.enemies:
		after.note(str(e.get("id", "")), "Бой «%s» · %s" % [m.get("title", key), "победа" if won else "поражение"])
	return after


## Бой в том же виде, в каком его сыграл резолвер (для просмотра автобоя).
static func replay_session(content: Content, setup: Dictionary) -> CombatSession:
	return CombatSession.create_for_mission(content, RunState.from_dict(setup["state"]), str(setup["key"]), setup["spec"],
		str(setup["hero"]), setup["enh"], setup["support"], setup["ctx_event"], setup["ctx_option"])


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
