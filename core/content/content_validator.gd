class_name ContentValidator
extends RefCounted
## Проверка данных до запуска (GDD 8.5). Возвращает список ошибок; пусто — всё в порядке.

const KNOWN_CMDS := ["add_card", "remove_card", "add_ability", "add_trauma", "remove_trauma", "clear_traumas",
	"set_flag", "clear_flag", "adjust_resource", "add_temp", "add_perm", "set_stage", "reveal", "add_codex",
	"set_region", "remove_temporaries", "end_demo", "text", "combat_mod", "spawn_event", "start_chapter", "reset_wear"]
const KNOWN_CONDITIONS := ["in_collection", "not_owned", "executor_is", "has_flag", "not_flag", "owned_count",
	"attached", "executor_has_trauma"]
const CHECKS := ["stat", "gate_stat", "auto", "combat"]
const POOLS := ["all", "physical", "environment", "mental"]
const EVENT_TYPES := ["story", "reward", "side", "random"]
const STATS := ["power", "will", "cunning"]


static func validate(c: Content) -> Array[String]:
	var errors: Array[String] = []
	errors.append_array(c.load_errors)

	for tid: String in c.traumas:
		var t: Dictionary = c.traumas[tid]
		if not ["physical", "environment", "mental"].has(t.get("category", "")):
			errors.append("%s: неизвестная категория травмы" % tid)

	for iid: String in c.initiators:
		var ev: String = c.initiators[iid].get("event", "")
		if not c.events.has(ev):
			errors.append("Инициатор %s ссылается на несуществующее событие %s" % [iid, ev])

	for rid: String in c.regions:
		for eid: String in c.regions[rid].get("random_pool", []):
			if not c.events.has(eid):
				errors.append("Регион %s: в пуле нет события %s" % [rid, eid])

	for eid: String in c.events:
		_validate_event(c, eid, errors)

	_validate_combat(c, errors)
	_validate_chapters(c, errors)
	_validate_missions(c, errors)

	# Сюжетная цепочка от E01 должна дойти до конца без обрывов и циклов.
	var seen := {}
	var cur := "E01"
	while cur != "":
		if seen.has(cur):
			errors.append("Сюжетная цепочка зациклена на %s" % cur)
			break
		seen[cur] = true
		if not c.events.has(cur):
			errors.append("Сюжетная цепочка ведёт в несуществующее событие %s" % cur)
			break
		cur = str(c.events[cur].get("next", ""))
	return errors


