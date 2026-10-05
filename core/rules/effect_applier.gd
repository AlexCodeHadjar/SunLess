class_name EffectApplier
extends RefCounted
## Закрытый набор команд последствий (GDD 4.10). Сценарист пишет данные, не код.
## Каждая команда возвращает записи для экрана результата: {"kind", "text", "card"?}.

const STAT_NAMES := {"power": "Сила", "will": "Воля", "cunning": "Хитрость"}
const RES_NAMES := {"shards": "✧ осколки душ"}


static func apply_all(content: Content, state: RunState, effects: Array, executor: String,
		rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for e: Dictionary in effects:
		out.append_array(apply(content, state, e, executor, rng))
	return out


static func apply(content: Content, state: RunState, e: Dictionary, executor: String,
		rng: RandomNumberGenerator) -> Array:
	if e.has("if_flag") and not state.has_flag(str(e["if_flag"])):
		return []
	if e.has("unless_flag") and state.has_flag(str(e["unless_flag"])):
		return []
	var target: String = str(e.get("target", executor))
	match str(e.get("cmd", "")):
		"add_card":
			return add_card(content, state, str(e["card"]))
		"remove_card":
			var card: String = e["card"]
			# unless_bought: купленный в магазине спутник остаётся (решение владельца)
			if bool(e.get("unless_bought", false)) and bool(state.characters.get(card, {}).get("bought", false)):
				return []
			if state.owns(card):
				_remove_card(state, card)
				return [{"kind": "lost", "text": str(e.get("text", "%s покидает коллекцию" % content.card_name(card))), "card": card}]
		"add_ability":
			var cid: String = e.get("character", executor)
			var aid: String = e["ability"]
			var ch: Dictionary = state.character(cid)
			if not ch.is_empty() and not Array(ch["abilities"]).has(aid):
				ch["abilities"].append(aid)
				return [{"kind": "ability", "text": "Способность: %s" % content.card_name(aid), "card": aid}]
		"edge":
			# сюжет ставит героя на грань смерти (без броска: бросок — только при поражении на грани)
			if state.is_alive(target) and not EdgeRules.on_edge(state, target):
				state.character(target)["edge"] = true
				state.note(target, "На грани")
				return [{"kind": "edge", "card": target, "text": str(e.get("text", "%s — на грани смерти" % content.card_name(target)))}]
		"recover":
			var out: Array = []
			EdgeRules.recover(content, state, target, str(e.get("text", "раны затянулись")), out)
			return out
		"psyche":
			return PsycheRules.change(content, state, target, int(e.get("value", 0)), str(e.get("text", "")), [target], rng)
		"set_flag":
			state.flags[str(e["flag"])] = true
			if e.has("text"):
				return [{"kind": "flag", "text": str(e["text"])}]
		"clear_flag":
			state.flags.erase(str(e["flag"]))
		"adjust_resource":
			var r: String = e["resource"]
			var v := int(e["value"])
			state.resources[r] = clampi(int(state.resources.get(r, 0)) + v, 0, 999)
			return [{"kind": "resource", "text": "%s %+d" % [RES_NAMES.get(r, r), v]}]
		"add_temp":
			var te := {
				"stat": str(e["stat"]), "value": int(e["value"]),
				"tags": e.get("tags", []), "label": str(e.get("label", "Временный эффект")),
			}
			state.temp_effects.append(te)
			return [{"kind": "temp", "text": "%s: %+d %s" % [te["label"], te["value"], STAT_NAMES.get(te["stat"], te["stat"])]}]
		"add_perm":
			var ch4: Dictionary = state.character(str(e.get("character", target)))
			if not ch4.is_empty():
				var s: String = e["stat"]
				ch4["perm"][s] = int(ch4["perm"].get(s, 0)) + int(e["value"])
				return [{"kind": "perm", "text": "Навсегда: %+d %s" % [int(e["value"]), STAT_NAMES.get(s, s)]}]
		"set_stage":
			var cid2: String = e["character"]
			var ch5: Dictionary = state.character(cid2)
			if not ch5.is_empty():
				ch5["stage"] = str(e["stage"])
				return [{"kind": "stage", "text": "%s — новая стадия: %s" % [content.card_name(cid2), content.stage_name(cid2, str(e["stage"]))], "card": cid2}]
		"map_mark":
			# след на карте-плане (MapRules): разорено / после шторма — на N выполненных миссий
			return MapRules.mark(content, state, str(e["place"]), str(e.get("state", "ravaged")), int(e.get("missions", 3)))
		"mover":
			return MoverRules.command(content, state, e)
		"zone":
			return ZoneRules.command(content, state, e)
		"terrain":
			return TerrainRules.command(content, state, e)
		"threat":
			# прорывы и Врата (GateRules): закрыть, отложить, отбить рой, баррикада, потушить, оборона
			return GateRules.command(content, state, e)
		"emerge":
			# на свободной площадке поднимается место со своей встречей (Гнездовье после набега)
			return MapRules.emerge(content, state, str(e["place"]), rng, str(e.get("near", "")))
		"add_codex":
			var entry: String = e["entry"]
			if not state.codex.has(entry):
				state.codex.append(entry)
				return [{"kind": "codex", "text": "Кодекс: %s" % str(e.get("text", entry))}]
		"remove_temporaries":
			# временные спутники главы уходят; купленные в магазине остаются (решение владельца)
			var gone: Array = []
			var stay: Array = []
			for card2: String in state.collection.duplicate():
				if content.characters.get(card2, {}).get("status", "") != "temporary":
					continue
				if bool(state.characters.get(card2, {}).get("bought", false)):
					stay.append(content.card_name(card2))
				else:
					_remove_card(state, card2)
					gone.append(content.card_name(card2))
			var out2: Array = []
			if not gone.is_empty():
				out2.append({"kind": "lost", "text": "Уходят: %s" % ", ".join(gone)})
			if not stay.is_empty():
				out2.append({"kind": "card", "text": "Остаются с Санни: %s" % ", ".join(stay)})
			return out2
		"adjust_trust":
			var a2 := str(e.get("a", executor))
			return TrustRules.change(content, state, a2, str(e["b"]), int(e["value"]), str(e.get("text", "сюжет")))
		"reset_wear":
			# кузнец: самое изношенное усиление — снова как новое
			var worst := ""
			for c3: String in state.wear:
				if state.owns(c3) and (worst == "" or int(state.wear[c3]) > int(state.wear[worst])):
					worst = c3
			if worst == "" or int(state.wear[worst]) <= WearRules.START:
				return [{"kind": "info", "text": "Чинить нечего"}]
			state.wear[worst] = WearRules.START
			state.note(worst, "Кузнец снял износ")
			return [{"kind": "info", "text": "%s: износ сброшен до %d%%" % [content.card_name(worst), WearRules.START]}]
		"text":
			return [{"kind": "story", "text": str(e["text"])}]
		"core_rank":
			# испытание души пройдено (CoreRules, docs/23): новый ранг героя
			return CoreRules.ascend(content, state, str(e.get("character", executor)))
		"tide":
			# прилив Забытого Берега (TideRules): предупреждение → вода → отлив с новыми проходами
			return TideRules.schedule(content, state, int(e.get("warn", TideRules.WARN)), int(e.get("flood", TideRules.FLOOD)), str(e.get("text", "")))
		_:
			push_error("Неизвестная команда эффекта: %s" % str(e.get("cmd", "")))
	return []


static func add_card(content: Content, state: RunState, card: String) -> Array:
	if state.owns(card):
		return []
	state.collection.append(card)
	var kind := content.card_kind(card)
	if kind == "character":
		var d: Dictionary = content.characters[card]
		if not state.characters.has(card):
			state.characters[card] = {
				"stage": str(d.get("start_stage", "")),
				"edge": false,
				"perm": {"power": 0, "will": 0, "cunning": 0},
				"abilities": Array(d.get("start_abilities", [])).duplicate(),
				"alive": true,
			}
		else:
			state.characters[card]["alive"] = true
	elif kind == "enhancement" and bool(content.enhancements[card].get("wears", true)):
		state.wear[card] = WearRules.START
	state.note(card, "Карта получена")
	return [{"kind": "card", "text": "Получено: %s" % content.card_name(card), "card": card}]


static func _remove_card(state: RunState, card: String) -> void:
	state.collection.erase(card)
	state.note(card, "Покинула коллекцию")
	# режим миссий: ушедший герой покидает отряд в пути, его кармашек пустеет
	if state.characters.has(card):
		state.characters[card]["pocket"] = []
		state.rest_until.erase(card)
		for sq: Dictionary in state.squads.duplicate():
			var hs: Array = sq.get("heroes", [])
			if hs.has(card):
				hs.erase(card)
				if hs.is_empty():
					state.squads.erase(sq)
					var st: Dictionary = state.missions.get(str(sq.get("mission", "")), {})
					if not st.is_empty():
						st["status"] = "open"
