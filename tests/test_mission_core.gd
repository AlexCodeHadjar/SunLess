extends TestCase
## Ядро миссий (docs/15, Ф2): отряды, часы, действия, этапы, прогноз, отдых, смерть навсегда.


## Прохождение, где уже открыт «Караван рабов» (MS02) — на нём проверяются правила.
func _run(seed_value: int = 7) -> RunState:
	var s := MissionFlow.new_run(content(), seed_value)
	MissionFlow.open(content(), s, "MS02")
	return s


## Отправить отряд и промотать часы до прибытия. Возвращает id отряда.
func _arrive(c: Content, s: RunState, mid: String, heroes: Array) -> int:
	var r := MissionFlow.launch(c, s, mid, heroes)
	check(r["ok"], "отряд должен уйти: %s" % r.get("error", ""))
	MissionFlow.tick(c, s, float(c.missions[mid]["duration"]))
	return int(r["squad"]["id"])


func test_new_run() -> void:
	var s := MissionFlow.new_run(content(), 7)
	eq(s.mode, "missions", "режим:")
	check(s.is_alive("P01"), "Санни жив")
	eq(MissionFlow.open_missions(s), ["MS01"], "с начала открыта только стартовая миссия:")
	check(not s.resources.has("mana"), "маны в режиме миссий нет")


func test_launch_rules() -> void:
	var c := content()
	var s := _run()
	check(MissionFlow.can_launch(c, s, "MS03", ["P01"]) != "", "закрытую миссию не запустить")
	check(MissionFlow.can_launch(c, s, "MS02", []) != "", "пустой отряд не уходит")
	check(MissionFlow.can_launch(c, s, "MS02", ["P01", "P01"]) != "", "в MS02 одно место")
	var r := MissionFlow.launch(c, s, "MS02", ["P01"])
	check(r["ok"], "отряд ушёл")
	eq(MissionFlow.busy_reason(c, s, "P01"), "на миссии", "Санни занят:")
	eq(s.missions["MS02"]["status"], "active", "миссия в работе:")
	check(MissionFlow.can_launch(c, s, "MS02", ["P01"]) != "", "вторично ту же миссию не запустить")


func test_clock_and_arrival() -> void:
	var c := content()
	var s := _run()
	var r := MissionFlow.launch(c, s, "MS02", ["P01"])
	var ev := MissionFlow.tick(c, s, 2.0)
	eq(MissionFlow.squad(s, int(r["squad"]["id"]))["phase"], "travel", "через 2 с ещё в пути:")
	check(ev.is_empty(), "событий пока нет")
	ev = MissionFlow.tick(c, s, 10.0)
	eq(MissionFlow.squad(s, int(r["squad"]["id"]))["phase"], "arrived", "прибыл:")
	check(ev.size() == 1 and ev[0]["kind"] == "arrived", "событие «прибыл»")


func test_actions_depend_on_squad() -> void:
	var c := content()
	var s := _run()
	var acts := MissionFlow.actions_for(c, s, "MS02", ["P01"])
	var over: Dictionary = acts.filter(func(e: Dictionary) -> bool: return e["action"]["id"] == "MS02_overhear")[0]
	check(over["available"], "у Санни есть Скрытность/Чутьё — подслушать можно")
	acts = MissionFlow.actions_for(c, s, "MS03", ["P01"])
	var debris: Dictionary = acts.filter(func(e: Dictionary) -> bool: return e["action"]["id"] == "MS03_debris")[0]
	check(debris["available"], "у Санни-раба есть Импровизация — обломки доступны")
	c.characters["P01"]["stages"]["slave"]["tags"].erase("Импровизация")
	acts = MissionFlow.actions_for(c, s, "MS03", ["P01"])
	debris = acts.filter(func(e: Dictionary) -> bool: return e["action"]["id"] == "MS03_debris")[0]
	check(not debris["available"], "без Импровизации обломки закрыты")