static func _validate_event(c: Content, eid: String, errors: Array[String]) -> void:
	var ev: Dictionary = c.events[eid]
	var where := "Событие %s" % eid
	var etype: String = ev.get("type", "")
	if not EVENT_TYPES.has(etype):
		errors.append("%s: неизвестный тип «%s»" % [where, etype])
	if str(ev.get("title", "")) == "":
		errors.append("%s: нет заголовка" % where)
	var nxt: String = ev.get("next", "")
	if nxt != "" and not c.events.has(nxt):
		errors.append("%s: next → несуществующее %s" % [where, nxt])
	for tag: String in ev.get("tags", []):
		if not c.tags.has(tag):
			errors.append("%s: неизвестный тег «%s»" % [where, tag])
	if ev.has("trauma_pool") and not POOLS.has(ev["trauma_pool"]):
		errors.append("%s: неизвестный пул травм" % where)
	_validate_effects(c, where + " on_appear", ev.get("on_appear", []), errors)
	_validate_effects(c, where + " on_success_common", ev.get("on_success_common", []), errors)

	var opts: Array = ev.get("options", [])
	if opts.size() != 3:
		errors.append("%s: вариантов %d, нужно ровно 3" % [where, opts.size()])
	var story_count := 0
	var ids := {}
	for o: Dictionary in opts:
		var oid: String = o.get("id", "")
		var ow := "%s / %s" % [where, oid]
		if oid == "" or ids.has(oid):
			errors.append("%s: пустой или повторный id варианта" % ow)
		ids[oid] = true
		if str(o.get("label", "")) == "":
			errors.append("%s: нет названия" % ow)
		var check: String = o.get("check", "stat")
		if not CHECKS.has(check):
			errors.append("%s: неизвестный тип проверки «%s»" % [ow, check])
		var sum := 0
		for s: String in o.get("req", {}):
			if not STATS.has(s):
				errors.append("%s: неизвестная характеристика «%s»" % [ow, s])
			sum += int(o["req"][s])
		if check == "combat":
			var spec: Dictionary = o.get("combat", {})
			if Array(spec.get("enemies", [])).is_empty():
				errors.append("%s: бой без противников" % ow)
			for en: String in spec.get("enemies", []):
				if not c.enemies.has(en):
					errors.append("%s: нет противника %s" % [ow, en])
			if spec.has("field") and not c.fields.has(str(spec["field"])):
				errors.append("%s: нет поля боя %s" % [ow, spec["field"]])
		if check in ["stat", "gate_stat"] and sum <= 0:
			errors.append("%s: проверка без требований — нужен check: auto" % ow)
		if check == "gate_stat" and Array(o.get("conditions", [])).is_empty():
			errors.append("%s: gate_stat без условий" % ow)
		if o.has("trauma_pool") and not POOLS.has(o["trauma_pool"]):
			errors.append("%s: неизвестный пул травм" % ow)
		for tag: String in o.get("tags", []):
			if not c.tags.has(tag):
				errors.append("%s: неизвестный тег «%s»" % [ow, tag])
		for cond: Dictionary in o.get("conditions", []):
			var ct: String = cond.get("type", "")
			if not KNOWN_CONDITIONS.has(ct):
				errors.append("%s: неизвестное условие «%s»" % [ow, ct])
			for key: String in ["card"]:
				if cond.has(key) and c.card_kind(str(cond[key])) == "":
					errors.append("%s: условие ссылается на несуществующую карту %s" % [ow, cond[key]])
			for card: String in cond.get("ids", []) + cond.get("cards", []):
				if c.card_kind(card) == "":
					errors.append("%s: условие ссылается на несуществующую карту %s" % [ow, card])
		for r: String in o.get("cost", {}):
			if not ["shards", "mana"].has(r):
				errors.append("%s: неизвестный ресурс «%s»" % [ow, r])
		_validate_effects(c, ow + " on_success", o.get("on_success", []), errors)
		_validate_effects(c, ow + " on_failure", o.get("on_failure", []), errors)
		if bool(o.get("story", false)):
			story_count += 1
			_validate_story_option(c, ev, o, ow, errors)
	if etype == "story" and story_count != 1:
		errors.append("%s: сюжетных вариантов %d, нужен ровно 1" % [where, story_count])
	if etype != "story" and story_count > 0:
		errors.append("%s: сюжетный вариант у несюжетного события" % where)
	if etype == "reward":
		for o: Dictionary in opts:
			if o.get("check", "stat") != "auto":
				errors.append("%s: у наградного события все варианты должны быть auto" % where)


## Сюжетный вариант не должен зависеть от того, что может исчезнуть (GDD 4.4).
static func _validate_story_option(c: Content, ev: Dictionary, o: Dictionary, ow: String, errors: Array[String]) -> void:
	for cond: Dictionary in o.get("conditions", []):
		var card: String = cond.get("card", "")
		if card == "":
			continue
		var e: Dictionary = c.enhancements.get(card, {})
		if not e.is_empty() and bool(e.get("wears", true)) and not Array(e.get("wear_exempt_arcs", [])).has(ev.get("arc", "")):
			errors.append("%s: сюжетный вариант требует изнашиваемую карту %s" % [ow, card])
		var ch: Dictionary = c.characters.get(card, {})
		if not ch.is_empty() and card != "P01":
			errors.append("%s: сюжетный вариант требует смертного персонажа %s" % [ow, card])


