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
## Состояние: state.flags — gates {точка: {stage, open_day, left}}, sites {место: {state, left}},
## swarms [{at, from, point}], gate_next (день следующего сигнала), gate_once [точки «раз за главу»].

const STAGES := ["signal", "open", "sealed"]
## облик места → запасной, если такой картинки у места нет
const FALLBACK := {"fight": "alarm", "burning": "damaged", "ruined": "damaged", "crowded": "alarm", "lockdown": "alarm",
	"overcrowded": "alarm", "leak": "alarm", "breached": "damaged", "sealed": "repair"}


static func cfg(content: Content, state: RunState) -> Dictionary:
	return Dictionary(MapRules.config(content, state.chapter).get("threat", {}))


static func active(content: Content, state: RunState) -> bool:
	return not cfg(content, state).is_empty()


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
	var fb := str(FALLBACK.get(st, ""))
	return fb if have.has(fb) else ""


## Место нельзя пройти: забаррикадировано до конца тревоги.
static func blocked(state: RunState, lid: String) -> bool:
	return site_state(state, lid) == "barricaded"


## Лагерь в месте с угрозой: отдых хуже, койки меньше, службы закрыты (кроме лечения).
static func camp_mod(content: Content, state: RunState, lid: String, camp: Dictionary) -> Dictionary:
	if not active(content, state):
		return camp
	var st := site_state(state, lid)
	var d := camp.duplicate(true)
	var keep := ["heal"]
	match st:
		"alarm", "fight", "crowded", "lockdown", "leak", "overcrowded":
			d["rest"] = int(d.get("rest", 20)) + int(cfg(content, state).get("alarm_rest", -10))
			d["services"] = Array(d.get("services", [])).filter(func(x: String) -> bool: return keep.has(x))
			if st in ["crowded", "overcrowded"]:
				d["beds"] = 0
		"damaged", "repair", "breached", "sealed":
			d["rest"] = int(d.get("rest", 20)) - 5
			d["beds"] = maxi(0, int(d.get("beds", 0)) - 1)
		"burning", "ruined":
			d["rest"] = 0
			d["beds"] = 0
			d["services"] = []
			d["danger"] = float(d.get("danger", 0.0)) + 0.2
	if alarm(state):
		d["danger"] = float(d.get("danger", 0.0)) * 1.5
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
	if state.demo_complete or alarm(state) or OnslaughtRules.done_in_chapter(content, state) < int(c.get("first_after", 2)):
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
	p[pid] = {"stage": "signal", "open_day": state.day + int(cfg(content, state).get("signal_days", 1))}
	state.flags["gates"] = p
	if bool(d.get("once", false)):
		var once: Array = state.flags.get("gate_once", [])
		once.append(pid)
		state.flags["gate_once"] = once
	var site := str(d.get("site", ""))
	if site != "":
		set_site(state, site, str(d.get("site_states", {}).get("signal", "alarm")))
	var out: Array = [{"kind": "breach_signal", "text": "%s: %s" % [str(cfg(content, state).get("signal_text", "Сигнал")), str(d.get("name", place_name(content, str(d.get("near", "")))))]}]
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
	return []


## Начало главы: угроз нет.
static func reset(state: RunState) -> void:
	for k: String in ["gates", "sites", "swarms", "gate_next", "gate_once"]:
		state.flags.erase(k)


## Строка для карты: что сейчас с угрозами ("" — тихо).
static func banner(content: Content, state: RunState) -> String:
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
