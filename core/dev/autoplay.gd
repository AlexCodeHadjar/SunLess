class_name AutoPlay
extends RefCounted
## Бот-игрок: проходит игру сам, как осторожный игрок. Нужен тестам баланса (tests/test_mission_core.gd)
## и инструменту разработчика «к началу главы» (DevCheckpoints) — один и тот же код.


## Один шаг игры (docs/16 §12, docs/17 — дни): решить на месте, выйти на миссию (отряд сам идёт по маршруту;
## видит только открытое на карте, как игрок), дела лагеря, не ночевать в низине перед приливом,
## закончить день, когда делать нечего или герои выдохлись.
## on_report(mission_id, report) — вызывается на каждый завершённый ход миссии (для статистики).
## Возвращает {state, error, chapter_started} — резолвер отдаёт новое состояние, поэтому state надо заменить.
const TIRED := 3            # после стольких выходов за день на несюжетное не идёт
const LOW_PSY := 35         # и с такой психикой — тоже


static func step(c: Content, s: RunState, on_report: Callable = Callable()) -> Dictionary:
	var started := ""
	# Воспоминание-добыча: бот берёт первую из трёх карт
	while not LootRules.pending(s).is_empty():
		LootRules.take(c, s, str(LootRules.pending(s)["options"][0]))
	if s.demo_complete:
		var nxt := str(s.flags.get("next_chapter", ""))
		if nxt == "":
			return {"state": s, "error": "", "chapter_started": "", "finished": true}
		MissionFlow.start_chapter(c, s, nxt)
		return {"state": s, "error": "", "chapter_started": nxt}   # новая глава — с чистого листа, ходы со следующего шага
	# отряд на месте — решить, что он делает
	if not s.squads.is_empty():
		return _resolve(c, s, on_report)
	for sid: String in ShopRules.shops_of(c, s):
		if not DayRules.shop_near(c, s, sid):
			continue
		for it: Dictionary in ShopRules.ensure(c, s, sid)["items"]:
			if c.card_kind(it["card"]) == "character" and not it["sold"] and int(s.resources.get("shards", 0)) >= int(it["price"]):
				ShopRules.buy(c, s, sid, it["card"])
	# как осторожный игрок: кто на грани — на койку, если здесь есть где лечь
	for h2: String in MissionFlow.free_heroes(c, s):
		if EdgeRules.on_edge(s, h2):
			CampRules.put(c, s, h2)
	if FigureRules.on(c, s):
		return _figure_step(c, s, started)
	var open := MissionFlow.open_missions(s)
	open.sort_custom(func(x: String, y: String) -> bool:
		var sx := str(c.missions[x]["type"]) == "story"
		var sy := str(c.missions[y]["type"]) == "story"
		return sx and not sy if sx != sy else x < y)
	# сюжет стоит (ждёт закрытых Врат) дольше 4 дней — бот, как игрок, идёт на Врата при любом прогнозе
	if open.any(func(x: String) -> bool: return str(c.missions[x]["type"]) == "story"):
		s.flags["bot_story_day"] = s.day
	var desperate := s.day - int(s.flags.get("bot_story_day", s.day)) > 4
	for mid: String in open:
		if TideRules.mission_flooded(c, s, mid) or not DayRules.mission_reachable(c, s, mid):
			continue
		var story := str(c.missions[mid]["type"]) == "story"
		# как игрок: видит только открытое на карте; на несюжетное — без марш-броска
		if DayRules.restricted(c, s) and not MapRules.revealed(c, s, str(c.missions[mid].get("location", ""))):
			s.flags["bot_hidden"] = int(s.flags.get("bot_hidden", 0)) + 1
			continue
		if not story and DayRules.restricted(c, s) and str(c.missions[mid]["type"]) != "onslaught" 				and TravelRules.march_steps(c, s, TravelRules.distance(c, s, str(c.missions[mid].get("location", "")))) > 0:
			continue
		var push := desperate and GateRules.mission_ids(c, s).has(mid)   # сюжет стоит — идут и усталыми
		var free := MissionFlow.free_heroes(c, s).filter(func(h: String) -> bool: return not MissionFlow.excluded(c, mid, h) \
			and (story or push or (not CampRules.in_bed(s, h) and PsycheRules.psyche(s, h) >= LOW_PSY and DayRules.sorties(s, h) < TIRED)))
		if free.is_empty():
			continue
		var mx := int(c.missions[mid]["squad"]["max"])
		var team: Array = []
		for need: String in c.missions[mid].get("requires_heroes", []):
			if free.has(need):
				team.append(need)
		for h: String in free:
			# не берёт в отряд тех, кто не пойдёт вместе (доверие −3)
			if team.size() < mx and not team.has(h) and (story or TrustRules.refusal(c, s, team + [h]) == ""):
				team.append(h)
		if MissionFlow.can_launch(c, s, mid, team) != "":
			continue
		# как игрок: раскладывает свободные усиления по кармашкам отряда — если здесь можно переснарядиться
		if DayRules.can_equip(c, s) == "":
			equip(c, s, team)
		# как осторожный игрок: на несюжетное — только с хорошим прогнозом
		var urgent := GateRules.mission_ids(c, s).has(mid)   # Врата, волны, прорывы — как игрок, бот их не бросает
		if not story and int(MissionForecast.mission_forecast(c, s, mid, team)["value"]) < ((0 if desperate else 30) if urgent else 50):
			continue
		MissionFlow.launch(c, s, mid, team)
		return {"state": s, "error": "", "chapter_started": started}
	# дела лагеря (DayPlanner): дозор в опасном месте, разведка, сбор — кем-то бодрым
	for task: String in DayPlanner.tasks_left(c, s):
		if task == "watch" and float(DayRules.camp(c, s).get("danger", 0.0)) < 0.15:
			continue
		for h: String in MissionFlow.free_heroes(c, s):
			if PsycheRules.psyche(s, h) >= LOW_PSY and DayRules.sorties(s, h) < TIRED:
				DayPlanner.do_task(c, s, task, h)
				return {"state": s, "error": "", "chapter_started": started}
	# не ночевать там, куда завтра придёт вода
	if TideRules.threatened(s, s.party_at) or TideRules.flooded(s, s.party_at):
		for n: String in MapRules.neighbors(c, s, s.party_at):
			if TravelRules.can_stop(c, s, n) and MapRules.revealed(c, s, n) and not TideRules.threatened(s, n):
				TravelRules.travel(c, s, n, [])
				break
	DayRules.end_day(c, s)
	return {"state": s, "error": "", "chapter_started": started}