func test_resolve_updates_state() -> void:
	var c := content()
	# в данных MS02 для Санни почти беспроигрышна — ужесточаем, чтобы встретить и провал
	c.missions["MS02"]["actions"][0]["stages"][0]["req"] = {"cunning": 14}
	var saw_success := false
	var saw_failure := false
	for seed_value in range(1, 40):
		var s := _run(seed_value)
		var sid := _arrive(c, s, "MS02", ["P01"])
		var clock := s.clock
		var r := MissionResolver.resolve(c, s, sid, "MS02_watch")
		check(r["ok"], "действие выполнено")
		var ns: RunState = r["state"]
		var rep: Dictionary = r["report"]
		check(ns.squads.is_empty(), "отряд вернулся")
		eq(rep["stages"].size(), 2, "два этапа:")
		if ns.is_alive("P01"):
			eq(MissionFlow.busy_reason(c, ns, "P01"), "", "отдыха нет — Санни свободен сразу:")
		if rep["outcome"] in ["success", "partial"]:
			saw_success = true
			eq(ns.missions["MS02"]["status"], "done", "миссия выполнена:")
			eq(ns.missions.get("MS03", {}).get("status", ""), "open", "сюжет открыл MS03:")
			eq(ns.completed_missions, 1, "счётчик миссий:")
		else:
			saw_failure = true
			eq(ns.missions["MS02"]["status"], "open", "проваленную можно повторить:")
			eq(int(ns.missions["MS02"]["attempts"]), 1, "попытка засчитана:")
		check(s.squads.size() == 1, "исходное состояние не тронуто (транзакция)")
	check(saw_success, "за 40 прохождений хотя бы один успех")
	check(saw_failure, "за 40 прохождений хотя бы один провал")


func test_retreat() -> void:
	var c := content()
	var s := _run()
	var sid := _arrive(c, s, "MS02", ["P01"])
	var r := MissionResolver.resolve(c, s, sid, "MS02_lay_low")
	var ns: RunState = r["state"]
	eq(r["report"]["outcome"], "retreat", "итог:")
	eq(ns.missions["MS02"]["status"], "open", "после отступления миссия снова открыта:")
	eq(int(ns.missions["MS02"]["attempts"]), 0, "отступление — не попытка:")
	eq(MissionFlow.busy_reason(c, ns, "P01"), "", "после отступления герой свободен:")
	check(r["report"]["traumas"].is_empty(), "без ран")


func test_locked_action_refused() -> void:
	var c := content()
	c.characters["P01"]["stages"]["slave"]["tags"].erase("Импровизация")
	var s := _run()
	s.missions["MS03"] = {"status": "open", "attempts": 0}
	var sid := _arrive(c, s, "MS03", ["P01"])
	var r := MissionResolver.resolve(c, s, sid, "MS03_debris")
	check(not r["ok"], "закрытое действие не выполнить")


func test_combat_stage_runs() -> void:
	var c := content()
	var s := _run(3)
	s.missions["MS03"] = {"status": "open", "attempts": 0}
	var sid := _arrive(c, s, "MS03", ["P01"])
	var r := MissionResolver.resolve_through(c, s, sid, "MS03_fight")
	check(r["ok"], "бой прошёл")
	var rep: Dictionary = r["report"]
	eq(rep["combats"].size(), 1, "один автобой:")
	check(Array(rep["combats"][0]["rounds"]).size() >= 2, "в автобое сыграно не меньше двух раундов")
	check(rep["stages"][1].has("combat"), "второй этап — бой")


func test_rest_and_tick() -> void:
	var c := content()
	var s := _run()
	var sid := _arrive(c, s, "MS02", ["P01"])
	s = MissionResolver.resolve(c, s, sid, "MS02_lay_low")["state"]
	# отдыха между событиями нет (решение владельца): герой свободен сразу, часы его не держат
	eq(MissionFlow.busy_reason(c, s, "P01"), "", "Санни свободен сразу после миссии:")
	var ev := MissionFlow.tick(c, s, 25.0)
	check(not ev.any(func(e: Dictionary) -> bool: return e["kind"] == "rested"), "событий отдыха больше нет")


