class_name GateRules
extends RefCounted
## Угрозы-точки карты-плана: прорывы Академии (docs «Глава 2 — Академия — карта»), Врата Кошмара в Городе людей
## (тот же механизм, docs «Город людей») — настройки в data/maps/<регион>.json → threat.
## Точка (B1…/G1…) проходит стадии: signal (сигнал: трещины, сирены; день на подготовку) → open (прорыв: миссия
## на день) → sealed (заложен/закрыт, ремонт N дней) → снова пусто. Сигнал можно «отложить» (укрепить участок) или
## закрыть засадой; прорыв закрывает его миссия (команда threat do=seal).
## Не пришли за день — из точки выходит рой: подвижная угроза, каждую ночь шаг по тропам к цели (Академия — Зал
## капсул). Где рой — тревога и миссия «Рой в …» на день; не отбили — место повреждено (или горит), рой идёт дальше;
## забаррикадированное место рой обходит. Дошёл до цели — миссия-оборона с высокой ставкой.
## Пока есть прорыв или рой — Тревога: у мест в тревоге службы закрыты, отдых хуже. Тревога прошла — повреждённое
## чинится (repair N дней → целое).
## Город людей (threat.kind = gate, docs «Город людей — нападения из Врат»): Врата стоят, пока их не закроют
## (предвестие 1–2 дня → открываются только ночью → закрыты миссией → шрам); ранг 1–3 (модификаторы gate_rankN),
## виден после разведки. Из открытых Врат в фазы движения выходит волна (одна на Врата): идёт в соседний квартал,
## где больше людей; в квартале стоит до двух ночей — повреждён, затем разрушен — и идёт дальше. Эвакуированный
## квартал волна проходит, но его всё равно задевает. Мост можно взорвать (тропа закрыта на неделю). Паника города
## 0–100 растёт от Врат и разрушений, падает с закрытыми Вратами. Тревога — двое Врат и больше: укрытия и госпиталь
## переполнены, подземка и вокзал закрыты. Кварталы без волны и без Врат рядом — в ремонт.
## Состояние: state.flags — gates {точка: {stage, open_day, left, rank, known, held}}, sites {место: {state, left}},
## swarms [{at, from, point, nights, path}], gate_next (день следующего сигнала), gate_once [точки «раз за главу»],
## panic (паника города), evac {квартал: до какого дня эвакуирован}.

const STAGES := ["signal", "open", "sealed", "scar"]
## облик места → запасные по порядку, если такой картинки у места нет
const FALLBACK := {"fight": ["alarm"], "burning": ["damaged"], "ruined": ["damaged", "burned"], "damaged": ["burned", "fight", "alarm"],
	"crowded": ["alarm"], "lockdown": ["alarm"], "overcrowded": ["alarm"], "leak": ["alarm"], "breached": ["damaged"],
	"sealed": ["repair"], "closed": ["alarm"], "collapsed": ["damaged"], "temporary": ["repair"]}


static func cfg(content: Content, state: RunState) -> Dictionary:
	return Dictionary(MapRules.config(content, state.chapter).get("threat", {}))


static func active(content: Content, state: RunState) -> bool:
	return not cfg(content, state).is_empty()


## breach — прорывы Академии, gate — Врата города.
static func kind(content: Content, state: RunState) -> String:
	return str(cfg(content, state).get("kind", "breach"))


## Паника города 0–100.
static func panic(state: RunState) -> int:
	return int(state.flags.get("panic", 0))


static func add_panic(content: Content, state: RunState, delta: int) -> void:
	if not cfg(content, state).has("panic"):
		return
	state.flags["panic"] = clampi(panic(state) + delta, 0, 100)


## Квартал эвакуирован (волна проходит мимо, людей нет).
static func evacuated(state: RunState, lid: String) -> bool:
	return int(Dictionary(state.flags.get("evac", {})).get(lid, 0)) >= state.day


## Открытые Врата (города) / прорывы.
static func open_count(state: RunState) -> int:
	var n := 0
	for p: String in points(state):
		if str(points(state)[p].get("stage", "")) == "open":
			n += 1
	return n


## Большая Тревога города: открыты Врата не меньше alarm_gates.
static func big_alarm(content: Content, state: RunState) -> bool:
	return kind(content, state) == "gate" and open_count(state) >= int(cfg(content, state).get("alarm_gates", 2))


static func points(state: RunState) -> Dictionary:
	return Dictionary(state.flags.get("gates", {}))


static func sites(state: RunState) -> Dictionary:
	return Dictionary(state.flags.get("sites", {}))


static func swarms(state: RunState) -> Array:
	return Array(state.flags.get("swarms", []))


static func stage(state: RunState, point: String) -> String:
	return str(points(state).get(point, {}).get("stage", ""))


## Облик места от угроз ("" — нет): тревога, бой, повреждён, горит, забаррикадирован, ремонт…
static func site_state(state: RunState, lid: String) -> String:
	return str(sites(state).get(lid, {}).get("state", ""))


## Тревога: открыт прорыв или по карте идёт рой.
static func alarm(state: RunState) -> bool:
	if not swarms(state).is_empty():
		return true
	for p: String in points(state):
		if str(points(state)[p].get("stage", "")) == "open":
			return true
	return false


static func point_def(content: Content, state: RunState, point: String) -> Dictionary:
	return Dictionary(cfg(content, state).get("points", {}).get(point, {}))


