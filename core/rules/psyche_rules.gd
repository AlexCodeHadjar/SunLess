class_name PsycheRules
extends RefCounted
## Психика героя (docs/16 §9г, по мотивам Darkest Dungeon). Шкала 100 → 0; хранится как напряжение
## characters[cid].panic = 100 − психика. На нуле — кризис: ПАНИКА (−30% к характеристикам и силе в бою,
## срывы: слова отчаяния, упрёки, порча усилений, надлом тега) или ПОДЪЁМ ДУХА (+50%, слова поддержки,
## доверие, рост тегов вдвое, иммунитет к потере психики). Шанс подъёма — от характера, доверия и травм.
## Кризис длится до конца боя (если начался в бою) или события (миссии), которое в него ввело.
##
## Что бьёт по психике: угроза, «тёмные» теги места и врагов, небо, свои травмы, вражда в отряде, провалы,
## новые травмы, гибель товарищей, проигранные раунды и перевес врага в силе.
## Что восстанавливает: удачные этапы и миссии, работа с теми, кому доверяешь (+3 и выше), «светлые» теги,
## отдых вне миссий (быстрее в лагере), слова героя в подъёме духа.
## Характер (теги): Хладнокровие ×0,65 потерь, Стойкость ×0,7, Хрупкая психика ×1,3, Трус ×1,25, Паникёр ×1,2;
## шанс подъёма (база 35%): Решимость и Оптимист +15, Вдохновитель +10, Хладнокровие и Стойкость +5,
## Мрачность −5, Хрупкая психика и Трус −10, Паникёр −15; +7 за каждого близкого (доверие ≥3), −5 за травму.

const MAX := 100
const DECAY := 0.12           # восстановление вне миссии, психики в секунду (в лагере ×2)
const PANIC_MULT := 0.70
const UPLIFT_MULT := 1.50
const RAGE_PANIC := 0.90      # Ярость: паника почти не гасит силу в бою
const RESOLVE_PANIC := 0.85   # Решимость: и в панике держится лучше
const PANIC_AFTER := 35       # психика после конца паники
const UPLIFT_AFTER := 70      # …и после подъёма духа
const UPLIFT_BASE := 35
const UPLIFT_MIN := 5
const UPLIFT_MAX := 70
const ACT_CHANCE := 0.6       # шанс поступка героя в кризисе перед этапом

# потери и прибавки психики (положительное — прибавка)
const THREAT := -6            # за единицу угрозы при прибытии
const DREAD := -5             # за «тёмный» тег места или врага (не больше DREAD_CAP)
const DREAD_CAP := -20
const CALM := 3               # за «светлый» тег
const SKY := {"blood_moon": -8, "eclipse": -5, "storm": -5, "day": 2}
const OWN_TRAUMA := -3        # за каждую свою травму при прибытии
const FEUD := -8              # пара в отряде с доверием ≤ −2
const TEAM := 4               # союзник с доверием ≥ 3
const STAGE := {"fail": [-20, -12], "partial": [-8, -4], "ok": [3, 1]}   # [исполнитель, остальные]
const NEW_TRAUMA := -20
const DEATH := -35
const ROUND_LOST := -14
const ROUND_WON := 4
const GAP_MAX := -18          # перевес врага в силе за раунд
const END := {"success": 5, "partial": 1, "failure": -10, "retreat": -4}

const TAG_LOSS := {"Хладнокровие": 0.65, "Стойкость": 0.7, "Хрупкая психика": 1.3, "Трус": 1.25, "Паникёр": 1.2}
const TAG_UPLIFT := {"Решимость": 15, "Оптимист": 15, "Вдохновитель": 10, "Хладнокровие": 5, "Стойкость": 5,
	"Мрачность": -5, "Хрупкая психика": -10, "Трус": -10, "Паникёр": -15}
const DREAD_TAGS := ["Тьма", "Глубина", "Кладбище", "Мёртвое тело", "Запах крови", "Ментальное давление", "Пожирание душ",
	"Буря", "Прилив", "Порча", "Проклятие", "Страх", "Нежить", "Гигант", "Древний", "Заклинание Кошмара", "Паразит", "Одержимость"]
