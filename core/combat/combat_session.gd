class_name CombatSession
extends RefCounted
## Бой «Столкновение» (docs/12). Без HP: силы сторон сравниваются, раунд решает бросок
## по доле сил (5–95%). Всё считается пошагово в «летописи силы», чтобы игрок видел каждую цифру.
## Работает на копии состояния; итог применяется через finish() так же транзакционно, как обычный ход.

const RANK_STEP := 1.6
const CLASS_MULT := [1.0, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5]
const TAG_CAP_UP := 1.0
const TAG_CAP_DOWN := -0.6
const SYN_CAP := 0.8
const CON_CAP := 0.6
const ENV_CAP := 0.4
const CHANCE_MIN := 5
const CHANCE_MAX := 95
const MOMENTUM := 0.10
const WOUND := 0.10
const TRAUMA_PENALTY := 0.05
const STAT_STEP := 0.04
const STAT_ROTATION := ["power", "will", "cunning"]
const WINS_NEEDED := 2
const HAND_SIZE := 3

var content: Content
var state: RunState
var rng: RandomNumberGenerator
var event_id := ""
var option_id := ""
var hero := ""
var enh: Array = []
var allies: Array = []
var enemies: Array = []           # копии описаний противников
var field: Dictionary = {}
var kind := "normal"
var mods: Dictionary = {}
var ward := false

var round_no := 0
var hero_wins := 0
var enemy_wins := 0
var momentum := ""                # "hero" | "enemy" | ""
var round_card: Dictionary = {}
## Намерение врага на этот раунд (видно игроку до выбора приёма)
var intent: Dictionary = {}
var intent_notes: Array = []
var pending_enemy_bonus := 0.0
var carry_enemy_bonus := 0.0
var next_round_card: Dictionary = {}
var used_round_cards: Array = []
var hand: Array = []              # id приёмов
var hero_extra_tags: Array = []   # «Боль» и т.п. до конца боя
var session_wounds := 0
var finished := false
var outcome := ""                 # win | loss | retreat | death
var rounds_log: Array = []
var entries: Array = []
var discovered: Array = []        # id связей, сработавших в сыгранных раундах
var result: Dictionary = {"traumas": [], "death": {}, "wear": [], "loot": {}, "progressed": false}


static func create(p_content: Content, state_in: RunState, p_event_id: String, p_option_id: String,
		draft: Dictionary, support: Array = [], p_ward: bool = false) -> CombatSession:
	var s := CombatSession.new()
	s.content = p_content
	s.state = state_in.copy()
	s.rng = RandomNumberGenerator.new()
	s.rng.seed = s.state.rng_seed
	s.rng.state = s.state.rng_state
	s.event_id = p_event_id
	s.option_id = p_option_id
	s.hero = str(draft.get("character", ""))
	s.enh = Array(draft.get("enhancements", [])).duplicate()
	s.ward = p_ward
	var o := p_content.option(p_event_id, p_option_id)
	var spec: Dictionary = o.get("combat", {})
	s.mods = s.state.combat_mods.get(p_event_id, {})
	for eid: String in Array(spec.get("enemies", [])) + Array(s.mods.get("add_enemies", [])):
		if p_content.enemies.has(eid):
			s.enemies.append(p_content.enemies[eid].duplicate(true))
	var fid: String = s.mods.get("field", spec.get("field", ""))
	s.field = p_content.fields.get(fid, {"id": "", "name": "Без особенностей", "tags": ["суша"], "effects": []})
	s.kind = str(spec.get("kind", "normal"))
	for e: Dictionary in s.enemies:
		if e.get("kind", "normal") == "boss" or (e.get("kind", "") == "elite" and s.kind == "normal"):
			s.kind = str(e["kind"])
	for a: String in Array(s.mods.get("allies", [])) + support:
		if a != s.hero and s.state.owns(a) and s.state.is_alive(a) and not s.allies.has(a) and s.allies.size() < 2:
			s.allies.append(a)
	return s


func rounds_total_label() -> String:
	return "до 2 побед из 3" if kind != "normal" else "2 раунда (при 1:1 — раунд истощения)"