## Отряд на месте: выбрать действие с лучшим прогнозом (или отступить от безнадёжного).
static func _resolve(c: Content, s: RunState, on_report: Callable) -> Dictionary:
	var started := ""
	for sq: Dictionary in s.squads.duplicate():
		# отряд мог исчезнуть: сюжет увёл его единственного героя (remove_card)
		if MissionFlow.squad(s, int(sq["id"])).is_empty():
			continue
		if sq["phase"] == "fork":
			# на развилке бот идёт дальше первым вариантом
			var opts: Array = sq["pending"]["report"]["fork"]["options"]
			var rf := MissionResolver.resume(c, s, int(sq["id"]), str(opts[0]["id"]))
			if not rf["ok"]:
				return {"state": s, "error": str(rf["error"]), "chapter_started": started}
			s = rf["state"]
			if not rf.has("fork") and on_report.is_valid():
				on_report.call(sq["mission"], rf["report"])
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
		var story_m := str(c.missions[sq["mission"]]["type"]) == "story"
		var urgent_m := GateRules.mission_ids(c, s).has(str(sq["mission"]))
		var need := 20 if story_m else ((0 if s.day - int(s.flags.get("bot_story_day", s.day)) > 4 else 30) if urgent_m else 50)
		# сюжет не ждёт вечно: после двух отступлений идут на лучшее, что есть (иначе глава встала бы без спутников)
		if story_m and int(s.missions.get(sq["mission"], {}).get("retreats", 0)) >= 2:
			need = 0
		var pick := best if best_v >= need or retreat == "" else retreat
		if pick == retreat and story_m:
			s.missions[sq["mission"]]["retreats"] = int(s.missions[sq["mission"]].get("retreats", 0)) + 1
		var r := MissionResolver.resolve(c, s, int(sq["id"]), pick)
		if not r["ok"]:
			return {"state": s, "error": str(r["error"]), "chapter_started": started}
		s = r["state"]
		if not r.has("fork") and on_report.is_valid():
			on_report.call(sq["mission"], r["report"])
	FigureRules.end_after_event(c, s)   # фигура: событие — полдня
	return {"state": s, "error": "", "chapter_started": started}