const CALM_TAGS := ["Святость", "Свет", "Звёздный свет", "Лунный свет", "Укрытия", "Штиль", "Тишина"]
const NAMES := {"panic": "Паника", "uplift": "Подъём духа"}


# --- чтение ------------------------------------------------------------------------

static func value(state: RunState, cid: String) -> int:
	return int(state.character(cid).get("panic", 0))


static func psyche(state: RunState, cid: String) -> int:
	return MAX - value(state, cid)


static func crisis(state: RunState, cid: String) -> String:
	return str(state.character(cid).get("psy", {}).get("state", ""))


static func word(psy: int) -> String:
	if psy <= 0:
		return "кризис"
	if psy < 15:
		return "ломается"
	if psy < 40:
		return "на пределе"
	if psy < 70:
		return "держится"
	return "крепок"


static func _tags(content: Content, state: RunState, cid: String) -> Array:
	return MissionFlow.hero_tags(content, state, cid)


## Во сколько раз герой теряет психику (характер и развитие тегов).
static func loss_mult(content: Content, state: RunState, cid: String) -> float:
	if GrowthRules.has(content, state, cid, "panic_immune"):
		return 0.0
	var k := 1.0
	for t: String in _tags(content, state, cid):
		k *= float(TAG_LOSS.get(t, 1.0))
	return k


## Шанс подъёма духа (%) при кризисе: характер, доверие в отряде, травмы.
static func uplift_chance(content: Content, state: RunState, cid: String, squad: Array) -> int:
	var p := UPLIFT_BASE
	for t: String in _tags(content, state, cid):
		p += int(TAG_UPLIFT.get(t, 0))
	var close := 0
	for other: String in squad:
		if other != cid and state.is_alive(other) and TrustRules.value(state, cid, other) >= TrustRules.HIGH:
			close += 1
	p += 7 * mini(close, 3)
	p -= 5 * TraumaRules.counted(state.character(cid).get("traumas", []))
	return clampi(p, UPLIFT_MIN, UPLIFT_MAX)


# --- изменение ------------------------------------------------------------------------

## Изменить психику (delta < 0 — потеря). На нуле — кризис. Возвращает записи отчёта.
## origin: "mission" | "combat" — когда кризис закончится.
static func change(content: Content, state: RunState, cid: String, delta: int, reason: String, squad: Array = [],
		rng: RandomNumberGenerator = null, origin: String = "mission", can_break: bool = true) -> Array:
	var ch := state.character(cid)
	if ch.is_empty() or not state.is_alive(cid) or delta == 0 or not TutorialRules.enabled(state, "panic"):
		return []
	var st := crisis(state, cid)
	if delta < 0:
		if st == "uplift":
			return []   # в подъёме духа психика не падает
		delta = int(round(delta * loss_mult(content, state, cid)))
		if delta == 0:
			return []
	var before := value(state, cid)
	var after := clampi(before - delta, 0, MAX)
	if delta < 0:
		after = mini(after, maxi(before, GrowthRules.panic_cap(content, state, cid)))
		if not can_break:
			after = mini(after, MAX - 1)
	ch["panic"] = after
	if after >= MAX and st == "":
		if rng == null:
			rng = RandomNumberGenerator.new()
			rng.seed = state.rng_seed + int(state.clock * 7.0) + cid.hash()
		var which := "uplift" if rng.randi_range(1, 100) <= uplift_chance(content, state, cid, squad) else "panic"
		return enter(content, state, cid, which, origin, reason, rng)
	return []


## Войти в кризис. Запись kind "crisis" с репликой героя.
static func enter(content: Content, state: RunState, cid: String, which: String, origin: String, reason: String,
		rng: RandomNumberGenerator) -> Array:
	state.character(cid)["psy"] = {"state": which, "origin": origin}
	state.note(cid, "%s (%s)" % [NAMES[which], reason])
	return [{"kind": "crisis", "card": cid, "state": which, "origin": origin,
		"quote": line(content, which, cid, "", "", rng),
		"text": "%s: %s — %s" % [content.card_name(cid), NAMES[which].to_upper(), reason]}]


## Конец кризиса: боя (origin "combat") или события ("" — любого). Психика — на исходную после кризиса.
static func reset(state: RunState, cid: String, origin: String = "") -> bool:
	var ch := state.character(cid)
	var st := crisis(state, cid)
	if st == "" or (origin != "" and str(ch["psy"].get("origin", "")) != origin):
		return false
	ch.erase("psy")
	ch["panic"] = MAX - (PANIC_AFTER if st == "panic" else UPLIFT_AFTER)
	return true