# --- раунды -------------------------------------------------------------------------

func begin_round() -> void:
	round_no += 1
	if round_no == 3 and kind == "normal":
		round_card = {"id": "EXHAUST", "name": "Раунд истощения", "tags": [], "stat": "will",
			"effects": [{"tag": "*both", "value": -0.2}], "text": "Обе стороны выдохлись: −20% всем."}
	elif not next_round_card.is_empty():
		round_card = next_round_card
	else:
		round_card = _draw_round_card()
	next_round_card = {}
	if round_card.get("special", "") == "add_enemy" and not enemies.is_empty():
		var weakest: Dictionary = enemies[0].duplicate(true)
		for e: Dictionary in enemies:
			if _enemy_base(e) < _enemy_base(weakest):
				weakest = e.duplicate(true)
		weakest["name"] = str(weakest["name"]) + " (подкрепление)"
		enemies.append(weakest)
	carry_enemy_bonus = pending_enemy_bonus
	pending_enemy_bonus = 0.0
	_choose_intent()
	hand = _draw_hand()


## Враг выбирает способность по своим тегам (взвешенно). Эффекты начала раунда применяются сразу.
func _choose_intent() -> void:
	intent_notes.clear()
	var et := _enemy_tags({})
	var pool: Array = []
	var total := 0
	var ids: Array = content.enemy_abilities.keys()
	ids.sort()
	for id: String in ids:
		var a: Dictionary = content.enemy_abilities[id]
		var need: Array = a.get("when_tags", [])
		var ok := need.is_empty()
		for t: String in need:
			if et.has(t):
				ok = true
		if ok:
			pool.append(a)
			total += int(a.get("weight", 1))
	intent = {}
	if pool.is_empty():
		return
	var r := rng.randi_range(1, total)
	for a: Dictionary in pool:
		r -= int(a.get("weight", 1))
		if r <= 0:
			intent = a.duplicate(true)
			break
	var neg := _intent_negator(_hero_tags({}), _env_tags(), {})
	if neg != "":
		return
	if bool(intent.get("summon", false)) and not enemies.is_empty():
		var weakest: Dictionary = enemies[0].duplicate(true)
		for e: Dictionary in enemies:
			if _enemy_base(e) < _enemy_base(weakest):
				weakest = e.duplicate(true)
		weakest["name"] = str(weakest["name"]).trim_suffix(" (подкрепление)") + " (поднят)"
		enemies.append(weakest)
		intent_notes.append("К бою присоединяется %s" % weakest["name"])
	if int(intent.get("heal_wound", 0)) > 0:
		if session_wounds > 0:
			session_wounds -= 1
			intent_notes.append("Рана врага затянулась")
		elif int(state.enemy_wounds.get(event_id, 0)) > 0:
			state.enemy_wounds[event_id] = int(state.enemy_wounds[event_id]) - 1
			intent_notes.append("Старая рана врага затянулась")


## Тег героя/поля, гасящий намерение (или "", если намерение действует).
func _intent_negator(ht: Array, env: Array, tactic: Dictionary) -> String:
	if intent.is_empty():
		return ""
	if bool(tactic.get("cancel_intent", false)):
		return "Финт"
	for t: String in intent.get("negated_by", []):
		if ht.has(t) or env.has(t):
			return t
	return ""


func _draw_round_card() -> Dictionary:
	var ids: Array = content.round_cards.keys()
	ids.sort()
	var pool: Array = []
	for id: String in ids:
		if not used_round_cards.has(id):
			pool.append(id)
	if pool.is_empty():
		used_round_cards.clear()
		pool = ids
	var pick: String = pool[rng.randi_range(0, pool.size() - 1)]
	used_round_cards.append(pick)
	return content.round_cards[pick].duplicate(true)