func test_save_roundtrip() -> void:
	var c := content()
	var s := _run()
	MissionFlow.launch(c, s, "MS02", ["P01"])
	MissionFlow.tick(c, s, 3.5)
	var s2 := RunState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	eq(s2.mode, "missions", "режим:")
	eq(s2.clock, 3.5, "часы:")
	eq(s2.squads.size(), 1, "отряд в пути сохранился:")
	eq(MissionFlow.busy_reason(c, s2, "P01"), "на миссии", "Санни всё ещё на миссии:")


func test_death_is_permanent_and_key_hero() -> void:
	var c := content()
	var s := _run()
	EffectApplier.add_card(c, s, "P09")
	EffectApplier.add_card(c, s, "P10")
	var entries: Array = []
	InjuryRules.kill(c, s, "P10", entries)
	check(not s.game_over, "Шифти погиб, но Санни и Шолар живы — игра идёт")
	check(not MissionFlow.heroes(c, s).has("P10"), "погибший уходит из состава")
	check(not ShopRules.can_offer(c, s, "P10"), "погибшего не вернуть и в магазине")
	# Санни обязателен для финала главы (MS10, MS11: requires_heroes) — без него сюжет обрывается
	eq(MissionFlow.key_mission_for(c, s, "P01"), "Храм Бога Теней", "Санни нужен сюжету:")
	eq(MissionFlow.key_mission_for(c, s, "P09"), "", "Шолар сюжету не обязателен:")
	InjuryRules.kill(c, s, "P01", entries)
	check(s.game_over, "Санни погиб до Храма — конец, хотя Шолар жив")


func test_game_over_when_nobody_left() -> void:
	var c := content()
	var s := _run()
	EffectApplier.add_card(c, s, "P09")
	for mid: String in ["MS10", "MS11"]:
		s.missions[mid] = {"status": "done", "attempts": 0}
	var entries: Array = []
	InjuryRules.kill(c, s, "P01", entries)
	check(not s.game_over, "сюжетные миссии Санни пройдены — его гибель не конец")
	InjuryRules.kill(c, s, "P09", entries)
	check(s.game_over, "героев не осталось — конец")


func test_forecast_words_and_combine() -> void:
	eq(MissionForecast.word(10), "Безнадёжно", "")
	eq(MissionForecast.word(60), "Неясно", "")
	eq(MissionForecast.word(90), "Уверенно", "")
	eq(MissionForecast.combine(["ok", "ok"]), "success", "ok+ok:")
	eq(MissionForecast.combine(["ok", "partial"]), "success", "ok+partial:")
	eq(MissionForecast.combine(["ok", "fail"]), "failure", "ok+fail — провал короткой миссии:")
	eq(MissionForecast.combine(["ok", "ok", "fail"]), "partial", "ok+ok+fail — с потерями:")
	eq(MissionForecast.combine(["partial", "partial"]), "partial", "partial+partial:")
	eq(MissionForecast.combine(["partial", "fail", "fail"]), "failure", "partial+fail+fail:")
	eq(MissionForecast.combine(["partial"]), "partial", "один частичный:")


func test_forecast_blur_and_scout() -> void:
	var c := content()
	var s := _run()
	s.missions["MS03"] = {"status": "open", "attempts": 0}
	var f := MissionForecast.mission_forecast(c, s, "MS03", ["P01"])
	check(str(f["word"]) != "", "прогноз есть")
	check(str(f["risk_word"]) != "", "риск есть")
	EffectApplier.add_card(c, s, "P09")   # Шолар: Выслеживание — разведчик
	var f2 := MissionForecast.mission_forecast(c, s, "MS03", ["P01", "P09"])
	check(not f2["blurred"], "с разведчиком прогноз чёткий")


