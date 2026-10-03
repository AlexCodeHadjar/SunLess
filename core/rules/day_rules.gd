class_name DayRules
extends RefCounted
## Дни, неделя и лагерь-стоянка (docs/16 §12, решения владельца 29.09.2026).
## Ход — день. За день отряд делает сколько угодно выходов, но герои устают: каждый следующий выход героя
## за день стоит психики (fatigue), с третьего вещи в кармашке изнашиваются сильнее — рано или поздно
## придётся «Закончить день». Пути нет: отряд сразу на месте.
## Отряд один. Где он остановился последним — там и лагерь (state.party_at). На карте-плане отряд ходит
## шагами дня по тропам (TravelRules, docs/17 §2): steps_free переходов бесплатно, дальше — марш-бросок.
## Неделя региона — фазы по дням (data/days.json; Берег: Ночь, Рассвет-отлив, Прилив и шторм, Кровавая луна
## по 2 дня): небо, вода, усталость, психика за выход.
## Ночь — в лагере: нападение (опасность места × фаза), отдых (отдых места; койка лечит грань), починка;
## затем новый день — вода (лагерь в затопленном месте — бегство), сроки, натиск, встречи мест.


static func cfg(content: Content) -> Dictionary:
	return content.days


static func region_of(content: Content, chapter: String) -> String:
	for lid: String in content.locations:
		if str(content.locations[lid].get("chapter", "")) == chapter:
			return str(content.locations[lid].get("region", ""))
	return ""


## Неделя главы: [[фаза, дней], …].
static func week(content: Content, chapter: String) -> Array:
	var w: Array = cfg(content).get("weeks", {}).get(region_of(content, chapter), [])
	return w if not w.is_empty() else [["day", 1]]


static func week_len(content: Content, chapter: String) -> int:
	var n := 0
	for ph: Array in week(content, chapter):
		n += maxi(1, int(ph[1]))
	return n


## Фаза дня: {id, name, sky, hint, tide, fatigue_mult, sortie_psyche, index, day_in, days, left, week}.
static func phase_at(content: Content, chapter: String, day: int) -> Dictionary:
	var w := week(content, chapter)
	var total := week_len(content, chapter)
	var d := posmod(day - 1, total)
	var acc := 0
	for i in w.size():
		var n := maxi(1, int(w[i][1]))
		if d < acc + n:
			var id := str(w[i][0])
			var def: Dictionary = cfg(content).get("phases", {}).get(id, {})
			return {"id": id, "name": str(def.get("name", id)), "sky": str(def.get("sky", "day")), "hint": str(def.get("hint", "")),
				"tide": str(def.get("tide", "")), "fatigue_mult": float(def.get("fatigue_mult", 1.0)),
				"sortie_psyche": int(def.get("sortie_psyche", 0)), "index": i, "day_in": d - acc + 1, "days": n,
				"left": acc + n - d, "week": (day - 1) / total + 1}
		acc += n
	return {"id": "day", "name": "День", "sky": "day", "hint": "", "tide": "", "fatigue_mult": 1.0, "sortie_psyche": 0,
		"index": 0, "day_in": 1, "days": 1, "left": 1, "week": 1}


static func phase(content: Content, state: RunState) -> Dictionary:
	return phase_at(content, state.chapter, state.day)


static func tomorrow(content: Content, state: RunState) -> Dictionary:
	return phase_at(content, state.chapter, state.day + 1)


# --- лагерь ---------------------------------------------------------------------------

## Особенности лагеря в месте: {rest, beds, danger, services}.
static func camp_at(content: Content, lid: String) -> Dictionary:
	var d: Dictionary = Dictionary(cfg(content).get("camp_default", {})).duplicate(true)
	d.merge(Dictionary(content.locations.get(lid, {}).get("camp", {})), true)
	return d


static func camp(content: Content, state: RunState) -> Dictionary:
	var c := GateRules.camp_mod(content, state, state.party_at, camp_at(content, state.party_at))
	return ZoneRules.camp_mod(content, state, state.party_at, c)


static func has_service(content: Content, state: RunState, service: String) -> bool:
	return Array(camp(content, state).get("services", [])).has(service)


## Переснарядиться (кармашки) можно только в лагере со службой equip; без карты-плана — везде.
static func can_equip(content: Content, state: RunState) -> String:
	if not restricted(content, state) or has_service(content, state, "equip"):
		return ""
	return "Переснарядиться можно только в лагере с укрытием — там, где есть «снаряжение»"


## Движение по тропам ограничено только на карте-плане.
static func restricted(content: Content, state: RunState) -> bool:
	# лагерь должен стоять на карте этой главы (иначе — глава без карты-плана или отряд ещё не пришёл)
	return state.party_at != "" and MapRules.config(content, state.chapter).get("places", {}).has(state.party_at)


static func reachable(content: Content, state: RunState, lid: String) -> bool:
	if not restricted(content, state):
		return true
	return lid == state.party_at or TravelRules.distance(content, state, lid) > 0


