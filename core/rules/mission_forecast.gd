class_name MissionForecast
extends RefCounted
## Прогноз миссии словами (docs/15 §5). Считается теми же функциями, что и настоящий исход
## (MissionResolver): шанс этапа-проверки, шанс боя, правило сложения этапов.

const WORDS := [[15, "Безнадёжно"], [35, "Очень опасно"], [50, "Опасно"], [65, "Неясно"], [85, "Хорошие шансы"], [101, "Уверенно"]]
const RISK_WORDS := [[0.2, "без потерь"], [0.5, "могут быть раны"], [1.01, "кто-то может не вернуться"]]
const CHANCE_MIN := 5
const CHANCE_MAX := 95
const PARTIAL_BAND := 25     # бросок чуть выше шанса — частичный успех этапа
const PARTIAL_TRAUMA := 50   # % травмы при частичном успехе этапа
const BLUR := 12             # насколько размывается прогноз при скрытых тегах


static func word(value: int) -> String:
	for w: Array in WORDS:
		if value < int(w[0]):
			return str(w[1])
	return str(WORDS[-1][1])


static func risk_word(risk: float) -> String:
	for w: Array in RISK_WORDS:
		if risk < float(w[0]):
			return str(w[1])
	return str(RISK_WORDS[-1][1])


## Итог действия по исходам этапов: "success" | "partial" | "failure".
## Успех — без провалов и в основном «ok»; частичный — провалов не больше трети этапов;
## иначе провал (в миссии из 1–2 этапов любой проваленный этап — провал миссии).
static func combine(outcomes: Array) -> String:
	var n := outcomes.size()
	if n == 0:
		return "success"
	var pts := 0
	var fails := 0
	for o: String in outcomes:
		pts += {"ok": 2, "partial": 1}.get(o, 0)
		if o == "fail":
			fails += 1
	if fails == 0 and pts >= int(ceil(1.5 * n)):
		return "success"
	if pts >= n and fails * 3 <= n:
		return "partial"
	return "failure"


static func ctx_event(m: Dictionary) -> Dictionary:
	return {"id": str(m.get("id", "")), "tags": m.get("context", [])}


static func ctx_option(a: Dictionary, st: Dictionary) -> Dictionary:
	return {"id": str(a.get("id", "")), "tags": st.get("tags", [])}


## Лучший исполнитель этапа-проверки: {hero, chance, temp_used}.
static func stage_actor(content: Content, state: RunState, m: Dictionary, a: Dictionary, st: Dictionary, heroes: Array) -> Dictionary:
	var best := {"hero": "", "chance": -1, "temp_used": []}
	for cid: String in heroes:
		if not state.is_alive(cid):
			continue
		var r := StatResolver.resolve(content, state, cid, MissionFlow.pocket(state, cid), ctx_event(m), ctx_option(a, st))
		var totals: Dictionary = r["totals"].duplicate()
		# связки отряда и паника (docs/16 §6–7)
		var tags: Array = Array(m.get("context", [])) + Array(st.get("tags", []))
		for p: Dictionary in BondRules.check_parts(content, state, heroes, cid, tags):
			totals[p["stat"]] = int(totals.get(p["stat"], 0)) + int(p["value"])
		for p2: Dictionary in PsycheRules.check_parts(content, state, cid, totals):
			totals[p2["stat"]] = int(totals.get(p2["stat"], 0)) + int(p2["value"])
		var c := clampi(ChanceCalculator.compute(totals, st.get("req", {})), CHANCE_MIN, CHANCE_MAX)
		if c > int(best["chance"]):
			best = {"hero": cid, "chance": c, "temp_used": r["temp_used"]}
	return best


## Бой этапа: ведущий — герой с лучшим шансом первого раунда, остальные в поддержке.
## reveal = false — скрытые теги врага не учитываются (игрок о них не знает).
static func combat_setup(content: Content, state: RunState, m: Dictionary, a: Dictionary, st: Dictionary,
		heroes: Array, reveal: bool) -> Dictionary:
	var best := {"hero": "", "round": -1, "fight": 0.0, "links": []}
	for cid: String in heroes:
		if not state.is_alive(cid):
			continue
		var support: Array = heroes.filter(func(x: String) -> bool: return x != cid)
		var s := CombatSession.create_for_mission(content, state, str(m.get("id", "")), st.get("combat", {}), cid,
			MissionFlow.pocket(state, cid), support, ctx_event(m), ctx_option(a, st))
		if not reveal:
			s.hidden_enemy_tags = Array(m.get("hidden_tags", [])).duplicate()
		s.round_no = 1
		var led := s.ledger(MemoryRules.fire(s, "round", false)["effect"])
		if int(led["chance"]) > int(best["round"]):
			best = {"hero": cid, "round": int(led["chance"]), "fight": CombatSession.fight_chance(int(led["chance"])), "links": led["links"]}
	return best