## Фигура (docs/18): день — две половины, действие — полдня. Лучшее событие (сюжет первым) — здесь: провести; на
## другом участке — шаг фигуры к нему; иначе дело лагеря или переждать полдня. Не ночевать там, куда придёт вода.
static func _figure_step(c: Content, s: RunState, started: String) -> Dictionary:
	var open := MissionFlow.open_missions(s)
	open.sort_custom(func(x: String, y: String) -> bool:
		var sx := str(c.missions[x]["type"]) == "story"
		var sy := str(c.missions[y]["type"]) == "story"
		return sx and not sy if sx != sy else x < y)
	if open.any(func(x: String) -> bool: return str(c.missions[x]["type"]) == "story"):
		s.flags["bot_story_day"] = s.day
	# сюжет стоит больше 4 дней, бот два дня (четыре половины) подряд просто ждал или больше трёх дней не провёл ни одного
	# события (шаги фигуры не в счёт) — идёт на лучшее при любом прогнозе
	if not s.flags.has("bot_event_day"):
		s.flags["bot_event_day"] = s.day
	var desperate := s.day - int(s.flags.get("bot_story_day", s.day)) > 4 or int(s.flags.get("bot_idle", 0)) >= 4 		or s.day - int(s.flags["bot_event_day"]) > 3
	# события по близости: сюжет первым, затем ближние; прогноз — только пока не нашлось подходящее
	var cands: Array = []
	var ra := FigureRules.reach_all(c, s, open)
	for mid: String in open:
		if MissionFlow.chapter_of(c, mid) != s.chapter or TideRules.mission_flooded(c, s, mid):
			continue
		var r := int(ra[mid])
		if r < 0:
			continue
		if str(c.missions[mid]["type"]) != "onslaught" and not MapRules.revealed(c, s, str(c.missions[mid].get("location", ""))):
			s.flags["bot_hidden"] = int(s.flags.get("bot_hidden", 0)) + 1
			continue
		# сюжет, затем побочные, Врата, волны и Натиск, затем случайные встречи; внутри — ближние первыми
		var typ := str(c.missions[mid]["type"])
		var rank := 0 if typ == "story" else (1 if typ in ["side", "onslaught"] or GateRules.mission_ids(c, s).has(mid) else 2)
		cands.append([rank, r, mid])
	cands.sort_custom(func(x: Array, y: Array) -> bool: return x < y)
	var target := ""
	for cd: Array in cands:
		var mid: String = cd[2]
		var team := _team(c, s, mid, desperate)
		if team.is_empty():
			continue
		if int(cd[1]) == 0:
			# сюжет — только свежим отрядом: кто на грани — сперва отдых и побочные дела
			if int(cd[0]) == 0 and not desperate and not _fresh(s, team):
				continue
			if MissionFlow.can_launch(c, s, mid, team) != "":
				continue
			if DayRules.can_equip(c, s) == "":
				equip(c, s, team)
			MissionFlow.launch(c, s, mid, team)
			s.flags["bot_idle"] = 0
			s.flags["bot_event_day"] = s.day
			return {"state": s, "error": "", "chapter_started": started}
		target = mid   # ближайшее подходящее (сюжет — первым)
		break
	if target != "":
		var path := TravelRules.route(c, s, s.party_at, str(c.missions[target].get("location", "")))
		if not path.is_empty() and FigureRules.move(c, s, str(path[0]))["ok"]:
			s.flags["bot_idle"] = 0
			return {"state": s, "error": "", "chapter_started": started}
	# вода идёт — уйти на сухой соседний участок
	if TideRules.threatened(s, s.party_at) or TideRules.flooded(s, s.party_at):
		for n: String in FigureRules.targets(c, s):
			if not TideRules.threatened(s, n) and MapRules.revealed(c, s, n) and FigureRules.move(c, s, n)["ok"]:
				return {"state": s, "error": "", "chapter_started": started}
	s.flags["bot_idle"] = int(s.flags.get("bot_idle", 0)) + 1
	# дело лагеря — тоже полдня: лучше, чем просто ждать
	for task: String in DayPlanner.tasks_left(c, s):
		if task == "watch" and float(DayRules.camp(c, s).get("danger", 0.0)) < 0.15:
			continue
		for h: String in MissionFlow.free_heroes(c, s):
			if PsycheRules.psyche(s, h) >= LOW_PSY and FigureRules.task(c, s, task, h)["ok"]:
				return {"state": s, "error": "", "chapter_started": started}
	FigureRules.wait(c, s)   # переждать полдня
	return {"state": s, "error": "", "chapter_started": started}


## Отряд свеж: никто не на грани смерти (провал на грани — бросок смерти).
static func _fresh(s: RunState, team: Array) -> bool:
	return team.all(func(h: String) -> bool: return not EdgeRules.on_edge(s, h))