## Миссия в досягаемости отряда. Натиск приходит сам — до него дойти можно всегда.
static func mission_reachable(content: Content, state: RunState, mid: String) -> bool:
	var m: Dictionary = content.missions.get(mid, {})
	if str(m.get("type", "")) == "onslaught":
		return true
	return reachable(content, state, str(m.get("location", "")))


## Лавка рядом: отряд стоит у места лавки на карте-плане (или карты-плана нет).
static func shop_near(content: Content, state: RunState, sid: String) -> bool:
	if not restricted(content, state) or not MapRules.config(content, state.chapter).get("places", {}).has(sid):
		return true
	return state.party_at == sid or MapRules.neighbors(content, state, sid).has(state.party_at)


## Переход без миссии по маршруту (TravelRules.travel). "" — перешли, иначе причина. Записи — в out.
static func move(content: Content, state: RunState, lid: String, out: Array) -> String:
	return TravelRules.travel(content, state, lid, out)


# --- усталость ------------------------------------------------------------------------

## Сколько выходов герой сделал сегодня.
static func sorties(state: RunState, cid: String) -> int:
	return int(state.character(cid).get("sorties", 0))


## Герой выдохся: сегодня больше не выйдет (max_sorties выходов за день).
static func exhausted(content: Content, state: RunState, cid: String) -> bool:
	return sorties(state, cid) >= int(cfg(content).get("max_sorties", 4))


## Психика за следующий выход героя сегодня (с фазой): 0, −6, −12…
static func fatigue_cost(content: Content, state: RunState, cid: String) -> int:
	var table: Array = cfg(content).get("fatigue", [0])
	if table.is_empty():
		return 0
	var ph := phase(content, state)
	var n := sorties(state, cid)
	var loss := int(round(float(table[mini(n, table.size() - 1)]) * float(ph["fatigue_mult"])))
	return loss + int(ph["sortie_psyche"])


## Отряд вышел: он теперь там (лагерь переезжает), герои устают, вещи уставших изнашиваются сильнее.
static func on_launch(content: Content, state: RunState, mid: String, heroes: Array) -> Array:
	var out: Array = []
	var lid := str(content.missions.get(mid, {}).get("location", ""))
	if content.locations.has(lid) and not FigureRules.on(content, state):   # фигура: лагерь там, где она, — Натиск его не двигает
		state.party_at = lid
		TravelRules.visit(state, lid)
	var from := int(cfg(content).get("tired_wear_from", 3))
	var extra := int(cfg(content).get("tired_wear", 5))
	for cid: String in heroes:
		var loss := fatigue_cost(content, state, cid)
		var ch := state.character(cid)
		ch["sorties"] = sorties(state, cid) + 1
		if loss < 0:
			var why := "усталость" if int(ch["sorties"]) > 1 else str(phase(content, state)["name"]).to_lower()
			out.append_array(PsycheRules.change(content, state, cid, loss, why, heroes, null, "mission", false))
		if int(ch["sorties"]) >= from:
			for card: String in MissionFlow.pocket(state, cid):
				if WearRules.wears(content, state, card):
					state.wear[card] = mini(100, WearRules.current(state, card) + extra)
	state.clock += 1.0
	return out


# --- ночь -----------------------------------------------------------------------------

## Можно ли закончить день: "" — да.
static func can_end(state: RunState) -> String:
	if state.game_over:
		return "Прохождение окончено"
	if not state.squads.is_empty():
		return "Сначала решите, что делает отряд на месте"
	return ""


