class_name ContentValidator
extends RefCounted
## Проверка данных до запуска (GDD 8.5). Возвращает список ошибок; пусто — всё в порядке.

const KNOWN_CMDS := ["add_card", "remove_card", "add_ability", "edge", "recover", "psyche",
	"set_flag", "clear_flag", "adjust_resource", "add_temp", "add_perm", "set_stage", "add_codex",
	"remove_temporaries", "text", "reset_wear", "adjust_trust", "tide", "map_mark", "emerge"]
const KNOWN_CONDITIONS := ["in_collection", "not_owned", "executor_is", "has_flag", "not_flag", "owned_count",
	"attached", "executor_on_edge"]
const STATS := ["power", "will", "cunning"]


static func validate(c: Content) -> Array[String]:
	var errors: Array[String] = []
	errors.append_array(c.load_errors)
	_validate_combat(c, errors)
	_validate_missions(c, errors)
	_validate_modifiers(c, errors)
	_validate_loot(c, errors)
	_validate_deck(c, errors)
	_validate_maps(c, errors)
	return errors


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
		if e.has("stat") and not STATS.has(str(e["stat"])):
			errors.append("%s: неизвестная характеристика %s" % [where, e["stat"]])
		if cmd == "set_stage":
			var ch: Dictionary = c.characters.get(str(e.get("character", "")), {})
			if not ch.get("stages", {}).has(str(e.get("stage", ""))):
				errors.append("%s: нет стадии %s" % [where, e.get("stage", "")])


## Боевые данные: все теги связей, полей, карт раунда и носителей существуют.
static func _validate_loot(c: Content, errors: Array[String]) -> void:
	for tier: String in c.loot.get("tiers", {}):
		if not LootRules.TIERS.has(tier):
			errors.append("loot.json: неизвестный уровень источника «%s»" % tier)
		for r: String in c.loot["tiers"][tier]:
			if not LootRules.RARITY_ORDER.has(r):
				errors.append("loot.json: %s — неизвестная редкость «%s»" % [tier, r])
	for mid: String in c.missions:
		var mem := str(c.missions[mid].get("memory", ""))
		if mem != "" and not LootRules.TIERS.has(mem):
			errors.append("%s: memory — неизвестный уровень «%s»" % [mid, mem])
	for id: String in c.enhancements:
		var e: Dictionary = c.enhancements[id]
		if bool(e.get("loot", false)) and not LootRules.RARITY_ORDER.has(str(e.get("rarity", ""))):
			errors.append("%s: у добычи неизвестная редкость «%s»" % [id, e.get("rarity", "")])


## Карты-планы (docs/16 §11.6): места есть в locations, рисунки лежат на месте, площадки и проходы в порядке.
static func _validate_maps(c: Content, errors: Array[String]) -> void:
	for region: String in c.maps:
		var m: Dictionary = c.maps[region]
		var art := str(m.get("art", ""))
		for key: String in ["base", "height", "water", "fog"]:
			if not ResourceLoader.exists(art + str(m.get(key, ""))):
				errors.append("maps/%s: нет файла %s" % [region, m.get(key, "")])
		var places: Dictionary = m.get("places", {})
		for lid: String in places:
			if not c.locations.has(lid) and not c.shops.has(lid):
				errors.append("maps/%s: место %s не описано в locations.json или shops.json" % [region, lid])
			for st: String in places[lid].get("states", ["dry"]):
				if not ResourceLoader.exists("%s%s_%s.webp" % [art, lid, st]):
					errors.append("maps/%s: нет виньетки %s_%s" % [region, lid, st])
		for lid: String in m.get("variants", {}):
			for v: String in m["variants"][lid]:
				if not Array(places.get(lid, {}).get("states", [])).has(v):
					errors.append("maps/%s: вариант %s у %s не в списке состояний" % [region, v, lid])
		for lid: String in c.locations:
			if str(c.locations[lid].get("region", "")) == region and not places.has(lid):
				errors.append("maps/%s: у места %s нет точки на карте" % [region, lid])
			if bool(c.locations[lid].get("emerge", false)) and m.get("sockets", []).is_empty():
				errors.append("maps/%s: появляющемуся месту %s негде встать — нет площадок" % [region, lid])
		for pair: Array in m.get("paths", []):
			for lid: String in pair:
				if not places.has(lid):
					errors.append("maps/%s: тропа ведёт в неизвестное место %s" % [region, lid])
	errors.append_array(dry_spine_errors(c))