func available_tactics() -> Array:
	var out: Array = []
	var own := _hero_tags({})
	var ids: Array = content.tactics.keys()
	ids.sort()
	for id: String in ids:
		var t: Dictionary = content.tactics[id]
		var req: Dictionary = t.get("requires", {})
		if req.has("hero_any"):
			var hit := false
			for tag: String in req["hero_any"]:
				if own.has(tag):
					hit = true
			if not hit:
				continue
		if req.has("attached") and not enh.has(str(req["attached"])):
			continue
		if bool(req.get("ally", false)) and allies.is_empty():
			continue
		if req.has("traumas_at_least") and TraumaRules.counted(state.character(hero).get("traumas", [])) < int(req["traumas_at_least"]):
			continue
		if int(t.get("mana", 0)) > int(state.resources.get("mana", 0)):
			continue
		out.append(id)
	return out


func _draw_hand() -> Array:
	var pool := available_tactics()
	var out: Array = []
	while out.size() < HAND_SIZE and not pool.is_empty():
		var i := rng.randi_range(0, pool.size() - 1)
		out.append(pool[i])
		pool.remove_at(i)
	return out


## Сыграть раунд с приёмом (или без: ""). Возвращает запись раунда.
func play_round(tactic_id: String = "") -> Dictionary:
	if finished:
		return {}
	var tactic: Dictionary = {}
	if tactic_id != "" and hand.has(tactic_id):
		tactic = content.tactics[tactic_id]
		var cost := int(tactic.get("mana", 0))
		if cost > 0:
			state.resources["mana"] = int(state.resources["mana"]) - cost
			entries.append({"kind": "resource", "text": "◈ мана −%d («%s»)" % [cost, tactic["name"]]})
	var led := ledger(tactic)
	var intent_active := _intent_negator(led["hero_tags"], led["env_tags"], tactic) == ""
	if intent_active and float(intent.get("next_bonus", 0.0)) > 0.0:
		pending_enemy_bonus = float(intent["next_bonus"])
	if intent_active and int(intent.get("wear", 0)) > 0:
		for card: String in enh:
			if WearRules.wears(content, state, card):
				state.wear[card] = mini(100, WearRules.current(state, card) + int(intent["wear"]))
		entries.append({"kind": "info", "text": "«%s»: усиления изнашиваются сильнее" % intent.get("name", "")})
	var roll := rng.randi_range(1, 100)
	var won: bool = roll <= int(led["chance"])
	for l: Dictionary in led["links"]:
		if not discovered.has(l["id"]):
			discovered.append(l["id"])
	var rec := {"round": round_no, "card": round_card, "tactic": tactic_id, "chance": led["chance"], "roll": roll,
		"hero_won": won, "ledger": led, "traumas": [], "intent": intent, "intent_active": intent_active}
	if won:
		hero_wins += 1
		session_wounds += 1
		momentum = "hero"
	else:
		enemy_wins += 1
		momentum = "enemy"
		var extra := int(intent.get("extra_trauma_on_win", 0)) if intent_active else 0
		_lose_round(tactic, rec, extra)
	for t: String in tactic.get("self_tags", []):
		if not hero_extra_tags.has(t):
			hero_extra_tags.append(t)
	if bool(tactic.get("reveal_next", false)):
		next_round_card = _draw_round_card()
		rec["revealed_next"] = next_round_card
	rounds_log.append(rec)
	if state.game_over:
		finished = true
		outcome = "death"
	elif hero_wins >= WINS_NEEDED or enemy_wins >= WINS_NEEDED or round_no >= 3:
		finished = true
		outcome = "win" if hero_wins > enemy_wins else "loss"
	return rec


func _lose_round(tactic: Dictionary, rec: Dictionary, extra: int = 0) -> void:
	var count := (2 if bool(tactic.get("all_in", false)) else 1) + extra
	if bool(tactic.get("guard", false)) and rng.randi_range(1, 100) <= 50:
		entries.append({"kind": "info", "text": "Удар принят в защите — травмы нет"})
		return
	if bool(tactic.get("echo_guard", false)):
		for card: String in enh:
			if Array(content.enhancements.get(card, {}).get("tags", [])).has("Эхо"):
				state.collection.erase(card)
				enh.erase(card)
				entries.append({"kind": "broken", "text": "%s принимает удар и рассыпается" % content.card_name(card), "card": card})
				return
	if bool(tactic.get("ally_guard", false)) and not allies.is_empty():
		var ally: String = allies[0]
		var before: Array = Array(state.character(ally).get("traumas", [])).duplicate()
		TurnResolver.give_traumas(content, state, ally, [], 1, _trauma_pool(), false, rng, result, entries)
		rec["ally_took"] = ally
		if not state.is_alive(ally):
			allies.erase(ally)
		var _unused := before
		return
	var n_before: int = Array(result["traumas"]).size()
	TurnResolver.give_traumas(content, state, hero, enh, count, _trauma_pool(), ward, rng, result, entries)
	rec["traumas"] = Array(result["traumas"]).slice(n_before)