## Восстановление вне миссий (кроме Фанатика). Кризисов вне миссий не бывает.
static func decay(state: RunState, dt: float, content: Content = null) -> void:
	for cid: String in state.characters:
		var ch: Dictionary = state.characters[cid]
		if content != null and GrowthRules.has(content, state, cid, "panic_no_decay"):
			continue
		if int(ch.get("panic", 0)) > 0 and not MissionFlow.on_mission(state, cid):
			ch["panic"] = maxi(0, int(round(float(ch["panic"]) - DECAY * dt)))


# --- влияние состояния ----------------------------------------------------------------

## Трус в панике сбегает с этапа (Отчаянная храбрость — нет).
static func flees(content: Content, state: RunState, cid: String) -> bool:
	return crisis(state, cid) == "panic" and _tags(content, state, cid).has("Трус") and not GrowthRules.has(content, state, cid, "brave")


## Гордыня в панике не даёт отряду отступить: "" — нет, иначе имя.
static func refuses_retreat(content: Content, state: RunState, heroes: Array) -> String:
	for cid: String in heroes:
		if state.is_alive(cid) and crisis(state, cid) == "panic" and _tags(content, state, cid).has("Гордыня"):
			return content.card_name(cid)
	return ""


## Множитель характеристик и силы: паника 0,7 (Решимость 0,85), подъём 1,5.
static func mult(content: Content, state: RunState, cid: String, in_combat: bool = false) -> float:
	match crisis(state, cid):
		"uplift":
			return UPLIFT_MULT
		"panic":
			var tags := _tags(content, state, cid)
			if in_combat and tags.has("Ярость"):
				return RAGE_PANIC
			if tags.has("Решимость"):
				return RESOLVE_PANIC
			return PANIC_MULT
	return 1.0


## Прибавки к проверке от кризиса — к уже посчитанным итогам: [{source, stat, value}].
static func check_parts(content: Content, state: RunState, cid: String, totals: Dictionary) -> Array:
	var k := mult(content, state, cid)
	if is_equal_approx(k, 1.0):
		return []
	var out: Array = []
	for s: String in ["power", "will", "cunning"]:
		var v := int(totals.get(s, 0))
		var d := int(round(v * (k - 1.0)))
		if d == 0 and k < 1.0 and v > 0:
			d = -1
		if d != 0:
			out.append({"source": NAMES[crisis(state, cid)], "stat": s, "value": d})
	return out


# --- события миссии -----------------------------------------------------------------