static func _validate_effects(c: Content, where: String, effects: Array, errors: Array[String]) -> void:
	for e: Dictionary in effects:
		var cmd: String = e.get("cmd", "")
		if not KNOWN_CMDS.has(cmd):
			errors.append("%s: неизвестная команда «%s»" % [where, cmd])
			continue
		for key: String in ["card"]:
			if e.has(key) and c.card_kind(str(e[key])) == "":
				errors.append("%s: %s ссылается на несуществующую карту %s" % [where, cmd, e[key]])
		if e.has("ability") and not c.abilities.has(str(e["ability"])):
			errors.append("%s: нет способности %s" % [where, e["ability"]])
		if e.has("trauma") and not c.traumas.has(str(e["trauma"])):
			errors.append("%s: нет травмы %s" % [where, e["trauma"]])
		if e.has("stat") and not STATS.has(str(e["stat"])):
			errors.append("%s: неизвестная характеристика %s" % [where, e["stat"]])
		if cmd == "reveal":
			if e.has("event") and not c.events.has(str(e["event"])):
				errors.append("%s: reveal несуществующего события %s" % [where, e["event"]])
		if cmd == "set_stage":
			var ch: Dictionary = c.characters.get(str(e.get("character", "")), {})
			if not ch.get("stages", {}).has(str(e.get("stage", ""))):
				errors.append("%s: нет стадии %s" % [where, e.get("stage", "")])


## Главы свободного режима: места связаны, якоря и события ссылаются на существующее.
static func _validate_chapters(c: Content, errors: Array[String]) -> void:
	for cid: String in c.chapters:
		var ch: Dictionary = c.chapters[cid]
		var nodes := {}
		for n: Dictionary in ch.get("nodes", []):
			nodes[str(n["id"])] = true
		if not nodes.has(str(ch.get("start_node", ""))):
			errors.append("Глава %s: нет стартового места" % cid)
		for l: Array in ch.get("links", []):
			for nid: Variant in l:
				if not nodes.has(str(nid)):
					errors.append("Глава %s: связь с несуществующим местом %s" % [cid, nid])
		var ids: Array = [str(ch.get("final", ""))]
		for a: Dictionary in Array(ch.get("anchors", [])) + Array(ch.get("threads", [])):
			ids.append(str(a["event"]))
			for dep: String in a.get("after", []):
				if not c.events.has(dep):
					errors.append("Глава %s: условие ссылается на несуществующее %s" % [cid, dep])
		for eid: String in ids:
			if not c.events.has(eid):
				errors.append("Глава %s: нет события %s" % [cid, eid])
		for eid: String in c.events:
			var ev: Dictionary = c.events[eid]
			if str(ev.get("chapter", "")) == cid and ev.has("node") and not nodes.has(str(ev["node"])):
				errors.append("%s: место %s не найдено в главе %s" % [eid, ev["node"], cid])