func _trauma_pool() -> String:
	var best: Dictionary = {}
	for e: Dictionary in enemies:
		if best.is_empty() or _enemy_base(e) > _enemy_base(best):
			best = e
	return str(best.get("trauma_pool", "physical"))


func retreat() -> void:
	finished = true
	outcome = "retreat"


# --- летопись силы -------------------------------------------------------------------

func hero_rank() -> int:
	var c: Dictionary = content.characters.get(hero, {})
	var stage: String = state.character(hero).get("stage", "")
	return int(c.get("stages", {}).get(stage, {}).get("rank", c.get("rank", 0)))


func _enemy_base(e: Dictionary) -> float:
	var cls := clampi(int(e.get("class", 1)), 1, 7)
	return 100.0 * pow(RANK_STEP, int(e.get("rank", 0)) - hero_rank()) * CLASS_MULT[cls]


func _hero_tags(tactic: Dictionary) -> Array:
	var out: Array = []
	var c: Dictionary = content.characters.get(hero, {})
	var stage: String = state.character(hero).get("stage", "")
	var base: Array = c.get("stages", {}).get(stage, {}).get("tags", c.get("tags", []))
	for t: String in base:
		_add_unique(out, t)
	for card: String in enh:
		for t: String in content.enhancements.get(card, {}).get("tags", []):
			_add_unique(out, t)
	for a: String in allies:
		for t: String in content.characters.get(a, {}).get("support_tags", []):
			_add_unique(out, t)
	for t: String in mods.get("hero_tags", []):
		_add_unique(out, t)
	for t: String in hero_extra_tags:
		_add_unique(out, t)
	for t: String in tactic.get("add_tags", []):
		_add_unique(out, t)
	if bool(tactic.get("take_field_tag", false)) and not Array(field.get("tags", [])).is_empty():
		_add_unique(out, str(field["tags"][0]))
	return out


func _enemy_tags(tactic: Dictionary) -> Array:
	var out: Array = []
	for e: Dictionary in enemies:
		for t: String in e.get("tags", []):
			_add_unique(out, t)
	for t: String in mods.get("enemy_tags", []):
		_add_unique(out, t)
	if bool(state.enemy_alert.get(event_id, false)):
		_add_unique(out, "Настороженность")
	for t: String in tactic.get("cancel_enemy_tags", []):
		out.erase(t)
	return out


func _env_tags() -> Array:
	var out: Array = []
	for t: String in field.get("tags", []):
		_add_unique(out, t)
	for t: String in round_card.get("tags", []):
		_add_unique(out, t)
	return out


static func _add_unique(arr: Array, v: String) -> void:
	if not arr.has(v):
		arr.append(v)