static func place_name(content: Content, lid: String) -> String:
	return str(content.locations.get(lid, {}).get("name", lid))


## Все миссии угроз карты: сигналы, проломы, рой, пожары, оборона цели.
static func mission_ids(content: Content, state: RunState) -> Array:
	var c := cfg(content, state)
	var out: Array = []
	for pid: String in c.get("points", {}):
		out.append(str(c["points"][pid].get("signal", "")))
		out.append(str(c["points"][pid].get("open", "")))
	for pid: String in c.get("points", {}):
		if c["points"][pid].has("scar"):
			out.append(str(c["points"][pid]["scar"]))
	out.append_array(Dictionary(c.get("swarm", {})).values())
	out.append_array(Dictionary(c.get("fire", {})).values())
	out.append(str(c.get("core", "")))
	return out


# --- облик мест ----------------------------------------------------------------------------

static func set_site(state: RunState, lid: String, st: String, left: int = 0) -> void:
	var s := sites(state).duplicate()
	if st == "":
		s.erase(lid)
	else:
		s[lid] = {"state": st, "left": left}
	state.flags["sites"] = s


## Какой облик рисовать у места: свой, если есть картинка, иначе запасной.
static func visible_state(state: RunState, lid: String, have: Array) -> String:
	var st := site_state(state, lid)
	if st == "":
		return ""
	if have.has(st):
		return st
	for fb: String in FALLBACK.get(st, []):
		if have.has(fb):
			return fb
	return ""


## Место нельзя пройти: забаррикадировано до конца тревоги или мост обрушен.
static func blocked(state: RunState, lid: String) -> bool:
	return site_state(state, lid) in ["barricaded", "collapsed"]


## Лагерь в месте с угрозой: отдых хуже, койки меньше, службы закрыты (кроме лечения).
static func camp_mod(content: Content, state: RunState, lid: String, camp: Dictionary) -> Dictionary:
	if not active(content, state):
		return camp
	var st := site_state(state, lid)
	var d := camp.duplicate(true)
	var keep := ["heal"]
	match st:
		"alarm", "fight", "crowded", "lockdown", "leak", "overcrowded", "closed":
			d["rest"] = int(d.get("rest", 20)) + int(cfg(content, state).get("alarm_rest", -10))
			d["services"] = Array(d.get("services", [])).filter(func(x: String) -> bool: return keep.has(x))
			if st in ["crowded", "overcrowded"]:
				d["beds"] = 0
		"damaged", "repair", "breached", "sealed":
			d["rest"] = int(d.get("rest", 20)) - 5
			d["beds"] = maxi(0, int(d.get("beds", 0)) - 1)
		"burning", "ruined", "collapsed":
			d["rest"] = 0
			d["beds"] = 0
			d["services"] = []
			d["danger"] = float(d.get("danger", 0.0)) + 0.2
	if alarm(state):
		d["danger"] = float(d.get("danger", 0.0)) * float(cfg(content, state).get("alarm_danger", 1.5))
	if panic(state) >= 60:   # паника в городе: отдых хуже
		d["rest"] = int(d.get("rest", 20)) - 5
	return d


# --- миссии угроз ---------------------------------------------------------------------------

static func _open(content: Content, state: RunState, mid: String) -> Array:
	if mid == "" or not content.missions.has(mid):
		return []
	return MissionFlow.open(content, state, mid, true)


static func _status(state: RunState, mid: String) -> String:
	return str(state.missions.get(mid, {}).get("status", ""))


## Миссия открыта в эту ночь и ещё ждёт отряд: у игрока день на ответ.
static func _fresh(state: RunState, mid: String) -> bool:
	return mid != "" and _status(state, mid) == "open" and int(state.missions.get(mid, {}).get("opened_day", 0)) >= state.day


## Миссия не сделана: открыта (ещё ждёт), истекла или отряд на ней не выстоял.
static func _missed(state: RunState, mid: String) -> bool:
	return mid != "" and _status(state, mid) in ["expired", "failed"]


# --- ночь ------------------------------------------------------------------------------------

