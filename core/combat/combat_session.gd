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
var used_memories: Array = []     # навыки карт «раз за бой», уже сработавшие (MemoryRules)
var hero_extra_tags: Array = []   # «Боль» и т.п. до конца боя
var session_wounds := 0
var finished := false
var outcome := ""                 # win | loss | retreat | death
var rounds_log: Array = []
var entries: Array = []
var discovered: Array = []        # id связей, сработавших в сыгранных раундах
var crises: Array = []            # кризисы психики в этом бою (PsycheRules): записи kind "crisis"
var result: Dictionary = {"traumas": [], "death": {}, "wear": [], "loot": {}, "progressed": false}
# бой из миссии (docs/15): вместо события — описание боя и теги проверки миссии/этапа
var ctx_event: Dictionary = {}
var ctx_option: Dictionary = {}
var hidden_enemy_tags: Array = []   # для прогноза: теги врага, которых игрок ещё не знает


## Бой этапа миссии. key — ключ ран и настороженности врага (id миссии), spec — {enemies, field, kind},
## hero — ведущий героя, support — остальные герои отряда (до двух в поддержке).
static func create_for_mission(p_content: Content, state_in: RunState, key: String, spec: Dictionary,
		p_hero: String, p_enh: Array, support: Array, p_ctx_event: Dictionary, p_ctx_option: Dictionary) -> CombatSession:
	var s := CombatSession.new()
	s.content = p_content
	s.state = state_in.copy()
	s.rng = RandomNumberGenerator.new()
	s.rng.seed = s.state.rng_seed
	s.rng.state = s.state.rng_state
	s.event_id = key
	s.option_id = str(p_ctx_option.get("id", ""))
	s.hero = p_hero
	s.enh = p_enh.duplicate()
	s.ctx_event = p_ctx_event
	s.ctx_option = p_ctx_option
	for eid: String in spec.get("enemies", []):
		if p_content.enemies.has(eid):
			s.enemies.append(p_content.enemies[eid].duplicate(true))
	var fid := str(spec.get("field", ""))
	s.field = p_content.fields.get(fid, {"id": "", "name": "Без особенностей", "tags": ["суша"], "effects": []})
	s.kind = str(spec.get("kind", "normal"))
	for e: Dictionary in s.enemies:
		if e.get("kind", "normal") == "boss" or (e.get("kind", "") == "elite" and s.kind == "normal"):
			s.kind = str(e["kind"])
	for a: String in support:
		if a != p_hero and s.state.is_alive(a) and not s.allies.has(a) and s.allies.size() < 2:
			s.allies.append(a)
	return s


## Автобой (docs/15 — вмешаться нельзя). Приёмов нет: особые навыки карт в кармашке ведущего и способности
## отряда срабатывают сами, когда выполнено их условие (MemoryRules, docs/16 §9д).
func auto_play() -> void:
	while not finished:
		begin_round()
		play_round()


## Шанс выиграть бой целиком при шансе раунда p (до 2 побед из 3 раундов).
static func fight_chance(round_chance: int) -> float:
	var p := clampf(round_chance / 100.0, 0.0, 1.0)
	return p * p * (3.0 - 2.0 * p)


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
		return str(tactic.get("cancel_intent_by", "Воспоминание"))
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