## Прибытие: угроза, тёмные и светлые теги, небо, травмы, вражда и доверие в отряде.
static func arrival(content: Content, state: RunState, m: Dictionary, heroes: Array, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var tags: Array = Array(m.get("known_tags", [])) + Array(m.get("hidden_tags", []))
	tags.append_array(content.fields.get(str(m.get("field", "")), {}).get("tags", []))
	var dread := 0
	var calm := 0
	for t: String in tags:
		if DREAD_TAGS.has(t):
			dread += DREAD
		elif CALM_TAGS.has(t):
			calm += CALM
	dread = maxi(dread, DREAD_CAP)
	var sky := int(SKY.get(Atmosphere.sky(content, state), 0))
	for cid: String in heroes:
		if not state.is_alive(cid):
			continue
		var d := THREAT * int(m.get("threat", 1)) + dread + calm + sky
		d += OWN_TRAUMA * TraumaRules.counted(state.character(cid).get("traumas", []))
		for other: String in heroes:
			if other == cid or not state.is_alive(other):
				continue
			var t := TrustRules.value(state, cid, other)
			if t <= -2:
				d += FEUD
			elif t >= TrustRules.HIGH:
				d += TEAM
		d -= int(GrowthRules.total(content, state, cid, "panic_mission"))
		if GrowthRules.has(content, state, cid, "panic_threat_immune"):
			d -= THREAT * int(m.get("threat", 1))   # Осторожный: угроза не пугает
		out.append_array(change(content, state, cid, d, "место и угроза", heroes, rng))
	return out


## После этапа: исход, новые травмы, гибель товарищей.
static func after_stage(content: Content, state: RunState, heroes: Array, actor: String, outcome: String,
		traumas_got: Dictionary, dead: Array, rng: RandomNumberGenerator, stage_name: String) -> Array:
	var out: Array = []
	var d2: Array = STAGE.get(outcome, [0, 0])
	for cid: String in heroes:
		if not state.is_alive(cid):
			continue
		var d := int(d2[0]) if cid == actor else int(d2[1])
		d += NEW_TRAUMA * int(traumas_got.get(cid, 0))
		for x: String in dead:
			if x != cid:
				d += DEATH
		out.append_array(change(content, state, cid, d, "этап «%s»" % stage_name, heroes, rng))
	return out


## Раунд боя: проигрыш, выигрыш и перевес врага в силе. Кризис здесь — до конца боя.
static func combat_round(content: Content, state: RunState, hero: String, allies: Array, won: bool, h: float, e: float,
		rng: RandomNumberGenerator) -> Array:
	var squad: Array = [hero] + allies
	var d := ROUND_WON if won else ROUND_LOST
	if h > 0.0 and e > h:
		d += int(maxf(GAP_MAX, -25.0 * (e / h - 1.0)))
	var out: Array = change(content, state, hero, d, "раунд боя", squad, rng, "combat")
	for a: String in allies:
		out.append_array(change(content, state, a, int(d / 2), "раунд боя", squad, rng, "combat"))
	return out


## Итог миссии для психики: удача и провал; затем кризисы события заканчиваются.
static func end_mission(content: Content, state: RunState, heroes: Array, outcome: String, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for cid: String in heroes:
		if state.is_alive(cid):
			out.append_array(change(content, state, cid, int(END.get(outcome, 0)), "итог миссии", heroes, rng, "mission", false))
	for cid: String in heroes:
		if state.is_alive(cid):
			var st := crisis(state, cid)
			if reset(state, cid):
				out.append({"kind": "info", "card": cid, "text": "%s приходит в себя после: %s" % [content.card_name(cid), NAMES[st].to_lower()]})
	return out


# --- поступки героя в кризисе ---------------------------------------------------------

## Перед этапом: герой в кризисе может что-то сделать. Возвращает записи отчёта (kind "psy_act").
## Паника: отчаяние (психика отряда −10), упрёк (доверие −1), срыв (износ усиления +30),
## надлом (редко: мутация тега). Подъём: поддержка (психика +12), плечом к плечу (доверие +1), озарение (+1 опыт тегу).
static func act(content: Content, state: RunState, cid: String, squad: Array, rng: RandomNumberGenerator) -> Array:
	var st := crisis(state, cid)
	if st == "" or not state.is_alive(cid) or rng.randf() >= ACT_CHANCE:
		return []
	var others: Array = squad.filter(func(x: String) -> bool: return x != cid and state.is_alive(x))
	var tags := _tags(content, state, cid)
	var other := str(others[rng.randi_range(0, others.size() - 1)]) if not others.is_empty() else ""
	var kind := ""
	if st == "panic":
		var w := {"despair": 4, "blame": 3 if other != "" else 0, "break": 2, "scar": 1}
		if tags.has("Паникёр"):
			w["despair"] += 3
		for t: String in ["Ложь", "Гордыня", "Мрачность"]:
			if tags.has(t):
				w["blame"] += 2
		for t2: String in ["Импровизация", "Ярость"]:
			if tags.has(t2):
				w["break"] += 2
		if others.is_empty():
			w["despair"] = 0
		kind = _pick(w, rng)
	else:
		var w2 := {"rally": 4 if not others.is_empty() else 0, "bond": 3 if other != "" else 0, "insight": 2}
		if tags.has("Вдохновитель"):
			w2["rally"] += 3
		kind = _pick(w2, rng)
	var out: Array = []
	var extra := ""
	match kind:
		"despair":
			var hit := int(round(-10 * (1.5 if tags.has("Паникёр") else 1.0)))
			for o: String in others:
				out.append_array(change(content, state, o, hit, "отчаяние %s" % content.card_name(cid), squad, rng))
		"blame":
			out.append_array(TrustRules.change(content, state, cid, other, -1, "упрёк в панике"))
		"break":
			var items: Array = MissionFlow.pocket(state, cid).filter(func(c: String) -> bool: return WearRules.wears(content, state, c))
			if items.is_empty():
				kind = "despair_self"
				out.append_array(change(content, state, cid, -5, "срыв", squad, rng))
			else:
				var card := str(items[rng.randi_range(0, items.size() - 1)])
				extra = content.card_name(card)
				var w3 := WearRules.current(state, card) + 30
				if w3 >= 100:
					state.collection.erase(card)
					state.wear.erase(card)
					Array(state.character(cid).get("pocket", [])).erase(card)
					out.append({"kind": "broken", "card": card, "text": "%s ломает в панике: %s" % [content.card_name(cid), extra]})
				else:
					state.wear[card] = w3
		"scar":
			var cand: Array = []
			for t3: String in tags:
				if content.tag_growth.has(t3) and not state.character(cid).get("growth", {}).has(t3):
					cand.append(t3)
			if cand.is_empty():
				kind = "despair_self"
			else:
				var tag := str(cand[rng.randi_range(0, cand.size() - 1)])
				var g: Dictionary = state.character(cid).get("growth", {})
				g[tag] = "mut"
				state.character(cid)["growth"] = g
				var e: Dictionary = content.tag_growth[tag]["mut"]
				extra = "%s → %s" % [tag, e.get("name", "")]
				out.append({"kind": "growth", "card": cid, "mutation": true,
					"text": "%s: надлом — «%s» мутирует: %s (%s)" % [content.card_name(cid), tag, e.get("name", ""), e.get("text", "")]})
		"rally":
			var up := int(round(12 * (1.5 if tags.has("Вдохновитель") else 1.0)))
			for o2: String in others:
				out.append_array(change(content, state, o2, up, "поддержка %s" % content.card_name(cid), squad, rng))
		"bond":
			out.append_array(TrustRules.change(content, state, cid, other, 1, "поддержал в подъёме духа"))
		"insight":
			var bag: Dictionary = state.character(cid).get("tag_xp", {})
			var growable: Array = tags.filter(func(t4: String) -> bool: return content.tag_growth.has(t4))
			if not growable.is_empty():
				var tg := str(growable[rng.randi_range(0, growable.size() - 1)])
				bag[tg] = float(bag.get(tg, 0.0)) + 1.0
				state.character(cid)["tag_xp"] = bag
				extra = tg
	var quote := line(content, kind, cid, content.card_name(other) if other != "" else "", extra, rng)
	out.push_front({"kind": "psy_act", "card": cid, "state": st, "act": kind, "quote": quote,
		"text": "%s: %s" % [content.card_name(cid), quote]})
	return out


static func _pick(w: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0
	for k: String in w:
		total += int(w[k])
	var r := rng.randi_range(1, maxi(1, total))
	for k2: String in w:
		r -= int(w[k2])
		if r <= 0:
			return k2
	return str(w.keys()[0])


## Реплика героя: data/psyche.json {act: [строки с {name} {other} {card}]}.
static func line(content: Content, act_name: String, cid: String, other: String, extra: String, rng: RandomNumberGenerator) -> String:
	var lines: Array = content.psyche_lines.get(act_name, [])
	if lines.is_empty():
		return ""
	var s := str(lines[rng.randi_range(0, lines.size() - 1)])
	return s.replace("{name}", content.card_name(cid)).replace("{other}", other if other != "" else "все").replace("{card}", extra)


## Характер героя в двух словах — для планшета и брифинга.
static func reaction(content: Content, state: RunState, cid: String) -> String:
	var tags := _tags(content, state, cid)
	var out: Array = ["подъём духа — %d%%" % uplift_chance(content, state, cid, [])]
	var k := loss_mult(content, state, cid)
	if not is_equal_approx(k, 1.0):
		out.append("теряет психику ×%s" % str(snappedf(k, 0.01)))
	if tags.has("Трус"):
		out.append("в панике сбегает")
	if tags.has("Гордыня"):
		out.append("в панике не отступает")
	if tags.has("Ярость"):
		out.append("в панике в бою почти не слабеет")
	if tags.has("Паникёр"):
		out.append("паника заразна")
	if tags.has("Вдохновитель"):
		out.append("в подъёме — сильная поддержка")
	return "; ".join(out)