## Карта без тупиков (docs/17 §2): все постоянные места связаны тропами; высоты и лавки связаны между собой
## без низин и средних мест — в любой прилив от любой высоты можно дойти до любой другой.
static func dry_spine_errors(c: Content) -> Array[String]:
	var out: Array[String] = []
	for region: String in c.maps:
		var m: Dictionary = c.maps[region]
		var places: Dictionary = m.get("places", {})
		var all: Array = []
		var dry: Array = []
		for lid: String in places:
			if c.shops.has(lid):
				all.append(lid)
				dry.append(lid)
			elif c.locations.has(lid) and not bool(c.locations[lid].get("emerge", false)):
				all.append(lid)
				if str(c.locations[lid].get("height", "")) == "high":
					dry.append(lid)
		for pair: Array in [[all, "все места"], [dry, "высоты и лавки (в прилив)"]]:
			var nodes: Array = pair[0]
			if nodes.size() < 2:
				continue
			var seen := {nodes[0]: true}
			var queue: Array = [nodes[0]]
			while not queue.is_empty():
				var cur: String = queue.pop_front()
				for e: Array in m.get("paths", []):
					for k in 2:
						if str(e[k]) == cur and nodes.has(str(e[1 - k])) and not seen.has(str(e[1 - k])):
							seen[str(e[1 - k])] = true
							queue.append(str(e[1 - k]))
			for lid: String in nodes:
				if not seen.has(lid):
					out.append("maps/%s: тупик — %s: место %s не связано тропами с %s" % [region, pair[1], lid, nodes[0]])
	return out


## Колода событий (docs/16 §11.4): миссии существуют, из своей главы, не повторяются; pick не больше единиц.
static func _validate_deck(c: Content, errors: Array[String]) -> void:
	var seen := {}
	for ch: String in c.deck:
		if ch.begins_with("_"):
			continue
		for g: Dictionary in DeckRules.groups(c, ch):
			var units: Array = g.get("units", [])
			var chains := units.filter(func(u: Variant) -> bool: return DeckRules.unit(u)["chain"]).size()
			if int(g.get("pick", 0)) > units.size() or int(g.get("pick", 0)) < 1:
				errors.append("deck.json: %s/%s — pick %s при %d единицах" % [ch, g.get("name", ""), g.get("pick", 0), units.size()])
			if int(g.get("min_chains", 0)) > mini(chains, int(g.get("pick", 0))):
				errors.append("deck.json: %s/%s — min_chains больше, чем цепочек" % [ch, g.get("name", "")])
			for u: Variant in units:
				for mid: String in DeckRules.unit(u)["missions"]:
					if not c.missions.has(mid):
						errors.append("deck.json: %s — нет миссии %s" % [ch, mid])
					elif MissionFlow.chapter_of(c, mid) != ch:
						errors.append("deck.json: %s — миссия %s из другой главы" % [ch, mid])
					if seen.has(mid):
						errors.append("deck.json: миссия %s в колоде дважды" % mid)
					seen[mid] = true


static func _validate_modifiers(c: Content, errors: Array[String]) -> void:
	var seen := {}
	for d: Dictionary in c.modifiers.get("list", []):
		var id := str(d.get("id", ""))
		if id == "" or seen.has(id):
			errors.append("modifiers.json: пустой или повторный id «%s»" % id)
		seen[id] = true
		for t: String in Array(d.get("enemy_tags", [])) + Array(d.get("field_tags", [])):
			if not c.combat_tags.has(t):
				errors.append("modifiers.json: %s — нет боевого тега «%s»" % [id, t])
		for b: Dictionary in d.get("check", []):
			if not STATS.has(str(b.get("stat", ""))):
				errors.append("modifiers.json: %s — неизвестная характеристика %s" % [id, b.get("stat", "")])


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