## Честность прогноза: доля успехов (успех + ½ частичного) близка к обещанному значению.
func test_forecast_is_honest() -> void:
	var c := content()
	for pair: Array in [["MS02", "MS02_watch"], ["MS02", "MS02_scholar"], ["MS03", "MS03_fight"], ["MS03", "MS03_debris"]]:
		var mid: String = pair[0]
		var aid: String = pair[1]
		var s0 := _run(1)
		s0.missions[mid] = {"status": "open", "attempts": 0}
		var fc := MissionForecast.action_forecast(c, s0, mid, MissionFlow.action(c, mid, aid), ["P01"], true)
		var score := 0.0
		var n := 300
		for i in n:
			var s := _run(1000 + i)
			s.missions[mid] = {"status": "open", "attempts": 0}
			var sid := _arrive(c, s, mid, ["P01"])
			var rep: Dictionary = MissionResolver.resolve_through(c, s, sid, aid)["report"]
			score += {"success": 1.0, "partial": 0.5}.get(rep["outcome"], 0.0)
		var real := int(round(100.0 * score / n))
		print("   [прогноз] %s/%s: обещано %d (%s), на деле %d" % [mid, aid, int(fc["value"]), fc["word"], real])
		check(absi(real - int(fc["value"])) <= 15, "%s/%s: прогноз %d, на деле %d" % [mid, aid, int(fc["value"]), real])