## Полный расчёт текущего раунда с приёмом. Возвращает силы, шанс, шаги и сработавшие связи.
func ledger(tactic: Dictionary = {}) -> Dictionary:
	var ht := _hero_tags(tactic)
	var et := _enemy_tags(tactic)
	var env := _env_tags()
	var intent_neg := _intent_negator(ht, env, tactic)
	if intent_neg == "":
		for t: String in intent.get("cancel_hero_tags", []):
			ht.erase(t)
	var hs: Array = []
	var es: Array = []
	var links: Array = []
	var sides := {"hero": ht, "enemy": et}

	# 0–2. База, ранг, класс, численность
	var H := 100.0
	hs.append({"label": "База", "kind": "base", "value": H})
	var bases: Array = []
	for e: Dictionary in enemies:
		bases.append(_enemy_base(e))
	var crowd := env.has("Узость") and et.has("Стая") and bases.size() > 2
	if crowd:
		bases.sort()
		bases.reverse()
		bases = bases.slice(0, 2)
		links.append(_link_rec(content.conflicts.get(_find_conflict("Узость", "Стая"), {}), "enemy", 0.0))
	var E := 0.0
	for b: float in bases:
		E += b
	es.append({"label": "База ×%d, ранг и класс" % bases.size() if bases.size() > 1 else "База, ранг и класс", "kind": "base", "value": E,
		"detail": _rank_detail()})

	# 3. Теги сторон
	var contrib := {"hero": {}, "enemy": {}}
	var tag_sum := {"hero": 0.0, "enemy": 0.0}
	for side: String in sides:
		for t: String in sides[side]:
			var v := float(content.combat_tags.get(t, {}).get("value", 0.0))
			if side == "hero" and Array(tactic.get("double_tags", [])).has(t):
				var blocked := false
				for b: String in tactic.get("blocked_by_env", []):
					if env.has(b):
						blocked = true
				if not blocked:
					v *= 2.0
			if absf(v) > 0.0001:
				contrib[side][t] = v
				tag_sum[side] += v
	var hb := clampf(tag_sum["hero"], TAG_CAP_DOWN, TAG_CAP_UP)
	var eb := clampf(tag_sum["enemy"], TAG_CAP_DOWN, TAG_CAP_UP)
	H *= 1.0 + hb
	E *= 1.0 + eb
	hs.append({"label": "Теги героя", "kind": "tags", "pct": hb, "value": H, "tags": contrib["hero"].keys()})
	es.append({"label": "Особенности врага", "kind": "tags", "pct": eb, "value": E, "tags": contrib["enemy"].keys()})

	# 4. Симбиозы
	var syn := {"hero": 0.0, "enemy": 0.0}
	for sid: String in content.synergies:
		var s: Dictionary = content.synergies[sid]
		if bool(s.get("first_round_only", false)) and round_no > 1:
			continue
		for side: String in sides:
			var own: Array = sides[side]
			var all_present := true
			var any_own := false
			for t: String in s.get("tags", []):
				if own.has(t):
					any_own = true
				elif not env.has(t):
					all_present = false
			if all_present and any_own:
				var v := float(s.get("value", 0.15))
				syn[side] += v
				links.append(_link_rec(s, side, v, "synergy"))
	var hsyn := minf(syn["hero"], SYN_CAP)
	var esyn := minf(syn["enemy"], SYN_CAP)
	if hsyn > 0:
		H *= 1.0 + hsyn
		hs.append({"label": "Симбиозы", "kind": "synergy", "pct": hsyn, "value": H})
	if esyn > 0:
		E *= 1.0 + esyn
		es.append({"label": "Симбиозы", "kind": "synergy", "pct": esyn, "value": E})

	# 5. Конфликты
	var con := {"hero": 0.0, "enemy": 0.0}
	for cid: String in content.conflicts:
		var c: Dictionary = content.conflicts[cid]
		if c.get("mode", "") == "crowd":
			continue
		var loser_tag: String = c["a"] if c.get("loser", "b") == "a" else c["b"]
		var winner_tag: String = c["b"] if c.get("loser", "b") == "a" else c["a"]
		for side: String in sides:
			var other := "enemy" if side == "hero" else "hero"
			if not Array(sides[side]).has(loser_tag):
				continue
			if not (Array(sides[other]).has(winner_tag) or env.has(winner_tag)):
				continue
			var pen := float(c.get("value", 0.2))
			if c.get("mode", "") == "nullify":
				pen = float(contrib[side].get(loser_tag, 0.0)) * pen + 0.05
			con[side] += pen
			links.append(_link_rec(c, side, -pen, "conflict"))
	if tactic.has("enemy_penalty_if"):
		var cond: Dictionary = tactic["enemy_penalty_if"]
		for t: String in cond.get("tags", []):
			if et.has(t):
				con["enemy"] += float(cond.get("value", 0.2))
				links.append({"id": "tac:%s>%s" % [tactic.get("id", ""), t], "type": "conflict", "name": tactic.get("name", ""),
					"tags": [str(tactic.get("add_tags", ["?"])[0]), t], "side": "enemy", "value": -float(cond.get("value", 0.2))})
				break
	var hcon := minf(con["hero"], CON_CAP)
	var econ := minf(con["enemy"], CON_CAP)
	if hcon > 0:
		H *= 1.0 - hcon
		hs.append({"label": "Конфликты", "kind": "conflict", "pct": -hcon, "value": H})
	if econ > 0:
		E *= 1.0 - econ
		es.append({"label": "Конфликты", "kind": "conflict", "pct": -econ, "value": E})

	# 6. Поле боя и 7. карта раунда
	for src: Dictionary in [{"d": field, "label": "Поле: %s" % field.get("name", ""), "kind": "field"},
			{"d": round_card, "label": "Раунд: %s" % round_card.get("name", ""), "kind": "round_no"}]:
		var add := {"hero": 0.0, "enemy": 0.0}
		for eff: Dictionary in src["d"].get("effects", []):
			var tag: String = eff["tag"]
			var v := float(eff["value"])
			if tag == "*hero":
				add["hero"] += v
			elif tag == "*both":
				add["hero"] += v
				add["enemy"] += v
			else:
				for side: String in sides:
					if Array(sides[side]).has(tag):
						add[side] += v
						links.append({"id": "env:%s>%s" % [src["d"].get("id", ""), tag], "type": "synergy" if v > 0 else "conflict",
							"name": str(src["d"].get("name", "")), "tags": [str(src["d"].get("name", "")), tag], "side": side, "value": v})
		for side: String in sides:
			var v2 := clampf(add[side], -ENV_CAP, ENV_CAP)
			if absf(v2) > 0.0001:
				if side == "hero":
					H *= 1.0 + v2
					hs.append({"label": src["label"], "kind": src["kind"], "pct": v2, "value": H})
				else:
					E *= 1.0 + v2
					es.append({"label": src["label"], "kind": src["kind"], "pct": v2, "value": E})

	# 8. Состояния
	var tr := TraumaRules.counted(state.character(hero).get("traumas", []))
	if tr > 0:
		var p := -minf(0.3, tr * TRAUMA_PENALTY)
		H *= 1.0 + p
		hs.append({"label": "Травмы (%d)" % tr, "kind": "state", "pct": p, "value": H})
	if momentum == "hero":
		H *= 1.0 + MOMENTUM
		hs.append({"label": "Натиск", "kind": "state", "pct": MOMENTUM, "value": H})
	elif momentum == "enemy":
		E *= 1.0 + MOMENTUM
		es.append({"label": "Натиск", "kind": "state", "pct": MOMENTUM, "value": E})
	var wounds := int(state.enemy_wounds.get(event_id, 0)) + session_wounds
	if wounds > 0:
		var w := -minf(0.4, wounds * WOUND)
		E *= 1.0 + w
		es.append({"label": "Раны (%d)" % wounds, "kind": "state", "pct": w, "value": E})
	if float(tactic.get("bonus", 0.0)) > 0.0:
		var tb := float(tactic["bonus"])
		H *= 1.0 + tb
		hs.append({"label": "Приём: %s" % tactic.get("name", ""), "kind": "tactic", "pct": tb, "value": H})

	# 8б. Намерение врага
	if not intent.is_empty():
		var iname := "Намерение: %s" % intent.get("name", "")
		if intent_neg != "":
			links.append({"id": "int:%s>%s" % [intent.get("id", ""), intent_neg], "type": "conflict", "name": "%s гасит «%s»" % [intent_neg, intent.get("name", "")],
				"tags": [intent_neg, str(intent.get("name", ""))], "side": "enemy", "value": 0.0, "intent": true})
			es.append({"label": iname + " — погашено (%s)" % intent_neg, "kind": "intent", "pct": 0.0, "value": E})
		else:
			var eb2 := float(intent.get("bonus", 0.0))
			if TraumaRules.counted(state.character(hero).get("traumas", [])) > 0:
				eb2 += float(intent.get("bonus_if_hero_wounded", 0.0))
			if intent.has("per_enemy"):
				eb2 += minf(float(intent["per_enemy"]) * maxf(0, enemies.size() - 1), float(intent.get("per_enemy_cap", 0.3)))
			var red: Dictionary = intent.get("reduced_by", {})
			for t: String in red.get("tags", []):
				if ht.has(t):
					eb2 *= float(red.get("factor", 0.5))
					links.append({"id": "int:%s>%s" % [intent.get("id", ""), t], "type": "conflict", "name": "%s ослабляет «%s»" % [t, intent.get("name", "")],
						"tags": [t, str(intent.get("name", ""))], "side": "enemy", "value": 0.0, "intent": true})
					break
			for t: String in intent.get("backfire_tags", []):
				if ht.has(t):
					eb2 = -0.20
					links.append({"id": "int:%s>%s" % [intent.get("id", ""), t], "type": "conflict", "name": "%s: гордыня против врага" % t,
						"tags": [t, str(intent.get("name", ""))], "side": "enemy", "value": -0.20, "intent": true})
					break
			if absf(eb2) > 0.0001:
				E *= 1.0 + eb2
				es.append({"label": iname, "kind": "intent", "pct": eb2, "value": E})
			var hp := float(intent.get("hero_penalty", 0.0))
			if hp > 0.0:
				H *= 1.0 - hp
				hs.append({"label": iname, "kind": "intent", "pct": -hp, "value": H})
				links.append({"id": "int:%s" % intent.get("id", ""), "type": "conflict", "name": str(intent.get("name", "")),
					"tags": [str(intent.get("name", "")), "герой"], "side": "hero", "value": -hp, "intent": true})
	if carry_enemy_bonus > 0.0:
		E *= 1.0 + carry_enemy_bonus
		es.append({"label": "Выжидание окупилось", "kind": "intent", "pct": carry_enemy_bonus, "value": E})

	# 9. Характеристика раунда
	var stat: String = round_card.get("stat", "")
	if stat == "":
		stat = STAT_ROTATION[(round_no - 1) % 3] if round_no > 0 else "power"
	var totals := _hero_totals()
	if bool(tactic.get("best_stat", false)):
		for st: String in STAT_ROTATION:
			if int(totals.get(st, 0)) > int(totals.get(stat, 0)):
				stat = st
	var sv := int(totals.get(stat, 5))
	var sf := clampf(1.0 + STAT_STEP * (sv - 5), 0.6, 1.4)
	H *= sf
	hs.append({"label": "%s %d" % [EffectApplier.STAT_NAMES.get(stat, stat), sv], "kind": "stat", "pct": sf - 1.0, "value": H, "stat": stat})

	var chance := clampi(int(round(100.0 * H / maxf(1.0, H + E))), CHANCE_MIN, CHANCE_MAX)
	return {"hero": H, "enemy": E, "chance": chance, "hero_steps": hs, "enemy_steps": es, "links": links,
		"hero_tags": ht, "enemy_tags": et, "env_tags": env, "stat": stat, "stat_value": sv}