## Боевые данные: все теги связей, полей, карт раунда и носителей существуют.
static func _validate_combat(c: Content, errors: Array[String]) -> void:
	var T := c.combat_tags
	for sid: String in c.synergies:
		for t: String in c.synergies[sid].get("tags", []):
			if not T.has(t):
				errors.append("Симбиоз %s: нет тега «%s»" % [sid, t])
	for cid: String in c.conflicts:
		for key: String in ["a", "b"]:
			if not T.has(str(c.conflicts[cid].get(key, ""))):
				errors.append("Конфликт %s: нет тега «%s»" % [cid, c.conflicts[cid].get(key, "")])
	for fid: String in c.fields:
		for t: String in c.fields[fid].get("tags", []):
			if not T.has(t):
				errors.append("Поле %s: нет тега «%s»" % [fid, t])
	for rid: String in c.round_cards:
		for t: String in c.round_cards[rid].get("tags", []):
			if not T.has(t):
				errors.append("Карта раунда %s: нет тега «%s»" % [rid, t])
	for eid: String in c.enemies:
		for t: String in c.enemies[eid].get("tags", []):
			if not T.has(t):
				errors.append("Противник %s: нет тега «%s»" % [eid, t])
	for pid: String in c.characters:
		var ch: Dictionary = c.characters[pid]
		var all: Array = Array(ch.get("tags", [])) + Array(ch.get("support_tags", []))
		for st: Dictionary in ch.get("stages", {}).values():
			all += Array(st.get("tags", []))
		for t: String in all:
			if not T.has(t):
				errors.append("Персонаж %s: нет тега «%s»" % [pid, t])
	for uid: String in c.enhancements:
		for t: String in c.enhancements[uid].get("tags", []):
			if not T.has(t):
				errors.append("Усиление %s: нет тега «%s»" % [uid, t])
	for aid: String in c.enemy_abilities:
		var a: Dictionary = c.enemy_abilities[aid]
		for t: String in Array(a.get("when_tags", [])) + Array(a.get("negated_by", [])) + Array(a.get("cancel_hero_tags", [])) \
				+ Array(a.get("backfire_tags", [])) + Array(a.get("reduced_by", {}).get("tags", [])):
			if not T.has(t):
				errors.append("Способность врага %s: нет тега «%s»" % [aid, t])
	for xid: String in c.tactics:
		for t: String in Array(c.tactics[xid].get("add_tags", [])) + Array(c.tactics[xid].get("self_tags", [])):
			if not T.has(t):
				errors.append("Приём %s: нет тега «%s»" % [xid, t])


## Миссии и локации (docs/15, ветка gameplay/missions).
const MISSION_TYPES := ["story", "side", "random"]


static func _validate_missions(c: Content, errors: Array[String]) -> void:
	for lid: String in c.locations:
		var loc: Dictionary = c.locations[lid]
		if str(loc.get("name", "")) == "":
			errors.append("Локация %s: нет названия" % lid)
		var pos: Array = loc.get("pos", [])
		if pos.size() != 2:
			errors.append("Локация %s: pos должен быть [x, y]" % lid)
		for mid: String in loc.get("random", {}).get("pool", []):
			if not c.missions.has(mid):
				errors.append("Локация %s: в пуле нет миссии %s" % [lid, mid])
	for mid: String in c.missions:
		_validate_mission(c, mid, errors)


