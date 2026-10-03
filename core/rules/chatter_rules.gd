class_name ChatterRules
extends RefCounted
## Мысли и реплики героев над их картами (просьбы владельца 03.10) — для настроения, на игру не влияют. Редко и по
## делу: о месте, где стоит отряд, о сюжете главы, о Воспоминаниях при себе; общие фразы — редкое исключение.
## Без намёков на игру: польза Воспоминания — словами (use_phrase), без цифр; сюжет — через место, где он ждёт.
## Данные — data/chatter.json (tools/gen_chatter.py): lines [{id, hero ("*" — любой), kind (thought | say | wisdom),
## when [теги], text}], dialogs [{id, heroes, when, lines [[герой, текст]…]}]; теги и подстановки — в шапке генератора.
## Все теги when должны совпасть; чем точнее совпало (место, сюжет, кармашек), тем вероятнее реплика.

const KINDS := ["thought", "say", "wisdom"]
const EVENTS := ["after_win", "after_loss", "after_night", "move"]
## вес тега: место, сюжет и Воспоминания — главное; «place» и общий «story» — слабее точных
const WEIGHTS := {"place": 1.0, "story": 2.0, "pocket": 2.5, "knows": 2.5, "skill": 1.0, "worn": 3.0, "no_pocket": 2.5}
## польза Воспоминания словами: главная характеристика и где она сильнее
const STAT_WORDS := {"power": "удар выходит тяжелее", "cunning": "врага проще перехитрить", "will": "дух держится крепче"}
const TAG_WORDS := {"weather": "в непогоду", "survival": "когда надо выжить", "combat": "в бою", "climb": "на кручах",
	"stealth": "когда надо затаиться", "knowledge": "когда нужно знать наверняка", "lure": "когда надо выманить тварь",
	"ritual": "в обрядах", "social": "в разговоре", "duel": "в поединке", "chase": "в погоне"}
const STRONG := ["at:", "story:", "done:", "pocket@"]


## Обстановка (без героя): {tags, place, story_place}.
static func scene(content: Content, state: RunState, heroes: Array, extra: Array = []) -> Dictionary:
	var t: Array = [state.chapter, str(DayRules.phase(content, state).get("id", ""))]
	if FigureRules.on(content, state):
		t.append("midday" if FigureRules.half(state) == 1 else "morning")
	var place := ""
	if DayRules.restricted(content, state) and state.party_at != "":
		place = str(content.locations.get(state.party_at, content.shops.get(state.party_at, {})).get("name", ""))
		t.append("at:" + state.party_at)
		if place != "":
			t.append("place")
		if TideRules.threatened(state, state.party_at):
			t.append("water")
		if (DayPlanner.options(content, state)["today"] as Array).is_empty():
			t.append("idle")
	# сюжет главы: открытые события и последнее пройденное
	var story := ""
	var story_place := ""
	var done := ""
	for mid: String in MissionFlow._sorted(content.missions):
		var m: Dictionary = content.missions[mid]
		if str(m.get("type", "")) != "story" or MissionFlow.chapter_of(content, mid) != state.chapter:
			continue
		var st := str(state.missions.get(mid, {}).get("status", ""))
		if st == "open":
			t.append("story:" + mid)
			if story == "":
				story = mid
				var sl := str(m.get("location", ""))
				story_place = str(content.locations.get(sl, content.shops.get(sl, {})).get("name", ""))
		elif st == "done":
			done = mid
	if story_place != "":
		t.append("story")
	if done != "":
		t.append("done:" + done)
	for cid: String in heroes:
		if not MissionFlow.pocket(state, cid).is_empty():
			t.append("pocket@" + cid)
	t.append_array(extra)
	return {"tags": t, "place": place, "story_place": story_place}