func _hero_totals() -> Dictionary:
	var ev: Dictionary = content.events.get(event_id, {})
	var o := content.option(event_id, option_id)
	return StatResolver.resolve(content, state, hero, enh, ev, o)["totals"]


func _rank_detail() -> String:
	var parts: Array = []
	for e: Dictionary in enemies:
		var d := int(e.get("rank", 0)) - hero_rank()
		parts.append("%s: ранг %+d → ×%.2f, класс ×%.2f" % [e["name"], d, pow(RANK_STEP, d), CLASS_MULT[clampi(int(e.get("class", 1)), 1, 7)]])
	return "; ".join(parts)


func _find_conflict(a: String, b: String) -> String:
	for cid: String in content.conflicts:
		var c: Dictionary = content.conflicts[cid]
		if c["a"] == a and c["b"] == b:
			return cid
	return ""


func _link_rec(d: Dictionary, side: String, value: float, type: String = "conflict") -> Dictionary:
	var tags: Array = d.get("tags", [d.get("a", ""), d.get("b", "")])
	return {"id": str(d.get("id", "")), "type": type, "name": str(d.get("name", "")), "tags": tags, "side": side, "value": value}


## Оценка шанса первого раунда без карты раунда — для строки варианта в планшете.
static func estimate(p_content: Content, state_in: RunState, p_event_id: String, p_option_id: String, draft: Dictionary) -> int:
	if str(draft.get("character", "")) == "":
		return 0
	var s := create(p_content, state_in, p_event_id, p_option_id, draft)
	s.round_no = 1
	s.round_card = {}
	return int(s.ledger({})["chance"])