## Сыграть раунд: сначала срабатывают навыки карт (условия раунда), затем бросок. Возвращает запись раунда.
func play_round() -> Dictionary:
	if finished:
		return {}
	var fired := MemoryRules.fire(self, "round", true)
	var tactic: Dictionary = fired["effect"]
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
	var rec := {"round": round_no, "card": round_card, "memories": fired["fired"], "chance": led["chance"], "roll": roll,
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
	# психика: раунд, перевес врага; кризис здесь длится до конца боя
	if state.is_alive(hero):
		for e: Dictionary in PsycheRules.combat_round(content, state, hero, allies, won, float(led["hero"]), float(led["enemy"]), rng):
			entries.append(e)
			if str(e.get("kind", "")) == "crisis":
				crises.append(e)
				rec["crisis"] = e
	rounds_log.append(rec)
	if state.game_over:
		finished = true
		outcome = "death"
	elif hero_wins >= WINS_NEEDED or enemy_wins >= WINS_NEEDED or round_no >= 3:
		finished = true
		outcome = "win" if hero_wins > enemy_wins else "loss"
	if finished:
		for c: String in [hero] + allies:
			PsycheRules.reset(state, c, "combat")
	return rec


func _lose_round(tactic: Dictionary, rec: Dictionary, extra: int = 0) -> void:
	var lose := MemoryRules.fire(self, "lose", true)
	rec["memories_lose"] = lose["fired"]
	var guard := maxi(int(tactic.get("guard", 0)), int(lose["effect"].get("guard", 0)))
	var count := (2 if bool(tactic.get("all_in", false)) else 1) + extra
	if guard > 0 and rng.randi_range(1, 100) <= guard:
		entries.append({"kind": "info", "text": "Удар отведён — травмы нет"})
		return
	if bool(lose["effect"].get("echo_guard", false)):
		var echo := str(lose["effect"].get("echo_card", ""))
		if echo != "" and enh.has(echo):
			state.collection.erase(echo)
			enh.erase(echo)
			Array(state.character(hero).get("pocket", [])).erase(echo)
			entries.append({"kind": "broken", "text": "%s принимает удар и рассыпается" % content.card_name(echo), "card": echo})
			return
	if bool(tactic.get("ally_guard", false)) and not allies.is_empty():
		var ally: String = allies[0]
		var before: Array = Array(state.character(ally).get("traumas", [])).duplicate()
		InjuryRules.give_traumas(content, state, ally, [], 1, _trauma_pool(), rng, result, entries)
		rec["ally_took"] = ally
		if not state.is_alive(ally):
			allies.erase(ally)
		var _unused := before
		return
	var n_before: int = Array(result["traumas"]).size()
	InjuryRules.give_traumas(content, state, hero, enh, count, _trauma_pool(), rng, result, entries)
	rec["traumas"] = Array(result["traumas"]).slice(n_before)


func _trauma_pool() -> String:
	var best: Dictionary = {}
	for e: Dictionary in enemies:
		if best.is_empty() or _enemy_base(e) > _enemy_base(best):
			best = e
	return str(best.get("trauma_pool", "physical"))


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
	for t: String in tactic.get("cancel_enemy_tags", []):
		out.erase(t)
	for t: String in hidden_enemy_tags:
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


## Полный расчёт текущего раунда с навыками карт (effect от MemoryRules.fire). Возвращает силы, шанс, шаги и сработавшие связи.
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
	for pen: Dictionary in tactic.get("enemy_penalties", []):
		for t: String in pen.get("tags", []):
			if et.has(t):
				con["enemy"] += float(pen.get("value", 0.2))
				links.append({"id": "mem:%s>%s" % [pen.get("card", ""), t], "type": "conflict", "name": str(pen.get("name", "")),
					"tags": [str(pen.get("name", "")), t], "side": "enemy", "value": -float(pen.get("value", 0.2))})
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

	# 7б. Небо (docs/16 §4): под кровавой луной враги злее, в затмение сильнее Тень
	var sky := Atmosphere.sky(content, state)
	if sky == "blood_moon":
		E *= 1.0 + Atmosphere.BLOOD_ENEMY
		es.append({"label": "Кровавая луна", "kind": "field", "pct": Atmosphere.BLOOD_ENEMY, "value": E})
	elif sky == "eclipse" and ht.has("Тень"):
		H *= 1.0 + Atmosphere.ECLIPSE_SHADOW
		hs.append({"label": "Затмение: Тень", "kind": "field", "pct": Atmosphere.ECLIPSE_SHADOW, "value": H})

	# 7в. Отряд (docs/16 §5–7): связка с союзником, доверие к союзнику, ярость в панике
	var bond := BondRules.combat_bonus(content, state, hero, allies)
	if float(bond["value"]) > 0.0:
		H *= 1.0 + float(bond["value"])
		hs.append({"label": "Связка: %s" % bond["name"], "kind": "state", "pct": float(bond["value"]), "value": H})
	for ally: String in allies:
		if TrustRules.value(state, hero, ally) >= TrustRules.HIGH:
			H *= 1.0 + TrustRules.COMBAT_HIGH
			hs.append({"label": "Доверие: %s" % content.card_name(ally), "kind": "state", "pct": TrustRules.COMBAT_HIGH, "value": H})
			break
	for g: Dictionary in GrowthRules.combat_steps(content, state, hero, round_no):
		H *= 1.0 + float(g["pct"])
		hs.append({"label": str(g["label"]), "kind": "state", "pct": float(g["pct"]), "value": H})
	# психика (docs/16 §9г): паника −30% (Ярость −10%, Решимость −15%), подъём духа +50%
	var pk := PsycheRules.mult(content, state, hero, true)
	if not is_equal_approx(pk, 1.0):
		H *= pk
		hs.append({"label": PsycheRules.NAMES[PsycheRules.crisis(state, hero)], "kind": "state", "pct": pk - 1.0, "value": H})

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
	for bs: Dictionary in tactic.get("bonus_steps", []):
		H *= 1.0 + float(bs["pct"])
		hs.append({"label": str(bs["label"]), "kind": "memory", "pct": float(bs["pct"]), "value": H, "card": str(bs.get("card", ""))})

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
	return StatResolver.resolve(content, state, hero, enh, ctx_event, ctx_option)["totals"]


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