## Кого бот отправит на событие ([] — не пойдёт): как в обычном шаге — сюжет всегда, остальное с хорошим прогнозом.
static func _team(c: Content, s: RunState, mid: String, desperate: bool) -> Array:
	var story := str(c.missions[mid]["type"]) == "story"
	var push := desperate and GateRules.mission_ids(c, s).has(mid)
	# на грани смерти — только сюжет или когда прижало: провал на грани — бросок смерти
	var free := MissionFlow.free_heroes(c, s).filter(func(h: String) -> bool: return not MissionFlow.excluded(c, mid, h) \
		and (story or desperate or not EdgeRules.on_edge(s, h)) \
		and (story or push or (not CampRules.in_bed(s, h) and PsycheRules.psyche(s, h) >= LOW_PSY and DayRules.sorties(s, h) < TIRED)))
	if free.is_empty():
		return []
	var mx := int(c.missions[mid]["squad"]["max"])
	var team: Array = []
	for need: String in c.missions[mid].get("requires_heroes", []):
		if free.has(need):
			team.append(need)
	for h: String in free:
		if team.size() < mx and not team.has(h) and (story or TrustRules.refusal(c, s, team + [h]) == ""):
			team.append(h)
	if team.size() < MissionFlow.squad_min(c, s, mid):
		return []
	for need2: String in c.missions[mid].get("requires_heroes", []):
		if not team.has(need2):
			return []
	var urgent := GateRules.mission_ids(c, s).has(mid)
	if not story and int(MissionForecast.mission_forecast(c, s, mid, team)["value"]) < ((0 if desperate else 30) if urgent else 50):
		return []
	return team


## Ведёт ли в главу сюжет (у какой-нибудь миссии next_chapter = глава).
static func _reachable_chapter(c: Content, chapter: String) -> bool:
	for mid: String in c.missions:
		if str(c.missions[mid].get("next_chapter", "")) == chapter:
			return true
	return false


## Начало главы-черновика: новое прохождение сразу с этой главы, отряд и осколки — из регионa (start_heroes, start_shards).
static func draft_start(c: Content, chapter: String, seed_value: int) -> RunState:
	var s := MissionFlow.new_run(c, seed_value, chapter)
	var reg := DayRules.region_of(c, chapter)
	var r: Dictionary = c.regions.get(reg, {})
	for cid: String in r.get("start_heroes", []):
		EffectApplier.add_card(c, s, cid)
	for card: String in r.get("start_cards", []):
		EffectApplier.add_card(c, s, card)
	s.resources["shards"] = int(r.get("start_shards", s.resources.get("shards", 10)))
	s.region = reg
	return s


## Усиления, не занятые героями на миссии, — по три в кармашек каждому из отряда (сначала первому).
static func equip(c: Content, s: RunState, team: Array) -> void:
	var spare: Array = []
	for card: String in s.collection:
		if c.card_kind(card) != "enhancement":
			continue
		var owner := MissionFlow.pocket_owner(s, card)
		if owner != "" and MissionFlow.on_mission(s, owner):
			continue
		spare.append(card)
	for cid: String in team:
		s.character(cid)["pocket"] = []
	for cid: String in s.characters:
		if not MissionFlow.on_mission(s, cid):
			var keep: Array = Array(s.character(cid).get("pocket", [])).filter(func(x: String) -> bool: return not spare.has(x))
			s.character(cid)["pocket"] = keep
	var i := 0
	for cid: String in team:
		var pocket: Array = []
		while pocket.size() < 3 and i < spare.size():
			pocket.append(spare[i])
			i += 1
		s.character(cid)["pocket"] = pocket


## Прохождение ботом до начала главы chapter (сразу после её открытия). Пробует несколько зёрен,
## пока прохождение не дойдёт живым. Возвращает {ok, state, error}.
static func to_chapter(c: Content, chapter: String, seed_value: int = 1, tries: int = 12) -> Dictionary:
	var last := ""
	# глава-черновик, в которую сюжет пока не ведёт: начать сразу со стартовым отрядом региона
	if chapter != "nightmare" and not _reachable_chapter(c, chapter):
		return {"ok": true, "state": draft_start(c, chapter, seed_value), "error": ""}
	for t in tries:
		var s := MissionFlow.new_run(c, seed_value + t)
		if s.chapter == chapter:
			return {"ok": true, "state": s, "error": ""}
		var steps := 0
		while steps < 12000 and not s.game_over:
			steps += 1
			var r := step(c, s)
			s = r["state"]
			if str(r["error"]) != "":
				last = str(r["error"])
				break
			if bool(r.get("finished", false)):
				last = "игра закончилась раньше главы %s" % chapter
				break
			if str(r["chapter_started"]) == chapter:
				return {"ok": true, "state": s, "error": ""}
		if s.game_over:
			last = "отряд погиб до главы %s" % chapter
	return {"ok": false, "state": null, "error": last}