static func _validate_mission(c: Content, mid: String, errors: Array[String]) -> void:
	var m: Dictionary = c.missions[mid]
	var w := "Миссия %s" % mid
	if not c.locations.has(str(m.get("location", ""))):
		errors.append("%s: нет локации «%s»" % [w, m.get("location", "")])
	if not MISSION_TYPES.has(str(m.get("type", ""))):
		errors.append("%s: неизвестный тип «%s»" % [w, m.get("type", "")])
	for key: String in ["title", "briefing", "arrival"]:
		if str(m.get(key, "")) == "":
			errors.append("%s: пустое поле %s" % [w, key])
	var threat := int(m.get("threat", 0))
	if threat < 1 or threat > 5:
		errors.append("%s: угроза %d, нужно 1–5" % [w, threat])
	var dur := float(m.get("duration", 0))
	if dur < 5.0 or dur > 15.0:
		errors.append("%s: время в пути %s с, нужно 5–15" % [w, dur])
	var squad: Dictionary = m.get("squad", {})
	var smin := int(squad.get("min", 1))
	var smax := int(squad.get("max", 1))
	if smin < 1 or smax > 5 or smin > smax:
		errors.append("%s: мест в отряде %d–%d, нужно 1 ≤ min ≤ max ≤ 5" % [w, smin, smax])
	if m.has("trauma_pool") and not POOLS.has(m["trauma_pool"]):
		errors.append("%s: неизвестный пул травм" % w)
	for en: String in m.get("enemies", []):
		if not c.enemies.has(en):
			errors.append("%s: нет противника %s" % [w, en])
	if m.has("field") and not c.fields.has(str(m["field"])):
		errors.append("%s: нет поля боя %s" % [w, m["field"]])
	for t: String in Array(m.get("known_tags", [])) + Array(m.get("hidden_tags", [])):
		if not c.combat_tags.has(t):
			errors.append("%s: нет боевого тега «%s»" % [w, t])
	for t: String in m.get("context", []):
		if not c.tags.has(t):
			errors.append("%s: нет тега проверки «%s»" % [w, t])
	for r: Dictionary in m.get("rumors", []):
		var text := str(r.get("text", ""))
		if not (text.contains("[") and text.contains("]")):
			errors.append("%s: в слухе нет намёка в [скобках]: %s" % [w, text])
		var tag := str(r.get("tag", ""))
		if tag != "" and not c.combat_tags.has(tag) and not c.tags.has(tag):
			errors.append("%s: слух ссылается на неизвестный тег «%s»" % [w, tag])
	for nid: String in m.get("next", []):
		if not c.missions.has(nid):
			errors.append("%s: next → нет миссии %s" % [w, nid])

	var acts: Array = m.get("actions", [])
	var ids := {}
	var working := 0
	var story := 0
	for a: Dictionary in acts:
		var aid := str(a.get("id", ""))
		var aw := "%s / %s" % [w, aid]
		if aid == "" or ids.has(aid):
			errors.append("%s: пустой или повторный id действия" % aw)
		ids[aid] = true
		if str(a.get("label", "")) == "":
			errors.append("%s: нет названия действия" % aw)
		for t: String in a.get("requires_any", []):
			if not c.combat_tags.has(t):
				errors.append("%s: нет боевого тега «%s»" % [aw, t])
		if bool(a.get("story", false)):
			story += 1
		if bool(a.get("retreat", false)):
			continue
		working += 1
		var stages: Array = a.get("stages", [])
		if stages.is_empty() or stages.size() > 3:
			errors.append("%s: этапов %d, нужно 1–3" % [aw, stages.size()])
		for st: Dictionary in stages:
			_validate_stage(c, aw + " / " + str(st.get("name", "?")), st, errors)
		for key: String in ["on_success", "on_partial", "on_failure"]:
			_validate_effects(c, aw + " " + key, a.get(key, []), errors)
			for e: Dictionary in a.get(key, []):
				if str(e.get("resource", "")) == "mana":
					errors.append("%s %s: маны в миссиях нет (решение владельца)" % [aw, key])
	if working == 0:
		errors.append("%s: нет ни одного действия, кроме отступления" % w)
	if str(m.get("type", "")) == "story" and story == 0:
		errors.append("%s: у сюжетной миссии нет сюжетного действия" % w)


static func _validate_stage(c: Content, w: String, st: Dictionary, errors: Array[String]) -> void:
	if str(st.get("name", "")) == "":
		errors.append("%s: у этапа нет названия" % w)
	if st.has("combat"):
		var en: Array = st["combat"].get("enemies", [])
		if en.is_empty():
			errors.append("%s: бой без противников" % w)
		for e: String in en:
			if not c.enemies.has(e):
				errors.append("%s: нет противника %s" % [w, e])
		if st["combat"].has("field") and not c.fields.has(str(st["combat"]["field"])):
			errors.append("%s: нет поля боя %s" % [w, st["combat"]["field"]])
	elif not bool(st.get("auto", false)):
		var sum := 0
		for s: String in st.get("req", {}):
			if not STATS.has(s):
				errors.append("%s: неизвестная характеристика «%s»" % [w, s])
			sum += int(st["req"][s])
		if sum <= 0:
			errors.append("%s: у этапа нет требований — нужен req, combat или auto" % w)
	for t: String in st.get("tags", []):
		if not c.tags.has(t):
			errors.append("%s: нет тега проверки «%s»" % [w, t])
