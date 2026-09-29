class_name AutoPlay
extends RefCounted
## Бот-игрок: проходит игру сам, как осторожный игрок. Нужен тестам баланса (tests/test_mission_core.gd)
## и инструменту разработчика «к началу главы» (DevCheckpoints) — один и тот же код.


## Один шаг игры (docs/16 §12 — дни): решить на месте, выйти на миссию рядом, подойти к сюжету по тропам,
## не ночевать в низине перед приливом, закончить день, когда делать нечего или герои выдохлись.
## on_report(mission_id, report) — вызывается на каждый завершённый ход миссии (для статистики).
## Возвращает {state, error, chapter_started} — резолвер отдаёт новое состояние, поэтому state надо заменить.
const MOVES_PER_DAY := 4
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
	var open := MissionFlow.open_missions(s)
	open.sort_custom(func(x: String, y: String) -> bool:
		var sx := str(c.missions[x]["type"]) == "story"
		var sy := str(c.missions[y]["type"]) == "story"
		return sx and not sy if sx != sy else x < y)
	for mid: String in open:
		if TideRules.mission_flooded(c, s, mid) or not DayRules.mission_reachable(c, s, mid):
			continue
		var story := str(c.missions[mid]["type"]) == "story"
		var free := MissionFlow.free_heroes(c, s).filter(func(h: String) -> bool: return not MissionFlow.excluded(c, mid, h) \
			and (story or (not CampRules.in_bed(s, h) and PsycheRules.psyche(s, h) >= LOW_PSY and DayRules.sorties(s, h) < TIRED)))
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
		if not story and int(MissionForecast.mission_forecast(c, s, mid, team)["value"]) < 50:
			continue
		MissionFlow.launch(c, s, mid, team)
		return {"state": s, "error": "", "chapter_started": started}
	# рядом делать нечего — подойти к сюжету по тропам (переход стоит психики — не больше MOVES_PER_DAY за день)
	var moves := int(s.flags.get("bot_moves", 0))
	if moves < MOVES_PER_DAY and DayRules.restricted(c, s):
		var goal := ""
		for mid: String in open:
			if not TideRules.mission_flooded(c, s, mid) and not DayRules.mission_reachable(c, s, mid) \
					and (str(c.missions[mid]["type"]) == "story" or goal == ""):
				goal = str(c.missions[mid].get("location", ""))
				if str(c.missions[mid]["type"]) == "story":
					break
		var nxt := _next_step(c, s, goal) if goal != "" else ""
		if nxt != "" and DayRules.move(c, s, nxt, []) == "":
			s.flags["bot_moves"] = moves + 1
			return {"state": s, "error": "", "chapter_started": started}
	# не ночевать там, куда завтра придёт вода
	if TideRules.threatened(s, s.party_at) or TideRules.flooded(s, s.party_at):
		for n: String in MapRules.neighbors(c, s, s.party_at):
			if c.locations.has(n) and not TideRules.threatened(s, n) and not TideRules.flooded(s, n):
				DayRules.move(c, s, n, [])
				break
	DayRules.end_day(c, s)
	s.flags["bot_moves"] = 0
	return {"state": s, "error": "", "chapter_started": started}


## Следующий шаг по тропам к месту goal (поиск в ширину, мимо воды). "" — пути нет.
static func _next_step(c: Content, s: RunState, goal: String) -> String:
	if goal == s.party_at:
		return ""
	var prev := {s.party_at: ""}
	var queue: Array = [s.party_at]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == goal:
			break
		for n: String in MapRules.neighbors(c, s, cur):
			if prev.has(n) or not c.locations.has(n) or TideRules.flooded(s, n):
				continue
			prev[n] = cur
			queue.append(n)
	if not prev.has(goal):
		return ""
	var at := goal
	while str(prev[at]) != s.party_at and str(prev[at]) != "":
		at = str(prev[at])
	return at


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
		var need := 20 if str(c.missions[sq["mission"]]["type"]) == "story" else 50
		var pick := best if best_v >= need or retreat == "" else retreat
		var r := MissionResolver.resolve(c, s, int(sq["id"]), pick)
		if not r["ok"]:
			return {"state": s, "error": str(r["error"]), "chapter_started": started}
		s = r["state"]
		if not r.has("fork") and on_report.is_valid():
			on_report.call(sq["mission"], r["report"])
	return {"state": s, "error": "", "chapter_started": started}


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
