class_name CoreRules
extends RefCounted
## Ядро души — уровни и ранги героев (docs/23; решения владельца 05.10).
## У каждого героя своё ядро. Осколки душ общие: их можно потратить в лавке, а можно в любой момент впитать в ядро
## героя (планшет героя). Ядро ранга насыщается за 5 уровней; каждый уровень — +1 к характеристике на выбор игрока.
## Полное ядро — на карте появляется «Испытание души» этого героя (бой один на один с Отражением следующего ранга).
## Победа — новый ранг (Спящий → Пробуждённый → Вознесённый): в бою враги этого ранга теперь равны герою (раньше
## враг рангом выше — в 1,6 раза сильнее) и +1 ко всем характеристикам; ядро нового ранга начинается с нуля.
## Погиб герой — его ядро потеряно. Состояние: state.characters[cid].core {rank, level, picks}.

const RANKS := ["Спящий", "Пробуждённый", "Вознесённый", "Трансцендентный"]
const LEVELS := 5
const MAX_RANK := 2   # пока испытания есть до Вознесённого
## цена уровня в осколках: [ранг][уровень]
const COST := [[6, 8, 10, 12, 14], [12, 15, 18, 22, 26], [20, 24, 28, 34, 40]]
const STATS := ["power", "will", "cunning"]


static func core(state: RunState, cid: String) -> Dictionary:
	var ch := state.character(cid)
	if not ch.has("core"):
		ch["core"] = {"rank": 0, "level": 0, "picks": 0}
	return ch["core"]


## Ранг героя в бою: больший из ранга ядра и ранга стадии (сюжетной).
static func rank(content: Content, state: RunState, cid: String) -> int:
	var c: Dictionary = content.characters.get(cid, {})
	var stage := str(state.character(cid).get("stage", ""))
	var base := int(c.get("stages", {}).get(stage, {}).get("rank", c.get("rank", 0)))
	return maxi(base, int(core(state, cid).get("rank", 0)))


static func rank_name(content: Content, state: RunState, cid: String) -> String:
	return RANKS[clampi(rank(content, state, cid), 0, RANKS.size() - 1)]


static func level(state: RunState, cid: String) -> int:
	return int(core(state, cid).get("level", 0))


static func full(state: RunState, cid: String) -> bool:
	return level(state, cid) >= LEVELS


## Цена следующего уровня (-1 — ядро полно или ранг последний).
static func next_cost(state: RunState, cid: String) -> int:
	var cr := core(state, cid)
	var r := int(cr.get("rank", 0))
	if full(state, cid) or r >= COST.size():
		return -1
	return int(COST[r][int(cr.get("level", 0))])


## Сколько уровней ждут выбора характеристики.
static func pending(state: RunState, cid: String) -> int:
	var cr := core(state, cid)
	return int(cr.get("level", 0)) + int(cr.get("rank", 0)) * LEVELS - int(cr.get("picks", 0))


## Впитать осколки в ядро: следующий уровень. {ok, error, entries}.
static func absorb(content: Content, state: RunState, cid: String) -> Dictionary:
	if not state.is_alive(cid) or not state.characters.has(cid):
		return {"ok": false, "error": "Героя нет в отряде", "entries": []}
	var cost := next_cost(state, cid)
	if cost < 0:
		return {"ok": false, "error": "Ядро полно — нужно пройти испытание души", "entries": []}
	var have := int(state.resources.get("shards", 0))
	if have < cost:
		return {"ok": false, "error": "Не хватает осколков душ: нужно %d, есть %d" % [cost, have], "entries": []}
	state.resources["shards"] = have - cost
	var cr := core(state, cid)
	cr["level"] = int(cr.get("level", 0)) + 1
	var out: Array = [{"kind": "core", "text": "%s впитывает осколки: ядро — уровень %d из %d" % [content.card_name(cid), int(cr["level"]), LEVELS]}]
	if full(state, cid):
		out.append_array(ensure_trials(content, state))
	return {"ok": true, "error": "", "entries": out}


## Выбрать характеристику за уровень: +1 навсегда. {ok, error}.
static func pick(content: Content, state: RunState, cid: String, stat: String) -> Dictionary:
	if pending(state, cid) <= 0 or not STATS.has(stat):
		return {"ok": false, "error": "Нечего выбирать"}
	var ch := state.character(cid)
	var perm: Dictionary = ch.get("perm", {})
	perm[stat] = int(perm.get(stat, 0)) + 1
	ch["perm"] = perm
	core(state, cid)["picks"] = int(core(state, cid).get("picks", 0)) + 1
	return {"ok": true, "error": ""}


## Испытание души героя в главе (id события; "" — нет такого).
static func trial_id(content: Content, state: RunState, cid: String) -> String:
	var r := int(core(state, cid).get("rank", 0))
	var mid := "TR%d_%s_%s" % [r + 1, state.chapter, cid]
	return mid if content.missions.has(mid) else ""


static func is_trial(content: Content, mid: String) -> bool:
	return str(content.missions.get(mid, {}).get("trial", "")) != ""


## У героев с полным ядром есть испытание в текущей главе (открывает недостающие). Записи.
static func ensure_trials(content: Content, state: RunState) -> Array:
	var out: Array = []
	for cid: String in MissionFlow.heroes(content, state):
		if not full(state, cid) or int(core(state, cid).get("rank", 0)) >= MAX_RANK:
			continue
		var mid := trial_id(content, state, cid)
		if mid == "" or str(state.missions.get(mid, {}).get("status", "")) in ["open", "active"]:
			continue
		MissionFlow.open(content, state, mid, true)
		out.append({"kind": "core_trial", "text": "Ядро %s полно — ждёт испытание души" % content.card_name(cid)})
	return out


## Победа в испытании: новый ранг, +1 ко всем характеристикам, ядро ранга — с нуля. Записи.
static func ascend(content: Content, state: RunState, cid: String) -> Array:
	var cr := core(state, cid)
	if not full(state, cid):
		return []
	cr["rank"] = int(cr.get("rank", 0)) + 1
	cr["level"] = 0
	var perm: Dictionary = state.character(cid).get("perm", {})
	for st: String in STATS:
		perm[st] = int(perm.get(st, 0)) + 1
	state.character(cid)["perm"] = perm
	return [{"kind": "core", "text": "%s — %s! Враги этого ранга теперь ему равны; +1 ко всем характеристикам" % [
		content.card_name(cid), RANKS[clampi(int(cr["rank"]), 0, RANKS.size() - 1)]]}]
