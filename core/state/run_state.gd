class_name RunState
extends RefCounted
## Состояние одного прохождения. Хранит только ID и изменяемые значения —
## тексты и числа карт живут в Content (data/*.json).

const SAVE_VERSION := 2   # 2 — режим миссий (docs/15); сохранения прежнего режима по неделям не читаются

var region: String = ""
var resources: Dictionary = {"shards": 10}
## ID карт в руке игрока: персонажи, усиления, травмы.
var collection: Array = []
## character_id -> {stage, traumas:[], perm:{power,will,cunning}, abilities:[], alive, pocket:[]}
var characters: Dictionary = {}
## enhancement_id -> текущий шанс поломки, %
var wear: Dictionary = {}
var flags: Dictionary = {}
## [{stat, value, tags, label}] — временные бонусы до первого использования
var temp_effects: Array = []
var codex: Array = []
## раны врага: сохраняются до следующей попытки миссии (ключ — id миссии)
var enemy_wounds: Dictionary = {}
var log: Array = []
var card_log: Array = []   # [{t, card, text, seq}] — отметки карт для «В вашем прохождении»
var game_over: bool = false
var demo_complete: bool = false   # глава с end_chapter пройдена; next_chapter — во flags
var rng_seed: int = 0
var rng_state: int = 0
var chapter: String = ""            # текущая глава: nightmare, academy…
var mode: String = "missions"
var clock: float = 0.0              # игровые секунды (идут только в игре)
## mission_id -> {status: "open"|"active"|"done", attempts, opened_at}
var missions: Dictionary = {}
## [{id, mission, heroes:[], launched_at, arrive_at, phase: "travel"|"arrived"}]
var squads: Array = []
var next_squad: int = 1
## character_id -> игровое время, до которого герой отдыхает
var rest_until: Dictionary = {}
var completed_missions: int = 0
## location_id -> игровое время следующей случайной миссии
var loc_timers: Dictionary = {}
## shop_id -> {gen, items: [{card, price, sold}], seen} — ассортимент магазинов (ShopRules)
var shops: Dictionary = {}
## "a|b" (по алфавиту) -> доверие −5…+5 и причина последнего изменения (TrustRules)
var trust: Dictionary = {}
var trust_notes: Dictionary = {}
## card -> глава, в которой усиление заточено у торговца (ServiceRules)
var sharpened: Dictionary = {}
## лагерь: {beds: [cid], heal: {cid: секунд}} (CampRules)
var camp: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"region": region,
		"resources": resources.duplicate(true),
		"collection": collection.duplicate(true),
		"characters": characters.duplicate(true),
		"wear": wear.duplicate(true),
		"flags": flags.duplicate(true),
		"temp_effects": temp_effects.duplicate(true),
		"codex": codex.duplicate(true),
		"enemy_wounds": enemy_wounds.duplicate(true),
		"log": log.duplicate(true),
		"card_log": card_log.duplicate(true),
		"game_over": game_over,
		"demo_complete": demo_complete,
		# RNG хранится строкой: JSON теряет точность больших целых.
		"rng_seed": str(rng_seed),
		"rng_state": str(rng_state),
		"chapter": chapter,
		"mode": mode,
		"clock": clock,
		"missions": missions.duplicate(true),
		"squads": squads.duplicate(true),
		"next_squad": next_squad,
		"rest_until": rest_until.duplicate(true),
		"completed_missions": completed_missions,
		"loc_timers": loc_timers.duplicate(true),
		"shops": shops.duplicate(true),
		"trust": trust.duplicate(true),
		"trust_notes": trust_notes.duplicate(true),
		"sharpened": sharpened.duplicate(true),
		"camp": camp.duplicate(true),
	}


static func from_dict(d: Dictionary) -> RunState:
	var s := RunState.new()
	s.region = str(d.get("region", ""))
	s.resources = _ints(d.get("resources", {}))
	s.resources.erase("mana")
	s.collection = Array(d.get("collection", [])).duplicate(true)
	s.characters = Dictionary(d.get("characters", {})).duplicate(true)
	for cid: String in s.characters:
		var c: Dictionary = s.characters[cid]
		c["perm"] = _ints(c.get("perm", {}))
	s.wear = _ints(d.get("wear", {}))
	s.flags = Dictionary(d.get("flags", {})).duplicate(true)
	s.temp_effects = Array(d.get("temp_effects", [])).duplicate(true)
	for e: Dictionary in s.temp_effects:
		e["value"] = int(e.get("value", 0))
	s.codex = Array(d.get("codex", [])).duplicate(true)
	s.enemy_wounds = _ints(d.get("enemy_wounds", {}))
	s.log = Array(d.get("log", [])).duplicate(true)
	s.card_log = Array(d.get("card_log", [])).duplicate(true)
	for n: Dictionary in s.card_log:
		n["seq"] = int(n.get("seq", 0))
		n["t"] = float(n.get("t", 0.0))
	s.game_over = bool(d.get("game_over", false))
	s.demo_complete = bool(d.get("demo_complete", false))
	s.rng_seed = int(str(d.get("rng_seed", "0")))
	s.rng_state = int(str(d.get("rng_state", "0")))
	s.chapter = str(d.get("chapter", ""))
	s.mode = str(d.get("mode", "missions"))
	s.clock = float(d.get("clock", 0.0))
	s.missions = Dictionary(d.get("missions", {})).duplicate(true)
	for mid: String in s.missions:
		s.missions[mid]["attempts"] = int(s.missions[mid].get("attempts", 0))
	s.squads = Array(d.get("squads", [])).duplicate(true)
	for sq: Dictionary in s.squads:
		sq["id"] = int(sq.get("id", 0))
	s.next_squad = int(d.get("next_squad", 1))
	s.rest_until = Dictionary(d.get("rest_until", {})).duplicate(true)
	for cid: String in s.rest_until:
		s.rest_until[cid] = float(s.rest_until[cid])
	s.completed_missions = int(d.get("completed_missions", 0))
	s.loc_timers = Dictionary(d.get("loc_timers", {})).duplicate(true)
	s.trust = _ints(d.get("trust", {}))
	s.trust_notes = Dictionary(d.get("trust_notes", {})).duplicate(true)
	s.sharpened = Dictionary(d.get("sharpened", {})).duplicate(true)
	s.camp = Dictionary(d.get("camp", {})).duplicate(true)
	s.shops = Dictionary(d.get("shops", {})).duplicate(true)
	for sid: String in s.shops:
		s.shops[sid]["gen"] = int(s.shops[sid].get("gen", 0))
		s.shops[sid]["seen"] = int(s.shops[sid].get("seen", -1))
		for it: Dictionary in s.shops[sid].get("items", []):
			it["price"] = int(it.get("price", 0))
	return s


func copy() -> RunState:
	return RunState.from_dict(to_dict())


static func _ints(src: Variant) -> Dictionary:
	var out := {}
	if src is Dictionary:
		for k: Variant in src:
			out[str(k)] = int(src[k])
	return out


# --- удобные запросы -------------------------------------------------------

## Отметка в журнале карты (получение, травма, поломка, гибель).
func note(card_id: String, text: String) -> void:
	card_log.append({"t": clock, "card": card_id, "text": text, "seq": log.size()})


func owns(card_id: String) -> bool:
	return collection.has(card_id)


func character(cid: String) -> Dictionary:
	return characters.get(cid, {})


func is_alive(cid: String) -> bool:
	return bool(characters.get(cid, {}).get("alive", false))


func has_flag(flag: String) -> bool:
	return bool(flags.get(flag, false))