## Бот играет Первый Кошмар целиком: покупает попутчика, когда хватает осколков, отправляет свободных
## героев (сюжетные миссии — первыми), выбирает действие с лучшим прогнозом или отступает от безнадёжного.
func _bot(c: Content, seed_value: int, stats: Dictionary) -> Dictionary:
	var s := MissionFlow.new_run(c, seed_value)
	var steps := 0
	var attempts := 0
	var nightmare_done := false
	var academy_done := false
	while steps < 12000 and not s.game_over:
		steps += 1
		if s.demo_complete:
			if str(s.flags.get("next_chapter", "")) == "":
				break
			if s.chapter == "academy":
				academy_done = true
			nightmare_done = true
			MissionFlow.start_chapter(c, s, str(s.flags["next_chapter"]))
		for sid: String in ShopRules.shops_of(c, s):
			for it: Dictionary in ShopRules.ensure(c, s, sid)["items"]:
				if c.card_kind(it["card"]) == "character" and not it["sold"] and int(s.resources.get("shards", 0)) >= int(it["price"]):
					ShopRules.buy(c, s, sid, it["card"])
		# как осторожный игрок: лечит тяжёлые травмы у торговца, укладывает раненых и измотанных в лагерь
		for sid2: String in ShopRules.shops_of(c, s):
			for h: String in MissionFlow.free_heroes(c, s):
				for tid: String in Array(s.character(h).get("traumas", [])).duplicate():
					if str(c.traumas.get(tid, {}).get("severity", "")) != "light":
						ServiceRules.perform(c, s, sid2, "heal", h, tid)
		for h2: String in MissionFlow.free_heroes(c, s):
			if TraumaRules.counted(s.character(h2).get("traumas", [])) >= 2 or PsycheRules.psyche(s, h2) < 40:
				CampRules.put(c, s, h2)
		var open := MissionFlow.open_missions(s)
		open.sort_custom(func(x: String, y: String) -> bool:
			var sx := str(c.missions[x]["type"]) == "story"
			var sy := str(c.missions[y]["type"]) == "story"
			return sx and not sy if sx != sy else x < y)
		for mid: String in open:
			var free := MissionFlow.free_heroes(c, s).filter(func(h: String) -> bool: return not MissionFlow.excluded(c, mid, h) 				and (str(c.missions[mid]["type"]) == "story" or (not CampRules.in_bed(s, h) and PsycheRules.psyche(s, h) >= 30)))
			if free.is_empty():
				continue
			var mx := int(c.missions[mid]["squad"]["max"])
			var team: Array = []
			for need: String in c.missions[mid].get("requires_heroes", []):
				if free.has(need):
					team.append(need)
			for h: String in free:
				# не берёт в отряд тех, кто не пойдёт вместе (доверие −3)
				if team.size() < mx and not team.has(h) and TrustRules.refusal(c, s, team + [h]) == "":
					team.append(h)
			if MissionFlow.can_launch(c, s, mid, team) == "":
				# как осторожный игрок: на несюжетное — только с хорошим прогнозом
				if str(c.missions[mid]["type"]) != "story" and int(MissionForecast.mission_forecast(c, s, mid, team)["value"]) < 50:
					continue
				MissionFlow.launch(c, s, mid, team)
		MissionFlow.tick(c, s, 1.0)
		for sq: Dictionary in s.squads.duplicate():
			# отряд мог исчезнуть: сюжет увёл его единственного героя (remove_card)
			if MissionFlow.squad(s, int(sq["id"])).is_empty():
				continue
			if sq["phase"] == "fork":
				# на развилке бот идёт дальше первым вариантом
				var opts: Array = sq["pending"]["report"]["fork"]["options"]
				var rf := MissionResolver.resume(c, s, int(sq["id"]), str(opts[0]["id"]))
				if not rf["ok"]:
					return {"stuck": true, "error": rf["error"]}
				s = rf["state"]
				if not rf.has("fork"):
					_count(stats, sq["mission"], rf["report"])
				continue
			if sq["phase"] != "arrived":
				continue
			var best := ""
			var best_v := -1
			var retreat := ""
			for e: Dictionary in MissionFlow.actions_for(c, s, sq["mission"], sq["heroes"]):
				var a: Dictionary = e["action"]
				if bool(a.get("retreat", false)):
					retreat = str(a["id"])
				elif e["available"]:
					var v := int(MissionForecast.action_forecast(c, s, sq["mission"], a, sq["heroes"], true)["value"])
					if v > best_v:
						best_v = v
						best = str(a["id"])
			var need := 20 if str(c.missions[sq["mission"]]["type"]) == "story" else 50
			var pick := best if best_v >= need or retreat == "" else retreat
			var r := MissionResolver.resolve(c, s, int(sq["id"]), pick)
			if not r["ok"]:
				return {"stuck": true, "error": r["error"]}
			s = r["state"]
			attempts += 1
			if not r.has("fork"):
				_count(stats, sq["mission"], r["report"])
	var grown := {"vet": 0, "evo": 0, "mut": 0}
	for cid: String in s.characters:
		for tag: String in s.characters[cid].get("tag_xp", {}):
			var gst := GrowthRules.stage(s, cid, tag)
			if gst != "":
				grown[gst] += 1
	if steps >= 12000:
		return {"stuck": true, "error": "12000 шагов: глава %s, открыто %s, отряды %s, герои %s" % [s.chapter, MissionFlow.open_missions(s),
			s.squads.map(func(q: Dictionary) -> String: return "%s:%s" % [q["mission"], q["phase"]]), MissionFlow.heroes(c, s)]}
	return {"stuck": false, "over": s.game_over, "attempts": attempts, "clock": s.clock, "grown": grown, "academy_done": academy_done,
		"shore_done": s.demo_complete and s.chapter == "shore",
		"nightmare_done": nightmare_done, "story_done": academy_done or (s.demo_complete and s.chapter == "academy"),
		"heroes": MissionFlow.heroes(c, s).size()}


func _count(stats: Dictionary, mid: String, rep: Dictionary) -> void:
	# психика: кризисы по главам (баланс docs/16 §9г)
	var ps: Dictionary = stats.get("_psy", {})
	var ch := str(mid).substr(0, 2)
	var row: Dictionary = ps.get(ch, {"missions": 0, "panic": 0, "uplift": 0, "acts": 0})
	row["missions"] += 1
	for e: Dictionary in rep.get("crises", []):
		row[str(e.get("state", "panic"))] += 1
		var hk := "hero:" + str(e.get("card", ""))
		var hr: Dictionary = ps.get(hk, {"missions": 0, "panic": 0, "uplift": 0, "acts": 0})
		hr[str(e.get("state", "panic"))] += 1
		ps[hk] = hr
	for e2: Dictionary in rep.get("entries", []):
		if str(e2.get("kind", "")) == "psy_act":
			row["acts"] += 1
	ps[ch] = row
	stats["_psy"] = ps
	var st: Dictionary = stats.get(mid, {"tries": 0, "ok": 0, "retreat": 0, "deaths": 0})
	st["tries"] += 1
	st["ok"] += 1 if rep["outcome"] in ["success", "partial"] else 0
	st["retreat"] += 1 if rep["outcome"] == "retreat" else 0
	st["deaths"] += Array(rep["deaths"]).size()
	stats[mid] = st