## «Закончить день»: ночь в лагере и новое утро. Возвращает записи для окна ночи.
static func end_day(content: Content, state: RunState) -> Array:
	var out: Array = []
	if can_end(state) != "":
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = state.rng_seed + 104729 * state.day + 17
	TerrainRules.tribute(content, state, out)   # дань за ночь в замке (Мрачный город); не заплатили — ночь у ворот
	var ph := phase(content, state)
	var c := camp(content, state)
	var place := str(content.locations.get(state.party_at, {}).get("name", "лагерь"))
	out.append({"kind": "night", "text": "Ночь. Лагерь: %s" % place})
	var heroes := MissionFlow.heroes(content, state)
	# 1. ночное нападение: опасность места × фаза
	var att: Dictionary = cfg(content).get("night_attack", {})
	var chance := float(c.get("danger", 0.0)) * float(att.get("phase_mult", {}).get(str(ph["id"]), 1.0))
	if bool(state.flags.get("watch", false)):   # дело лагеря «Дозор»
		chance *= float(cfg(content).get("tasks", {}).get("watch", {}).get("danger_mult", 0.5))
	if chance > 0.0 and not heroes.is_empty() and rng.randf() < chance:
		out.append_array(_ordeal(content, state, att, "На лагерь напали ночью", "нападение", rng))
		MapEventRules.night_attack(content, state)   # след на карте: метка охотника, когти на тропе к лагерю
	# 2. отдых: психика по месту, койка лечит грань, починка
	var rest := float(c.get("rest", 20))
	var bed_rest := float(cfg(content).get("bed_rest", 20))
	for cid: String in MissionFlow.heroes(content, state):
		var bed := CampRules.in_bed(state, cid)
		PsycheRules.rest(state, cid, rest + (bed_rest if bed else 0.0))
		state.character(cid)["sorties"] = 0
		if bed and EdgeRules.on_edge(state, cid):
			EdgeRules.recover(content, state, cid, "отлежался в лагере", out)
	out.append({"kind": "rest", "text": "Отдых: психика +%d%s" % [int(rest), (", на койке ещё +%d" % int(bed_rest)) if not CampRules.beds(state).is_empty() else ""]})
	if Array(c.get("services", [])).has("repair"):
		var fixed := 0
		for card: String in state.wear.keys():
			if state.owns(card) and WearRules.current(state, card) > WearRules.START:
				state.wear[card] = maxi(WearRules.START, WearRules.current(state, card) - int(cfg(content).get("repair", 10)))
				fixed += 1
		if fixed > 0:
			out.append({"kind": "repair", "text": "Починили вещи: %d" % fixed})
	TerrainRules.exposed_night(content, state, out)   # ночь в открытом пепле в бурю
	state.camp["beds"] = []
	state.flags.erase("event_done")
	state.flags.erase("figure_jump")
	# 3. новый день: шаги и дела лагеря снова свободны
	TravelRules.new_day(state)
	DayPlanner.new_day(state)
	state.day += 1
	state.clock = float(state.day) * 100.0
	var today := phase(content, state)
	if str(today["id"]) != str(ph["id"]):
		out.append({"kind": "phase", "text": "%s. %s" % [today["name"], today["hint"]]})
	TideRules.count(state)
	out.append_array(TideRules.tick(content, state))
	out.append_array(TideRules.week(content, state, today, tomorrow(content, state), rng))
	if TideRules.flooded(state, state.party_at):
		out.append_array(_flee(content, state, rng))
	out.append_array(MissionFlow.expire_day(content, state))
	out.append_array(GateRules.night(content, state, rng))   # прорывы и рой (Академия), Врата (Город)
	out.append_array(TerrainRules.morning(content, state, rng, ph))   # буря, котловины и островки, обвалы
	if str(ph["id"]) == "storm" and str(today["id"]) != "storm":
		MapEventRules.after_storm(content, state, rng)   # море выбросило сундук, молния опалила место
	out.append_array(ZoneRules.night(content, state))   # территории растут, Очарование
	out.append_array(MoverRules.night(content, state, rng))   # Демон, тень под водой, охотники, статуи
	out.append_array(MissionFlow.spawn_day(content, state))
	out.append_array(OnslaughtRules.tick(content, state))
	# 4. утро: планировщик проверяет, что сегодня есть чем заняться (docs/17 §4)
	out.append_array(DayPlanner.ensure(content, state))
	return out


## Испытание всего отряда ночью (нападение, вода): лучший герой проходит проверку — иначе один падает.
static func _ordeal(content: Content, state: RunState, d: Dictionary, title: String, reason: String, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var heroes := MissionFlow.heroes(content, state)
	if heroes.is_empty():
		return out
	var st := {"name": title, "req": d.get("req", {"power": 6}), "tags": d.get("tags", [])}
	var best := MissionForecast.stage_actor(content, state, {}, {}, st, heroes)
	var chance := int(best.get("chance", 50))
	var ok := rng.randi_range(1, 100) <= chance
	var entries: Array = []
	for cid: String in heroes:
		entries.append_array(PsycheRules.change(content, state, cid, int(d.get("ok_psyche" if ok else "fail_psyche", -8)), reason, heroes, rng, "mission", false))
	if not ok:
		var victim: String = heroes[rng.randi_range(0, heroes.size() - 1)]
		EdgeRules.defeat(content, state, victim, MissionFlow.pocket(state, victim), rng, {}, entries)
	out.append({"kind": "night_ordeal", "ok": ok, "chance": chance, "hero": str(best.get("hero", "")),
		"text": "%s — %s" % [title, "отбились" if ok else "не все целы"], "entries": entries})
	out.append_array(entries)
	return out


## Вода пришла в лагерь: бегство к ближайшему сухому месту.
static func _flee(content: Content, state: RunState, rng: RandomNumberGenerator) -> Array:
	var out := _ordeal(content, state, cfg(content).get("flooded_camp", {}), "Вода пришла в лагерь", "прилив", rng)
	var here := MapRules.anchor(content, state, state.party_at)
	var best := ""
	var bd := INF
	for lid: String in MapRules.config(content, state.chapter).get("places", {}):
		if not TravelRules.can_stop(content, state, lid):
			continue
		var d := MapRules.anchor(content, state, lid).distance_to(here)
		if d < bd:
			bd = d
			best = lid
	if best != "":
		state.party_at = best
		TravelRules.visit(state, best)
		out.append({"kind": "move", "text": "Отряд бежал от воды: %s" % content.locations[best].get("name", best)})
	return out