## Миссии и локации (docs/15, ветка gameplay/missions).
const MISSION_TYPES := ["story", "side", "random", "onslaught"]


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
	for sid: String in c.shops:
		_validate_shop(c, sid, errors)
	for bid: String in c.bonds:
		var b: Dictionary = c.bonds[bid]
		var pair: Array = b.get("heroes", [])
		if pair.size() != 2 or not c.characters.has(str(pair[0])) or not c.characters.has(str(pair[1])):
			errors.append("Связка %s: нужны два существующих героя" % bid)
		var st: Dictionary = b.get("effect", {}).get("stat", {})
		if not st.is_empty() and not STATS.has(str(st.get("stat", ""))):
			errors.append("Связка %s: неизвестная характеристика" % bid)
	# сюжетные окна (docs/16 §9е)
	for ch: String in c.story:
		var pages: Array = c.story[ch].get("pages", [])
		if pages.is_empty():
			errors.append("Сюжет %s: нет страниц" % ch)
		for p: Dictionary in pages:
			if str(p.get("text", "")) == "" or str(p.get("title", "")) == "":
				errors.append("Сюжет %s: у страницы нет заголовка или текста" % ch)
			if not ["left", "right"].has(str(p.get("side", "left"))):
				errors.append("Сюжет %s: side — left или right" % ch)
			if not ResourceLoader.exists(str(p.get("image", ""))):
				errors.append("Сюжет %s: нет картинки %s" % [ch, p.get("image", "")])
	# особые навыки карт (docs/16 §9д)
	for id: String in c.enhancements.keys() + c.abilities.keys():
		var m: Dictionary = c.enhancements.get(id, c.abilities.get(id, {})).get("memory", {})
		if m.is_empty():
			continue
		if not ["round", "lose"].has(str(m.get("phase", "round"))):
			errors.append("Навык %s: неизвестная фаза %s" % [id, m.get("phase", "")])
		var w: Dictionary = m.get("when", {})
		var e: Dictionary = m.get("effect", {})
		var tags: Array = Array(w.get("enemy_any", [])) + Array(w.get("env_any", [])) + Array(w.get("hero_any", []))
		for alt: Dictionary in w.get("any_of", []):
			tags += Array(alt.get("enemy_any", [])) + Array(alt.get("env_any", [])) + Array(alt.get("hero_any", []))
		for k: String in ["add_tags", "cancel_enemy_tags", "double_tags", "blocked_by_env", "self_tags"]:
			tags += Array(e.get(k, []))
		tags += Array(e.get("enemy_penalty", {}).get("tags", []))
		for t: String in tags:
			if not c.combat_tags.has(t):
				errors.append("Навык %s: нет тега «%s»" % [id, t])
	# натиск Кошмара (docs/16 §9)
	for oid: String in c.onslaught:
		for nm: String in c.onslaught[oid].get("pool", []):
			if str(c.missions.get(nm, {}).get("type", "")) != "onslaught":
				errors.append("Натиск %s: %s — не миссия type onslaught" % [oid, nm])
		if Array(c.onslaught[oid].get("every", [])).size() != 2:
			errors.append("Натиск %s: every должен быть [от, до]" % oid)
	# рост тегов (docs/16 §8)
	var ctx_ids: Array = []
	for t: String in c.tags:
		ctx_ids.append(t)
	for tag: String in c.tag_growth:
		var g: Dictionary = c.tag_growth[tag]
		var w := "Рост тега «%s»" % tag
		for how: String in g.get("grow", []):
			if not ["check", "combat", "panic", "any"].has(how):
				errors.append("%s: неизвестный способ роста %s" % [w, how])
		for ct: String in g.get("check_tags", []):
			if not ctx_ids.has(ct):
				errors.append("%s: неизвестный тег проверки %s" % [w, ct])
		for kind: String in ["evo", "mut"]:
			var e: Dictionary = g.get(kind, {})
			if str(e.get("name", "")) == "":
				errors.append("%s: нет %s" % [w, "эволюции" if kind == "evo" else "мутации"])
			for b2: Dictionary in Array(e.get("check", [])) + Array(e.get("check_night", [])):
				if not STATS.has(str(b2.get("stat", ""))):
					errors.append("%s: неизвестная характеристика" % w)