func test_mission_simulation() -> void:
	var c := content()
	var n := 120
	var finished := 0
	var shore := 0
	var nightmare := 0
	var over := 0
	var total_attempts := 0
	var total_clock := 0.0
	var stats := {}
	var grown := {"vet": 0, "evo": 0, "mut": 0}
	for i in n:
		var r := _bot(c, 5000 + i, stats)
		for k: String in grown:
			grown[k] += int(r.get("grown", {}).get(k, 0))
		check(not r.get("stuck", false), "бот застрял (сид %d): %s" % [5000 + i, r.get("error", "")])
		if r.get("story_done", false):
			finished += 1
		if r.get("shore_done", false):
			shore += 1
		if r.get("nightmare_done", false):
			nightmare += 1
		if r.get("over", false):
			over += 1
		total_attempts += int(r.get("attempts", 0))
		total_clock += float(r.get("clock", 0.0))
	print("   [миссии] прохождений: %d, Первый Кошмар пройден: %d, Академия пройдена: %d, Забытый Берег пройден: %d, конец игры: %d" % [n, nightmare, finished, shore, over])
	print("   [миссии] попыток миссий в среднем: %.1f, игрового времени: %.0f с (~%.0f мин)" % [float(total_attempts) / n, total_clock / n, total_clock / n / 60.0])
	print("   [рост] на прохождение: опытных тегов %.1f, эволюций %.1f, мутаций %.2f" % [float(grown["vet"]) / n, float(grown["evo"]) / n, float(grown["mut"]) / n])
	var ps: Dictionary = stats.get("_psy", {})
	for ch: String in ps:
		var row: Dictionary = ps[ch]
		if int(row["panic"]) + int(row["uplift"]) > 0:
			print("   [психика] %s: миссий %d, паник %d (%.1f%%), подъёмов %d, поступков %d" % [ch, row["missions"], row["panic"],
				100.0 * row["panic"] / maxf(1, row["missions"]), row["uplift"], row["acts"]])
	stats.erase("_psy")
	var ids: Array = stats.keys()
	ids.sort()
	for mid: String in ids:
		var st: Dictionary = stats[mid]
		print("   [миссии] %s: попыток %d, удачно %d%%, отступлений %d, погибло героев %d" % [mid, st["tries"], int(100.0 * st["ok"] / maxf(1, st["tries"])), st["retreat"], st["deaths"]])
	check(finished >= n * 0.6, "демо (Кошмар + Академия) проходится в большинстве прохождений (%d из %d)" % [finished, n])
	check(shore >= n * 0.5, "Забытый Берег проходится хотя бы в половине прохождений (%d из %d)" % [shore, n])


func test_combat_replay_matches() -> void:
	var c := content()
	for seed_value in [3, 11, 29]:
		var s := _run(seed_value)
		s.missions["MS03"] = {"status": "open", "attempts": 0}
		var sid := _arrive(c, s, "MS03", ["P01"])
		var rep: Dictionary = MissionResolver.resolve_through(c, s, sid, "MS03_fight")["report"]
		var rec: Dictionary = rep["combats"][0]
		var replay := MissionResolver.replay_session(c, rec["setup"])
		replay.auto_play()
		eq(replay.outcome, rec["outcome"], "просмотр боя совпадает с итогом (сид %d):" % seed_value)
		eq(replay.rounds_log.size(), Array(rec["rounds"]).size(), "столько же раундов:")
		for i in replay.rounds_log.size():
			eq(int(replay.rounds_log[i]["roll"]), int(rec["rounds"][i]["roll"]), "тот же бросок в раунде %d:" % (i + 1))