## Говорящий: психика, грань, Воспоминания при себе (знания — отдельно). {tags, card, know_card, worn_card, skill_card}.
static func hero(content: Content, state: RunState, cid: String) -> Dictionary:
	var t: Array = []
	var p := PsycheRules.psyche(state, cid)
	if p < 35:
		t.append("low")
	elif p >= 85:
		t.append("high")
	if EdgeRules.on_edge(state, cid):
		t.append("edge")
	var pocket := MissionFlow.pocket(state, cid).filter(func(k: String) -> bool: return content.enhancements.has(k))
	var card := ""
	var know := ""
	var worn := ""
	var skill := ""
	var worst := 0
	for k: String in pocket:
		if str(content.enhancements[k].get("origin", "")) == "knowledge":
			if know == "":
				know = k
			continue
		if card == "":
			card = k
		if skill == "" and not Dictionary(content.enhancements[k].get("memory", {})).is_empty():
			skill = k
		if WearRules.wears(content, state, k) and WearRules.current(state, k) >= 15 and WearRules.current(state, k) > worst:
			worst = WearRules.current(state, k)
			worn = k
	if card != "":
		t.append("pocket")
	if know != "":
		t.append("knows")
	if skill != "":
		t.append("skill")
	if worn != "":
		t.append("worn")
	if pocket.is_empty() and _free_memory(content, state):
		t.append("no_pocket")
	return {"tags": t, "card": card, "know_card": know, "worn_card": worn, "skill_card": skill}


## Есть Воспоминание, которое не лежит ни в чьём кармашке.
static func _free_memory(content: Content, state: RunState) -> bool:
	for k: String in state.collection:
		if content.enhancements.has(k) and state.owns(k) and MissionFlow.pocket_owner(state, k) == "":
			return true
	return false


## Совпали ли условия: теги when — в обстановке или у говорящего; with:<герой> — герой в отряде.
static func matches(when: Array, ctx: Array, own: Array, heroes: Array) -> bool:
	for t: String in when:
		if t.begins_with("with:"):
			if not heroes.has(t.substr(5)):
				return false
		elif not ctx.has(t) and not own.has(t):
			return false
	return true


## Вес реплики: точнее совпало — вероятнее.
static func weight(when: Array, generic: bool) -> float:
	if when.is_empty():
		return 0.12 if generic else 0.25
	var w := 0.6
	for t: String in when:
		if WEIGHTS.has(t):
			w += float(WEIGHTS[t])
		elif STRONG.any(func(p: String) -> bool: return t.begins_with(p)):
			w += 3.5
		else:
			w += 2.0
	return w


## Выбрать, кто и что скажет. heroes — герои с картами на экране; extra — событие экрана (after_win…);
## need_event — только о нём; recent — недавние id (не повторять). {id, kind: line | dialog, lines [[герой, вид, текст]…]} или {}.
static func pick(content: Content, state: RunState, heroes: Array, extra: Array, need_event: bool, recent: Array,
		rng: RandomNumberGenerator) -> Dictionary:
	var sc := scene(content, state, heroes, extra)
	var ctx: Array = sc["tags"]
	var own := {}
	for cid: String in heroes:
		own[cid] = hero(content, state, cid)
	var cands: Array = []   # [вес, ответ]
	for d: Dictionary in content.chatter.get("dialogs", []):
		var who: Array = d.get("heroes", [])
		var when: Array = d.get("when", [])
		if recent.has(str(d["id"])) or not who.all(func(h: String) -> bool: return heroes.has(h)):
			continue
		if (need_event and not _has_event(when, extra)) or not matches(when, ctx, [], heroes):
			continue
		var ls: Array = []
		for l: Array in d.get("lines", []):
			ls.append([str(l[0]), "say", _fmt(content, str(l[1]), sc, own, str(l[0]), when)])
		if ls.any(func(x: Array) -> bool: return str(x[2]) == ""):
			continue
		cands.append([weight(when, false) * 1.2, {"id": str(d["id"]), "kind": "dialog", "lines": ls}])
	for l: Dictionary in content.chatter.get("lines", []):
		var when2: Array = l.get("when", [])
		if recent.has(str(l["id"])) or (need_event and not _has_event(when2, extra)):
			continue
		var h := str(l.get("hero", "*"))
		var who2: Array = heroes if h == "*" else ([h] if heroes.has(h) else [])
		who2 = who2.filter(func(c: String) -> bool: return matches(when2, ctx, own[c]["tags"], heroes))
		if who2.is_empty():
			continue
		var cid: String = who2[rng.randi() % who2.size()]
		var text := _fmt(content, str(l["text"]), sc, own, cid, when2)
		if text == "":
			continue
		cands.append([weight(when2, h == "*"), {"id": str(l["id"]), "kind": "line", "lines": [[cid, str(l.get("kind", "say")), text]]}])
	if cands.is_empty():
		return {}
	var total := 0.0
	for cd: Array in cands:
		total += float(cd[0])
	var r := rng.randf() * total
	for cd: Array in cands:
		r -= float(cd[0])
		if r <= 0.0:
			return cd[1]
	return cands[-1][1]