static func _validate_shop(c: Content, sid: String, errors: Array[String]) -> void:
	var sh: Dictionary = c.shops[sid]
	var w := "Магазин %s" % sid
	for sv: String in sh.get("services", []):
		if not ServiceRules.NAMES.has(sv):
			errors.append("%s: неизвестная услуга %s" % [w, sv])
	if str(sh.get("name", "")) == "":
		errors.append("%s: нет названия" % w)
	if Array(sh.get("pos", [])).size() != 2:
		errors.append("%s: pos должен быть [x, y]" % w)
	if not _chapter_has_locations(c, str(sh.get("chapter", ""))):
		errors.append("%s: неизвестная глава «%s»" % [w, sh.get("chapter", "")])
	if int(sh.get("slots", 0)) < 1:
		errors.append("%s: slots должен быть не меньше 1" % w)
	if int(sh.get("refresh_every", 0)) < 1:
		errors.append("%s: refresh_every должен быть не меньше 1" % w)
	var stock: Array = sh.get("stock", [])
	if stock.is_empty():
		errors.append("%s: пустой stock" % w)
	for it: Dictionary in stock:
		var card := str(it.get("card", ""))
		var kind := c.card_kind(card)
		if kind != "character" and kind != "enhancement":
			errors.append("%s: в продаже может быть только персонаж или усиление, а не «%s»" % [w, card])
		if it.has("price") and int(it["price"]) < 1:
			errors.append("%s: у %s цена меньше 1" % [w, card])