## Ночь (DayRules.end_day, после сроков миссий): стадии точек, шаг роя, ремонт, новый сигнал. События — для окна ночи.
static func night(content: Content, state: RunState, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var c := cfg(content, state)
	if c.is_empty():
		return out
	if kind(content, state) == "gate":
		return _night_city(content, state, rng)
	_tick_sites(content, state, rng, out)
	_tick_points(content, state, rng, out)
	_tick_swarms(content, state, rng, out)
	if not alarm(state):
		_after_alarm(content, state, rng, out)
	_maybe_signal(content, state, rng, out)
	return out


## Ремонт и заложенные проломы: счётчики дней.
static func _tick_sites(content: Content, state: RunState, _rng: RandomNumberGenerator, out: Array) -> void:
	var s := sites(state).duplicate(true)
	for lid: String in s.keys():
		var e: Dictionary = s[lid]
		if str(e.get("state", "")) == "repair":
			e["left"] = int(e.get("left", 1)) - 1
			if int(e["left"]) <= 0:
				s.erase(lid)
				out.append({"kind": "repair", "text": "%s — отремонтировано" % place_name(content, lid)})
	state.flags["sites"] = s
	var p := points(state).duplicate(true)
	for pid: String in p.keys():
		var e2: Dictionary = p[pid]
		if str(e2.get("stage", "")) == "sealed":
			e2["left"] = int(e2.get("left", 1)) - 1
			if int(e2["left"]) <= 0:
				p.erase(pid)
				var site := str(point_def(content, state, pid).get("site", ""))
				if site != "" and str(point_def(content, state, pid).get("site_states", {}).get("sealed", "")) == "":
					set_site(state, site, "")
	state.flags["gates"] = p


static func _tick_points(content: Content, state: RunState, _rng: RandomNumberGenerator, out: Array) -> void:
	var p := points(state).duplicate(true)
	for pid: String in MissionFlow._sorted(p):
		var e: Dictionary = p[pid]
		var d := point_def(content, state, pid)
		match str(e.get("stage", "")):
			"signal":
				if state.day >= int(e.get("open_day", state.day)):
					e["stage"] = "open"
					p[pid] = e
					state.flags["gates"] = p
					out.append_array(_on_open(content, state, pid, d))
			"open":
				var mid := str(d.get("open", ""))
				if _missed(state, mid) or not content.missions.has(mid):
					# прорыв не закрыли за день: рой уходит внутрь, пролом закладывают за его спиной
					e["stage"] = "sealed"
					e["left"] = int(cfg(content, state).get("sealed_days", 3))
					p[pid] = e
					state.flags["gates"] = p
					out.append_array(_swarm_enter(content, state, pid, d))
	state.flags["gates"] = p


static func _on_open(content: Content, state: RunState, pid: String, d: Dictionary) -> Array:
	var out: Array = []
	var near := str(d.get("near", ""))
	var site := str(d.get("site", ""))
	if site != "":
		set_site(state, site, str(d.get("site_states", {}).get("open", "alarm")))
	for lid: String in Array(d.get("alarm", [near])):
		if site_state(state, lid) in ["", "repair"]:
			set_site(state, lid, "alarm")
	out.append({"kind": "breach", "text": "%s: %s — Тревога" % [str(cfg(content, state).get("open_text", "Прорыв")), str(d.get("name", place_name(content, near)))]})
	out.append_array(_open(content, state, str(d.get("open", ""))))
	return out


static func _swarm_enter(content: Content, state: RunState, pid: String, d: Dictionary) -> Array:
	var at := str(d.get("enter", d.get("near", "")))
	if at == "" or not content.locations.has(at):
		return []
	var sw := swarms(state).duplicate(true)
	sw.append({"at": at, "from": "", "point": pid})
	state.flags["swarms"] = sw
	return _swarm_arrive(content, state, at, [{"kind": "swarm", "text": "Прорыв не закрыли — рой в кампусе: %s" % place_name(content, at)}])


## Рой пришёл в место: тревога и миссия «Рой в …» на день.
static func _swarm_arrive(content: Content, state: RunState, at: String, out: Array) -> Array:
	var c := cfg(content, state)
	if at == str(c.get("target", "")):
		set_site(state, at, "lockdown")
		out.append({"kind": "swarm", "text": "Рой у %s! %s" % [place_name(content, at), str(c.get("core_text", ""))]})
		out.append_array(_open(content, state, str(c.get("core", ""))))
		return out
	if site_state(state, at) != "barricaded":
		set_site(state, at, "fight" if MapRules.states(content, state, at).has("fight") else "alarm")
	out.append_array(_open(content, state, str(c.get("swarm", {}).get(at, ""))))
	return out


## Ночь для роя: не отбит — место повреждено (или горит), рой идёт на шаг к цели.
static func _tick_swarms(content: Content, state: RunState, rng: RandomNumberGenerator, out: Array) -> void:
	var c := cfg(content, state)
	var keep: Array = []
	for sw: Dictionary in swarms(state):
		var at := str(sw.get("at", ""))
		if at == str(c.get("target", "")):
			var core := str(c.get("core", ""))
			if _fresh(state, core):
				keep.append(sw)   # ещё день на оборону
				continue
			# оборону не удержали (рой, отбитый миссией, сюда не доходит — его снимает команда repel)
			set_site(state, at, "damaged")
			out.append({"kind": "swarm", "text": "Рой прорвался к %s. Наставники отбили его — дорогой ценой" % place_name(content, at)})
			for cid: String in MissionFlow.heroes(content, state):
				out.append_array(PsycheRules.change(content, state, cid, int(c.get("core_psyche", -15)), "рой у сердца кампуса", [], null, "mission", false))
			state.resources["shards"] = maxi(0, int(state.resources.get("shards", 0)) + int(c.get("core_shards", -4)))
			continue
		var mid := str(c.get("swarm", {}).get(at, ""))
		if _fresh(state, mid):
			keep.append(sw)   # пришёл сегодня — у отряда день, чтобы его встретить
			continue
		# отбитый рой сюда не доходит: команда clear снимает его сразу
		# не отбили: место повреждено или горит
		if site_state(state, at) != "barricaded":
			var burn := MapRules.states(content, state, at).has("burning") and rng.randf() < float(c.get("burn_chance", 0.35))
			set_site(state, at, "burning" if burn else "damaged")
			out.append({"kind": "damage", "text": "%s — %s" % [place_name(content, at), "горит" if burn else "повреждено"]})
			if burn:
				out.append_array(_open(content, state, str(c.get("fire", {}).get(at, ""))))
		var nxt := _next_step(content, state, at, str(c.get("target", "")))
		if nxt == "":
			out.append({"kind": "swarm", "text": "Рой рассеялся у %s" % place_name(content, at)})
			continue
		sw["from"] = at
		sw["at"] = nxt
		keep.append(sw)
		out.append({"kind": "swarm", "text": "Рой идёт дальше: %s" % place_name(content, nxt)})
		_swarm_arrive(content, state, nxt, out)
	state.flags["swarms"] = keep


## Шаг роя к цели по тропам: мимо забаррикадированных мест и воды.
static func _next_step(content: Content, state: RunState, from: String, target: String) -> String:
	if target == "" or from == target:
		return ""
	var r := TravelRules.route(content, state, from, target)
	if r.is_empty():
		return ""
	var nxt: String = r[0]
	return nxt if content.locations.has(nxt) else (r[1] if r.size() > 1 else "")


## Тревога прошла: тревожные места спокойны, баррикады разобраны, повреждённое — в ремонт.
static func _after_alarm(content: Content, state: RunState, rng: RandomNumberGenerator, out: Array) -> void:
	var c := cfg(content, state)
	var r: Array = c.get("repair", [2, 3])
	var s := sites(state).duplicate(true)
	var any := false
	for lid: String in s.keys():
		var st := str(s[lid].get("state", ""))
		if st in ["alarm", "fight", "barricaded", "lockdown", "crowded", "overcrowded"]:
			s.erase(lid)
			any = true
		elif st in ["damaged", "burning", "ruined", "breached"]:
			s[lid] = {"state": "repair", "left": rng.randi_range(int(r[0]), int(r[1])) + (1 if st == "burning" else 0)}
			out.append({"kind": "repair", "text": "%s — ремонт, %d дн." % [place_name(content, lid), int(s[lid]["left"])]})
			any = true
	state.flags["sites"] = s
	if any:
		out.append({"kind": "info", "text": str(c.get("calm_text", "Тревога снята"))})


## Новый сигнал: раз в every дней после first_after выполненных миссий главы, если сейчас угроз нет.
static func _maybe_signal(content: Content, state: RunState, rng: RandomNumberGenerator, out: Array) -> void:
	var c := cfg(content, state)
	if state.demo_complete or OnslaughtRules.done_in_chapter(content, state) < int(c.get("first_after", 2)):
		return
	if kind(content, state) == "gate":
		# в городе Врат может быть несколько сразу — но не больше max_gates
		var busy := 0
		for pid0: String in points(state):
			if str(points(state)[pid0].get("stage", "")) in ["signal", "open"]:
				busy += 1
		if busy >= int(c.get("max_gates", 3)):
			return
	else:
		if alarm(state):
			return
		for pid: String in points(state):
			if str(points(state)[pid].get("stage", "")) == "signal":
				return
	var every: Array = c.get("every", [3, 5])
	var nd := int(state.flags.get("gate_next", 0))
	if nd <= 0:
		nd = state.day + int(c.get("first_delay", 1))
		state.flags["gate_next"] = nd
	if state.day < nd:
		return
	var pick := choose_point(content, state, rng)
	if pick == "":
		return
	state.flags["gate_next"] = state.day + rng.randi_range(int(every[0]), int(every[1]))
	out.append_array(raise_signal(content, state, pick))


## Точка для сигнала: по весам, без занятых и уже бывших «раз за главу»; заложенные недавно — реже.
static func choose_point(content: Content, state: RunState, rng: RandomNumberGenerator) -> String:
	var pts: Dictionary = cfg(content, state).get("points", {})
	var once: Array = state.flags.get("gate_once", [])
	var total := 0.0
	var pool: Array = []
	for pid: String in MissionFlow._sorted(pts):
		if points(state).has(pid) or once.has(pid):
			continue
		var w := float(pts[pid].get("weight", 1.0))
		if int(pts[pid].get("after", 0)) > OnslaughtRules.done_in_chapter(content, state):
			continue
		if w <= 0.0:
			continue
		pool.append([pid, w])
		total += w
	if pool.is_empty():
		return ""
	var r := rng.randf() * total
	for e: Array in pool:
		r -= float(e[1])
		if r <= 0.0:
			return str(e[0])
	return str(pool.back()[0])


## Сигнал у точки: прорыв через signal_days дней; миссия сигнала (укрепить / засада).
static func raise_signal(content: Content, state: RunState, pid: String) -> Array:
	var d := point_def(content, state, pid)
	if d.is_empty():
		return []
	var p := points(state).duplicate(true)
	var c := cfg(content, state)
	var sd: Variant = c.get("signal_days", 1)
	var days := int(sd) if not (sd is Array) else int(sd[0]) + (state.day + pid.hash()) % (int(sd[1]) - int(sd[0]) + 1)
	p[pid] = {"stage": "signal", "open_day": state.day + days, "rank": _roll_rank(content, state, pid), "known": false}
	state.flags["gates"] = p
	if bool(d.get("once", false)):
		var once: Array = state.flags.get("gate_once", [])
		once.append(pid)
		state.flags["gate_once"] = once
	var site := str(d.get("site", ""))
	if site != "":
		set_site(state, site, str(d.get("site_states", {}).get("signal", "alarm")))
	var out: Array = [{"kind": _ev(content, state, "signal"), "text": "%s: %s" % [str(cfg(content, state).get("signal_text", "Сигнал")), str(d.get("name", place_name(content, str(d.get("near", "")))))]}]
	out.append_array(_open(content, state, str(d.get("signal", ""))))
	return out


# --- команда threat (миссии) -------------------------------------------------------------------

## {cmd: threat, do: seal|delay|clear|barricade|extinguish|repel, point?, place?}
static func command(content: Content, state: RunState, e: Dictionary) -> Array:
	var c := cfg(content, state)
	var pid := str(e.get("point", ""))
	var lid := str(e.get("place", ""))
	var p := points(state).duplicate(true)
	match str(e.get("do", "")):
		"seal":
			if not p.has(pid):
				return []
			p[pid] = {"stage": "sealed", "left": int(c.get("sealed_days", 3))}
			state.flags["gates"] = p
			var d := point_def(content, state, pid)
			var site := str(d.get("site", ""))
			if site != "":
				set_site(state, site, str(d.get("site_states", {}).get("sealed", "")))
			return [{"kind": "breach", "text": "%s закрыт: %s" % [str(c.get("open_text", "Прорыв")), str(d.get("name", pid))]}]
		"delay":
			if p.has(pid) and str(p[pid].get("stage", "")) == "signal":
				p[pid]["open_day"] = int(p[pid].get("open_day", state.day)) + 1
				state.flags["gates"] = p
				return [{"kind": "info", "text": "Участок укреплён — прорыв на день позже"}]
		"clear":
			var sw := swarms(state).filter(func(x: Dictionary) -> bool: return str(x.get("at", "")) != lid)
			state.flags["swarms"] = sw
			if site_state(state, lid) in ["fight", "alarm"]:
				set_site(state, lid, "alarm")
			return [{"kind": "swarm", "text": "Рой отбит: %s" % place_name(content, lid)}]
		"barricade":
			set_site(state, lid, "barricaded")
			var out: Array = [{"kind": "info", "text": "%s забаррикадировано — рой обходит" % place_name(content, lid)}]
			# рой у баррикады не задерживается: сразу шаг дальше
			var keep: Array = []
			for sw2: Dictionary in swarms(state):
				if str(sw2.get("at", "")) != lid:
					keep.append(sw2)
					continue
				var nxt := _next_step(content, state, lid, str(c.get("target", "")))
				if nxt != "":
					sw2["from"] = lid
					sw2["at"] = nxt
					keep.append(sw2)
			state.flags["swarms"] = keep
			for sw3: Dictionary in keep:
				if str(sw3.get("from", "")) == lid:
					_swarm_arrive(content, state, str(sw3["at"]), out)
			return out
		"extinguish":
			if site_state(state, lid) == "burning":
				set_site(state, lid, "damaged")
				return [{"kind": "info", "text": "%s — пожар потушен" % place_name(content, lid)}]
		"repel":
			var target := str(c.get("target", ""))
			state.flags["swarms"] = swarms(state).filter(func(x: Dictionary) -> bool: return str(x.get("at", "")) != target)
			set_site(state, target, "alarm")
			return [{"kind": "swarm", "text": "Рой отбит у %s" % place_name(content, target)}]
		# --- Врата города ---
		"scout":
			if p.has(pid):
				p[pid]["known"] = true
				state.flags["gates"] = p
				return [{"kind": "info", "text": "Разведка: %s — ранг %d" % [str(point_def(content, state, pid).get("name", pid)), int(p[pid].get("rank", 1))]}]
		"evacuate":
			var ev: Dictionary = Dictionary(state.flags.get("evac", {})).duplicate()
			ev[lid] = state.day + int(c.get("evac_days", 5))
			state.flags["evac"] = ev
			add_panic(content, state, -3)
			return [{"kind": "info", "text": "%s эвакуирован — волна пройдёт мимо людей" % place_name(content, lid)}]
		"close":
			if not p.has(pid):
				return []
			p[pid] = {"stage": "scar", "left": int(c.get("scar_days", 7)), "closed_day": state.day}
			state.flags["gates"] = p
			add_panic(content, state, int(c.get("panic", {}).get("closed", -15)))
			state.flags["gates_closed"] = int(state.flags.get("gates_closed", 0)) + 1
			var res: Array = [{"kind": "gate_close", "text": "Врата закрыты: %s — остался шрам" % str(point_def(content, state, pid).get("name", pid))}]
			res.append_array(_unlock_by_gates(content, state))
			return res
		"hold", "ambush":
			if p.has(pid):
				p[pid]["held"] = int(p[pid].get("open_day", state.day)) if str(e.get("do", "")) == "ambush" else state.day + 1
				if str(e.get("do", "")) == "ambush":
					p[pid]["rank"] = maxi(1, int(p[pid].get("rank", 1)) - 1)
				state.flags["gates"] = p
				return [{"kind": "info", "text": "Волна из Врат этой ночью не выйдет" if str(e.get("do", "")) == "hold" else "Засада готова: первая волна не выйдет, Врата слабее"}]
		"blow":
			set_site(state, lid, "collapsed", int(c.get("bridge_days", 7)))
			state.flags["swarms"] = swarms(state).filter(func(x: Dictionary) -> bool: return str(x.get("at", "")) != lid)
			return [{"kind": "damage", "text": "%s взорван: волна не пройдёт, район отрезан на неделю" % place_name(content, lid)}]
		"raise":
			# сюжет: Врата здесь и сейчас (предвестие или сразу открыты)
			var out2 := raise_signal(content, state, pid)
			var p2 := points(state).duplicate(true)
			if p2.has(pid):
				if e.has("rank"):
					p2[pid]["rank"] = int(e["rank"])
				if bool(e.get("open", false)):
					p2[pid]["open_day"] = state.day
				state.flags["gates"] = p2
				if bool(e.get("open", false)):
					p2[pid]["stage"] = "open"
					state.flags["gates"] = p2
					out2.append_array(_city_open(content, state, pid))
			return out2
		"calm":
			add_panic(content, state, -int(e.get("value", 10)))
			return [{"kind": "info", "text": "Город немного успокоился"}]
	return []


## Сюжет, привязанный к Вратам: миссии главы с unlock.gates_closed открываются, когда закрыто столько Врат.
static func _unlock_by_gates(content: Content, state: RunState) -> Array:
	var out: Array = []
	var n := int(state.flags.get("gates_closed", 0))
	for mid: String in MissionFlow._sorted(content.missions):
		var need := int(content.missions[mid].get("unlock", {}).get("gates_closed", 0))
		if need <= 0 or need > n or state.missions.has(mid) or MissionFlow.chapter_of(content, mid) != state.chapter:
			continue
		var after: Array = content.missions[mid].get("unlock", {}).get("after_all", [])
		if after.any(func(x: String) -> bool: return str(state.missions.get(x, {}).get("status", "")) != "done"):
			continue
		out.append_array(MissionFlow.open(content, state, mid, true))
	return out


## Имя события для окна ночи и обучения: у Академии и Города свои слова.
static func _ev(content: Content, state: RunState, what: String) -> String:
	return str(cfg(content, state).get("events", {}).get(what, {"signal": "breach_signal", "open": "breach", "swarm": "swarm"}.get(what, what)))


## Ранг Врат при предвестии: веса ranks, ранг 3 — только в Тревогу или при сильной панике.
static func _roll_rank(content: Content, state: RunState, pid: String) -> int:
	var c := cfg(content, state)
	if kind(content, state) != "gate":
		return 1
	var w: Dictionary = c.get("ranks", {"1": 5, "2": 3, "3": 1})
	var bias := int(point_def(content, state, pid).get("rank_bias", 0))
	var pool: Array = []
	for r: String in w:
		if r == "3" and not big_alarm(content, state) and panic(state) < 50:
			continue
		for i in int(w[r]):
			pool.append(int(r))
	if pool.is_empty():
		return 1
	var rng := RandomNumberGenerator.new()
	rng.seed = state.rng_seed + 9973 * state.day + pid.hash()
	return clampi(int(pool[rng.randi_range(0, pool.size() - 1)]) + bias, 1, 3)


# --- Город: ночь ---------------------------------------------------------------------------------

static func _night_city(content: Content, state: RunState, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var c := cfg(content, state)
	var ph := str(DayRules.phase(content, state).get("id", ""))
	_city_sites(content, state, out)
	_city_points(content, state, rng, out, ph)
	if Array(c.get("move_phases", ["dusk", "night"])).has(ph):
		_city_waves(content, state, rng, out)
	_city_repair(content, state, rng, out)
	_city_alarm_states(content, state)
	if open_count(state) == 0:
		add_panic(content, state, int(c.get("panic", {}).get("calm", -3)))
	_maybe_signal(content, state, rng, out)
	return out


## Счётчики мест: ремонт, обрушенный мост (потом временный понтон).
static func _city_sites(content: Content, state: RunState, out: Array) -> void:
	var s := sites(state).duplicate(true)
	for lid: String in s.keys():
		var e: Dictionary = s[lid]
		var st := str(e.get("state", ""))
		if st in ["repair", "collapsed", "temporary"]:
			e["left"] = int(e.get("left", 1)) - 1
			if int(e["left"]) > 0:
				continue
			match st:
				"repair", "temporary":
					s.erase(lid)
					out.append({"kind": "repair", "text": "%s — восстановлено" % place_name(content, lid)})
				"collapsed":
					s[lid] = {"state": "temporary", "left": 3}
					out.append({"kind": "repair", "text": "%s — навели временный понтон" % place_name(content, lid)})
	state.flags["sites"] = s


## Точки: предвестие → открытие (только в фазы open_phases), шрам выцветает, на шраме бывают встречи.
static func _city_points(content: Content, state: RunState, rng: RandomNumberGenerator, out: Array, ph: String) -> void:
	var c := cfg(content, state)
	var p := points(state).duplicate(true)
	for pid: String in MissionFlow._sorted(p):
		var e: Dictionary = p[pid]
		var d := point_def(content, state, pid)
		match str(e.get("stage", "")):
			"signal":
				var phases: Array = c.get("open_phases", ["night"])
				if state.day >= int(e.get("open_day", state.day)) and (phases.is_empty() or phases.has(ph)):
					e["stage"] = "open"
					e["open_day"] = state.day
					p[pid] = e
					state.flags["gates"] = p
					out.append_array(_city_open(content, state, pid))
					p = points(state).duplicate(true)
			"scar":
				e["left"] = int(e.get("left", 1)) - 1
				if int(e["left"]) <= 0:
					p.erase(pid)
				else:
					p[pid] = e
					if d.has("scar") and rng.randf() < float(c.get("scar_chance", 0.3)) and _status(state, str(d["scar"])) != "open":
						out.append_array(_open(content, state, str(d["scar"])))
	state.flags["gates"] = p


## Врата открылись: миссия Врат с рангом, квартал рядом в тревоге, паника.
static func _city_open(content: Content, state: RunState, pid: String) -> Array:
	var out: Array = []
	var c := cfg(content, state)
	var d := point_def(content, state, pid)
	var near := str(d.get("near", ""))
	if site_state(state, near) in ["", "repair"]:
		set_site(state, near, "alarm")
	add_panic(content, state, int(c.get("panic", {}).get("open", 10)))
	var rank := int(points(state).get(pid, {}).get("rank", 1))
	out.append({"kind": _ev(content, state, "open"), "text": "Открылись Врата Кошмара: %s (ранг %d)" % [str(d.get("name", pid)), rank]})
	var mid := str(d.get("open", ""))
	out.append_array(_open(content, state, mid))
	if state.missions.has(mid):
		var mods: Array = Array(state.missions[mid].get("mods", [])).filter(func(x: String) -> bool: return not x.begins_with("gate_rank"))
		if rank >= 2:
			mods.append("gate_rank%d" % rank)
		state.missions[mid]["mods"] = mods
	return out


## Волны: из открытых Врат — новая (одна на Врата), стоящие — эскалация квартала и шаг дальше.
static func _city_waves(content: Content, state: RunState, rng: RandomNumberGenerator, out: Array) -> void:
	var c := cfg(content, state)
	var keep: Array = []
	for w: Dictionary in swarms(state):
		var at := str(w.get("at", ""))
		var mid := str(c.get("swarm", {}).get(at, ""))
		if _fresh(state, mid) and not bool(w.get("passing", false)):
			keep.append(w)   # пришла сегодня — день, чтобы её встретить
			continue
		var nights := int(w.get("nights", 0)) + 1
		w["nights"] = nights
		var move := bool(w.get("passing", false))
		if not move:
			var st := "damaged" if nights == 1 else "ruined"
			if site_state(state, at) == "ruined":
				st = "ruined"
			if st == "ruined" and Array(c.get("sturdy", [])).has(at):
				st = "damaged"   # укрепления (убежище, госпиталь, власть) не рушатся — в городе всегда есть где переждать ночь
			set_site(state, at, st)
			add_panic(content, state, int(c.get("panic", {}).get(st, 5 if st == "damaged" else 15)))
			out.append({"kind": "damage", "text": "%s — %s" % [place_name(content, at), "повреждён" if st == "damaged" else "разрушен"]})
			move = st == "ruined" or (nights >= 2 and Array(c.get("sturdy", [])).has(at))
			if not move:
				out.append_array(_open(content, state, mid))   # ещё день, чтобы спасти квартал
				state.missions[mid]["opened_day"] = state.day
				keep.append(w)
				continue
		var nxt := _wave_target(content, state, at, Array(w.get("path", [at])))
		if nxt == "":
			out.append({"kind": "wave", "text": "Волна рассеялась у %s" % place_name(content, at)})
			continue
		w["from"] = at
		w["at"] = nxt
		w["nights"] = 0
		w["passing"] = false
		var path: Array = Array(w.get("path", [at]))
		path.append(nxt)
		w["path"] = path
		keep.append(w)
		out.append({"kind": _ev(content, state, "swarm"), "text": "Волна идёт дальше: %s" % place_name(content, nxt)})
		_wave_arrive(content, state, w, out)
	state.flags["swarms"] = keep
	# новые волны из открытых Врат
	var p := points(state)
	for pid: String in MissionFlow._sorted(p):
		if str(p[pid].get("stage", "")) != "open":
			continue
		if int(p[pid].get("held", -1)) >= state.day - 1 and int(p[pid].get("held", -1)) <= state.day:
			continue   # засада или сдержали волну
		if swarms(state).any(func(x: Dictionary) -> bool: return str(x.get("point", "")) == pid):
			continue
		var near := str(point_def(content, state, pid).get("near", ""))
		if not content.locations.has(near):
			continue
		var w2 := {"at": near, "from": "", "point": pid, "nights": 0, "path": [near]}
		var sw := swarms(state).duplicate(true)
		sw.append(w2)
		state.flags["swarms"] = sw
		out.append({"kind": _ev(content, state, "swarm"), "text": "Из Врат вышла волна: %s" % place_name(content, near)})
		_wave_arrive(content, state, w2, out)
		# _wave_arrive мог поменять волну (эвакуированный квартал) — сохранить
		var sw2 := swarms(state).duplicate(true)
		sw2[sw2.size() - 1] = w2
		state.flags["swarms"] = sw2


## Волна пришла в квартал: бой (миссия на день) или, если людей увели, — проходит мимо, задев квартал.
static func _wave_arrive(content: Content, state: RunState, w: Dictionary, out: Array) -> void:
	var c := cfg(content, state)
	var at := str(w.get("at", ""))
	if evacuated(state, at):
		w["passing"] = true
		if site_state(state, at) != "ruined":
			set_site(state, at, "damaged")
		out.append({"kind": "damage", "text": "%s эвакуирован — волна идёт мимо, но квартал задет" % place_name(content, at)})
		return
	set_site(state, at, "fight" if not MapRules.states(content, state, at).is_empty() else "alarm")
	out.append_array(_open(content, state, str(c.get("swarm", {}).get(at, ""))))


## Куда идёт волна: соседний квартал, где больше людей (эвакуированный — почти пуст), ближе к центру; не назад.
static func _wave_target(content: Content, state: RunState, at: String, path: Array) -> String:
	var c := cfg(content, state)
	var people: Dictionary = c.get("people", {})
	var center_at := MapRules.anchor(content, state, str(c.get("center", at)))
	var best := ""
	var bs := -1.0
	for n: String in TravelRules.adjacency(content, state).get(at, []):
		if not content.locations.has(n) or path.has(n) or blocked(state, n) or site_state(state, n) == "ruined":
			continue
		var sc := float(people.get(n, 1)) * (0.2 if evacuated(state, n) else 1.0)
		sc += 0.5 / (1.0 + 10.0 * MapRules.anchor(content, state, n).distance_to(center_at))
		if sc > bs or (is_equal_approx(sc, bs) and n < best):
			bs = sc
			best = n
	return best


## Ремонт: квартал без волны и без открытых Врат рядом чинится (3–5 дней), тревога снимается.
static func _city_repair(content: Content, state: RunState, rng: RandomNumberGenerator, out: Array) -> void:
	var c := cfg(content, state)
	var r: Array = c.get("repair", [3, 5])
	var hot := {}
	for w: Dictionary in swarms(state):
		hot[str(w.get("at", ""))] = true
	var adj := TravelRules.adjacency(content, state)
	for pid: String in points(state):
		var st := str(points(state)[pid].get("stage", ""))
		if st in ["open", "signal"]:
			var near := str(point_def(content, state, pid).get("near", ""))
			hot[near] = true
			if st == "open":
				for n: String in adj.get(near, []):
					hot[n] = true
	var s := sites(state).duplicate(true)
	for lid: String in s.keys():
		var st2 := str(s[lid].get("state", ""))
		if hot.has(lid):
			continue
		if st2 in ["alarm", "fight"]:
			s.erase(lid)
		elif st2 in ["damaged", "ruined"]:
			s[lid] = {"state": "repair", "left": rng.randi_range(int(r[0]), int(r[1])) + (2 if st2 == "ruined" else 0)}
			out.append({"kind": "repair", "text": "%s — восстановление, %d дн." % [place_name(content, lid), int(s[lid]["left"])]})
	state.flags["sites"] = s


## Тревога города: укрытия и госпиталь переполнены, подземка и вокзал закрыты; без Тревоги — как обычно.
static func _city_alarm_states(content: Content, state: RunState) -> void:
	var al: Dictionary = cfg(content, state).get("alarm_states", {})
	var on := big_alarm(content, state)
	for lid: String in al:
		var st := site_state(state, lid)
		if on and st == "":
			set_site(state, lid, str(al[lid]))
		elif not on and st == str(al[lid]):
			set_site(state, lid, "")


## Начало главы: угроз нет.
static func reset(state: RunState) -> void:
	for k: String in ["gates", "sites", "swarms", "gate_next", "gate_once", "panic", "evac", "gates_closed"]:
		state.flags.erase(k)


## Строка для карты: что сейчас с угрозами ("" — тихо).
static func banner(content: Content, state: RunState) -> String:
	if kind(content, state) == "gate":
		return _banner_city(content, state)
	var parts: Array = []
	for pid: String in MissionFlow._sorted(points(state)):
		var d := point_def(content, state, pid)
		var nm := str(d.get("name", pid))
		match str(points(state)[pid].get("stage", "")):
			"signal":
				var left := int(points(state)[pid].get("open_day", state.day)) - state.day
				parts.append("⚠ %s: %s — прорыв %s" % [str(cfg(content, state).get("signal_text", "Сигнал")), nm, "этой ночью" if left <= 0 else "через %d дн." % left])
			"open":
				parts.append("⚠ %s: %s" % [str(cfg(content, state).get("open_text", "Прорыв")), nm])
	for sw: Dictionary in swarms(state):
		parts.append("⚠ Рой: %s" % place_name(content, str(sw.get("at", ""))))
	return "  ·  ".join(parts)


static func _banner_city(content: Content, state: RunState) -> String:
	var parts: Array = []
	for pid: String in MissionFlow._sorted(points(state)):
		var e: Dictionary = points(state)[pid]
		var nm := str(point_def(content, state, pid).get("name", pid))
		var rk := ("ранг %d" % int(e.get("rank", 1))) if bool(e.get("known", false)) or str(e.get("stage", "")) == "open" else "ранг ?"
		match str(e.get("stage", "")):
			"signal":
				parts.append("⚠ Предвестие: %s (%s)" % [nm, rk])
			"open":
				parts.append("⚠ Врата: %s (%s)" % [nm, rk])
	for w: Dictionary in swarms(state):
		parts.append("⚠ Волна: %s" % place_name(content, str(w.get("at", ""))))
	if panic(state) > 0:
		parts.append("Паника %d%s" % [panic(state), " · ТРЕВОГА" if big_alarm(content, state) else ""])
	return "  ·  ".join(parts)