# --- итог --------------------------------------------------------------------------

func finish() -> Dictionary:
	var success := outcome == "win"
	var story_scheduled := false
	var last: Dictionary = rounds_log[-1] if not rounds_log.is_empty() else {"chance": 0, "roll": 0}
	result["event_id"] = event_id
	result["option_id"] = option_id
	result["executor"] = hero
	result["success"] = success
	result["chance"] = int(last["chance"])
	result["roll"] = int(last["roll"])
	result["rolled"] = not rounds_log.is_empty()
	result["combat"] = {"outcome": outcome, "hero_wins": hero_wins, "enemy_wins": enemy_wins, "rounds": rounds_log.size()}
	var header := {"win": "Победа в бою", "loss": "Поражение в бою", "retreat": "Отступление", "death": "Гибель в бою"}
	entries.push_front({"kind": "story" if success else "info", "text": "%s: %d : %d по раундам" % [header.get(outcome, ""), hero_wins, enemy_wins]})
	if state.game_over:
		pass
	elif success:
		story_scheduled = TurnResolver.apply_success(content, state, event_id, option_id, hero, rng, entries, result, false)
		var shards := 0
		for e: Dictionary in enemies:
			shards += int(e.get("shards", 0))
			var echo: Dictionary = e.get("echo", {})
			if not echo.is_empty() and rng.randf() < float(echo.get("chance", 0.0)):
				entries.append_array(EffectApplier.add_card(content, state, str(echo["card"])))
				entries.append({"kind": "card", "text": "Эхо: %s покоряется тени" % e["name"], "card": echo["card"]})
		if shards > 0:
			entries.append_array(EffectApplier.apply(content, state, {"cmd": "adjust_resource", "resource": "shards", "value": shards}, hero, rng))
			result["loot"] = {"resource": "shards", "value": shards}
		state.enemy_wounds.erase(event_id)
		state.enemy_alert.erase(event_id)
	else:
		var o := content.option(event_id, option_id)
		if outcome == "loss" and o.has("on_failure"):
			entries.append_array(EffectApplier.apply_all(content, state, o["on_failure"], hero, rng))
		if session_wounds > 0:
			state.enemy_wounds[event_id] = int(state.enemy_wounds.get(event_id, 0)) + session_wounds
			entries.append({"kind": "info", "text": "Враг ранен и не оправится до следующей встречи (−%d%%)" % (int(state.enemy_wounds[event_id]) * 10)})
		if outcome == "retreat":
			state.enemy_alert[event_id] = true
			entries.append({"kind": "info", "text": "Враг насторожен: при следующей встрече +10%"})
	# журнал противника: встреча в бою
	var verdict: String = {"win": "победа", "loss": "поражение", "death": "гибель героя", "retreat": "отступление"}.get(outcome, outcome)
	var ev_title := str(content.events.get(event_id, {}).get("title", event_id))
	for e: Dictionary in enemies:
		state.note(str(e.get("id", "")), "Бой «%s» против %s · %s %d:%d" % [ev_title, content.card_name(hero), verdict, hero_wins, enemy_wins])
	TurnResolver.apply_wear(content, state, enh, rng, entries, result)
	return TurnResolver.finish_turn(content, state, event_id, option_id, hero, int(last["chance"]), int(last["roll"]),
		success, story_scheduled, rng, entries, result)