static func _chapter_has_locations(c: Content, chapter: String) -> bool:
	for lid: String in c.locations:
		if str(c.locations[lid].get("chapter", "")) == chapter:
			return true
	return false


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
	if m.has("trauma_pool"):
		errors.append("%s: пула травм больше нет (грань смерти, docs/16 §9е)" % w)
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
	for cid: String in m.get("requires_heroes", []):
		if not c.characters.has(cid):
			errors.append("%s: requires_heroes → нет персонажа %s" % [w, cid])
		elif Array(m.get("exclude_heroes", [])).has(cid):
			errors.append("%s: %s и обязателен, и исключён" % [w, cid])
	if Array(m.get("requires_heroes", [])).size() > int(squad.get("max", 1)):
		errors.append("%s: обязательных героев больше, чем мест в отряде" % w)
	for cid: String in m.get("exclude_heroes", []):
		if not c.characters.has(cid):
			errors.append("%s: exclude_heroes → нет персонажа %s" % [w, cid])
	_validate_effects(c, w + " on_complete", m.get("on_complete", []), errors)
	_validate_effects(c, w + " on_expire", m.get("on_expire", []), errors)
	if str(m.get("type", "")) == "onslaught" and not m.has("expires"):
		errors.append("%s: у натиска должен быть срок expires" % w)
	for other: String in m.get("exclusive", []):
		if not c.missions.has(other):
			errors.append("%s: exclusive → нет миссии %s" % [w, other])
		elif not Array(c.missions[other].get("exclusive", [])).has(mid):
			errors.append("%s: миссия-выбор с %s должна быть взаимной" % [w, other])
	if m.has("expires") and (float(m["expires"]) < 1.0 or float(m["expires"]) > 10.0 or str(m.get("type", "")) == "story"):
		errors.append("%s: expires — только у побочных и случайных, 1–10 дней" % w)
	for ph: Dictionary in m.get("boss", {}).get("phases", []):
		if ph.has("field") and not c.fields.has(str(ph["field"])):
			errors.append("%s: у захода босса нет поля %s" % [w, ph["field"]])
		if ph.has("sky") and not ["eclipse", "blood_moon", "storm"].has(str(ph["sky"])):
			errors.append("%s: у захода босса неизвестное небо %s" % [w, ph["sky"]])
	if m.has("sky") and not ["eclipse", "blood_moon", "storm"].has(str(m["sky"])):
		errors.append("%s: небо «%s» — бывает только eclipse, blood_moon или storm" % [w, m["sky"]])
	for other: String in m.get("unlock", {}).get("after_all", []):
		if not c.missions.has(other):
			errors.append("%s: unlock.after_all → нет миссии %s" % [w, other])
	if m.has("next_chapter") and not _chapter_has_locations(c, str(m["next_chapter"])):
		errors.append("%s: next_chapter → у главы «%s» нет мест на карте" % [w, m["next_chapter"]])

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
		for cid: String in a.get("requires_hero", []):
			if not c.characters.has(cid):
				errors.append("%s: requires_hero → нет персонажа %s" % [aw, cid])
		var tneed: Dictionary = a.get("requires_trust", {})
		for cid: String in tneed.get("pair", []):
			if not c.characters.has(cid):
				errors.append("%s: requires_trust → нет персонажа %s" % [aw, cid])
		for cond: Dictionary in a.get("conditions", []):
			if not KNOWN_CONDITIONS.has(str(cond.get("type", ""))):
				errors.append("%s: неизвестное условие «%s»" % [aw, cond.get("type", "")])
			for card: String in Array(cond.get("ids", [])) + Array(cond.get("cards", [])) + ([str(cond["card"])] if cond.has("card") else []):
				if c.card_kind(card) == "":
					errors.append("%s: условие ссылается на несуществующую карту %s" % [aw, card])
		var cost: Dictionary = a.get("cost", {})
		for r: String in cost:
			if not ["shards", "sacrifice", "sacrifice_tag", "rest", "edge"].has(r):
				errors.append("%s: неизвестная цена «%s» (shards, sacrifice, sacrifice_tag, rest, edge)" % [aw, r])
		if cost.has("sacrifice") and c.card_kind(str(cost["sacrifice"])) != "enhancement":
			errors.append("%s: жертвовать можно только усиление, а не %s" % [aw, cost["sacrifice"]])
		if cost.has("sacrifice_tag") and not c.combat_tags.has(str(cost["sacrifice_tag"])):
			errors.append("%s: нет тега «%s» для жертвы" % [aw, cost["sacrifice_tag"]])
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
				if e.has("resource") and str(e["resource"]) != "shards":
					errors.append("%s %s: ресурс может быть только осколками душ (маны нет — решение владельца)" % [aw, key])
	if working == 0:
		errors.append("%s: нет ни одного действия, кроме отступления" % w)
	if str(m.get("type", "")) == "story" and story == 0:
		errors.append("%s: у сюжетной миссии нет сюжетного действия" % w)


static func _validate_stage(c: Content, w: String, st: Dictionary, errors: Array[String]) -> void:
	if str(st.get("name", "")) == "":
		errors.append("%s: у этапа нет названия" % w)
	if st.has("watch"):
		var wt: Dictionary = st["watch"]
		if not c.characters.has(str(wt.get("hero", ""))):
			errors.append("%s: смотр — нет героя %s" % [w, wt.get("hero", "")])
		for we: String in wt.get("enemies", []):
			if not c.enemies.has(we):
				errors.append("%s: смотр — нет противника %s" % [w, we])
		return
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
	if st.has("fork"):
		var f: Dictionary = st["fork"]
		if str(f.get("text", "")) == "":
			errors.append("%s: у развилки нет текста" % w)
		var opts: Array = f.get("options", [])
		if opts.size() < 2:
			errors.append("%s: у развилки меньше двух вариантов" % w)
		for o: Dictionary in opts:
			if str(o.get("id", "")) == "" or str(o.get("label", "")) == "":
				errors.append("%s: у варианта развилки нет id или названия" % w)
			if not ["continue", "retreat"].has(str(o.get("then", "continue"))):
				errors.append("%s: then у развилки — continue или retreat" % w)
			for st2: Dictionary in o.get("stages", []):
				_validate_stage(c, w + " / " + str(o.get("id", "")), st2, errors)
			_validate_effects(c, w + " fork on_success", o.get("on_success", []), errors)
			_validate_effects(c, w + " fork keep", o.get("keep", []), errors)