## Подстановки: {name} {place} {story_place} {card} {use} {Use} {skill}, в диалогах {card@P01} {use@P01} {Use@P01}.
## "" — не вышло (нет карты, слишком длинно).
static func _fmt(content: Content, text: String, sc: Dictionary, own: Dictionary, cid: String, when: Array) -> String:
	var out := text.replace("{name}", content.card_name(cid)).replace("{place}", str(sc["place"])) \
		.replace("{story_place}", str(sc["story_place"]))
	if out.contains("{card}") or out.contains("{use}") or out.contains("{Use}") or out.contains("{skill}"):
		var info: Dictionary = own.get(cid, {})
		var card := str(info.get("card", ""))
		if when.has("worn"):
			card = str(info.get("worn_card", ""))
		elif when.has("skill"):
			card = str(info.get("skill_card", ""))
		elif when.has("knows"):
			card = str(info.get("know_card", ""))
		if card == "":
			return ""
		out = _card_fmt(content, out, card, "")
	for h: String in own:
		if out.contains("@" + h + "}"):
			var c2 := str((own[h] as Dictionary).get("card", ""))
			if c2 == "":
				return ""
			out = _card_fmt(content, out, c2, "@" + h)
	if out.contains("{") or out.length() > 150:
		return ""
	return out


static func _card_fmt(content: Content, text: String, card: String, suffix: String) -> String:
	var e: Dictionary = content.enhancements.get(card, {})
	var mem: Dictionary = e.get("memory", {})
	var use := use_phrase(content, card)
	return text.replace("{card%s}" % suffix, content.card_name(card)).replace("{use%s}" % suffix, use) \
		.replace("{Use%s}" % suffix, use.left(1).to_upper() + use.substr(1)).replace("{skill%s}" % suffix, str(mem.get("name", "")))


## Чем Воспоминание полезно — словами, без цифр: главная характеристика и где она сильнее
## («удар выходит тяжелее, особенно в бою»).
static func use_phrase(content: Content, card: String) -> String:
	var best: Dictionary = {}
	for b: Dictionary in content.enhancements.get(card, {}).get("bonuses", []):
		if best.is_empty() or int(b.get("value", 0)) > int(best.get("value", 0)):
			best = b
	if best.is_empty() or not STAT_WORDS.has(str(best.get("stat", ""))):
		return "в трудный час не подведёт"
	var out := str(STAT_WORDS[str(best["stat"])])
	var tags: Array = best.get("tags", [])
	if not tags.is_empty() and TAG_WORDS.has(str(tags[0])):
		out += ", особенно " + str(TAG_WORDS[str(tags[0])])
	return out


static func _has_event(when: Array, extra: Array) -> bool:
	return when.any(func(t: String) -> bool: return extra.has(t))


## Сколько держать пузырь: по длине текста.
static func hold(text: String) -> float:
	return clampf(2.6 + text.length() * 0.045, 3.2, 7.5)