## Вероятности исходов одного этапа: {ok, partial, fail, hero, kind, links}.
static func stage_odds(content: Content, state: RunState, m: Dictionary, a: Dictionary, st: Dictionary,
		heroes: Array, reveal: bool) -> Dictionary:
	if bool(st.get("auto", false)):
		return {"ok": 1.0, "partial": 0.0, "fail": 0.0, "hero": "", "kind": "auto", "links": [], "risk": 0.0}
	if st.has("combat"):
		var c := combat_setup(content, state, m, a, MissionFlow.boss_stage(state, m, st), heroes, reveal)
		var f := float(c["fight"])
		# в бою травмы бывают и при победе (проигранный раунд) — риск чуть выше вероятности поражения
		return {"ok": f, "partial": 0.0, "fail": 1.0 - f, "hero": c["hero"], "kind": "combat", "links": c["links"],
			"round": c["round"], "risk": clampf(1.0 - f * f, 0.0, 1.0)}
	var actor := stage_actor(content, state, m, a, st, heroes)
	var ok := float(actor["chance"]) / 100.0
	var part := minf(float(PARTIAL_BAND), 100.0 - float(actor["chance"])) / 100.0
	var fail := maxf(0.0, 1.0 - ok - part)
	return {"ok": ok, "partial": part, "fail": fail, "hero": actor["hero"], "kind": "check", "chance": actor["chance"],
		"links": [], "risk": fail + part * PARTIAL_TRAUMA / 100.0}


## Прогноз одного действия: вероятности итогов, слово, риск, этапы и сработавшие связи тегов.
static func action_forecast(content: Content, state: RunState, mission_id: String, a: Dictionary,
		heroes: Array, reveal: bool) -> Dictionary:
	var m: Dictionary = content.missions.get(mission_id, {})
	if bool(a.get("retreat", false)):
		return {"value": 100, "word": "Без риска", "risk": 0.0, "risk_word": "без потерь", "success": 0.0,
			"partial": 0.0, "failure": 1.0, "stages": [], "links": []}
	var stages: Array = []
	var links: Array = []
	for st: Dictionary in a.get("stages", []):
		var od := stage_odds(content, state, m, a, st, heroes, reveal)
		od["name"] = st.get("name", "")
		stages.append(od)
		for l: Dictionary in od["links"]:
			links.append(l)
	# перебор всех сочетаний исходов этапов (не больше 3^3)
	var dist := {"success": 0.0, "partial": 0.0, "failure": 0.0}
	_enumerate(stages, 0, [], 1.0, dist)
	var value := int(round(100.0 * (float(dist["success"]) + 0.5 * float(dist["partial"]))))
	var safe := 1.0
	for od: Dictionary in stages:
		safe *= 1.0 - float(od["risk"])
	var risk := 1.0 - safe
	return {"value": value, "word": word(value), "risk": risk, "risk_word": risk_word(risk),
		"success": dist["success"], "partial": dist["partial"], "failure": dist["failure"], "stages": stages, "links": links}


static func _enumerate(stages: Array, i: int, acc: Array, p: float, dist: Dictionary) -> void:
	if p <= 0.0:
		return
	if i >= stages.size():
		var r := combine(acc)
		dist[r] = float(dist[r]) + p
		return
	for o: String in ["ok", "partial", "fail"]:
		var q := float(stages[i][o])
		if q > 0.0:
			_enumerate(stages, i + 1, acc + [o], p * q, dist)


## Прогноз до отправки отряда: по лучшему из доступных отряду действий.
## Если есть скрытые теги и в отряде нет разведчика — прогноз размыт диапазоном слов.
static func mission_forecast(content: Content, state: RunState, mission_id: String, heroes: Array) -> Dictionary:
	var m: Dictionary = content.missions.get(mission_id, {})
	if heroes.is_empty():
		return {"word": "", "word_low": "", "value": 0, "risk_word": "", "blurred": false, "action": "", "links": []}
	var reveal := Array(m.get("hidden_tags", [])).is_empty() or MissionFlow.has_scout(content, state, heroes)
	var best: Dictionary = {}
	var best_id := ""
	for entry: Dictionary in MissionFlow.actions_for(content, state, mission_id, heroes):
		var a: Dictionary = entry["action"]
		if not entry["available"] or bool(a.get("retreat", false)):
			continue
		var f := action_forecast(content, state, mission_id, a, heroes, reveal)
		if best.is_empty() or int(f["value"]) > int(best["value"]):
			best = f
			best_id = str(a.get("id", ""))
	if best.is_empty():
		return {"word": "", "word_low": "", "value": 0, "risk_word": "", "blurred": false, "action": "", "links": []}
	var low := word(maxi(0, int(best["value"]) - BLUR)) if not reveal else str(best["word"])
	return {"word": best["word"], "word_low": low, "value": best["value"], "risk_word": best["risk_word"],
		"blurred": not reveal and low != str(best["word"]), "action": best_id, "links": best["links"], "stages": best["stages"]}
