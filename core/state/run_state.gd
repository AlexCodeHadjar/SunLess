class_name RunState
extends RefCounted
## Состояние одного прохождения. Хранит только ID и изменяемые значения —
## тексты и числа карт живут в Content (data/*.json).

const SAVE_VERSION := 1

var week: int = 1
var arc: String = ""
var region: String = ""
var resources: Dictionary = {"coins": 10, "mana": 10}
## ID карт в нижней панели: персонажи, усиления, знания, инициаторы.
var collection: Array = []
## character_id -> {stage, traumas:[], perm:{power,will,cunning}, abilities:[], alive}
var characters: Dictionary = {}
## enhancement_id -> текущий шанс поломки, %
var wear: Dictionary = {}
var flags: Dictionary = {}
## event_id -> {status: "active"|"closed", done_options:[], spawned_week}
var events: Dictionary = {}
## option_id, последствия которых раскрыты
var revealed: Array = []
## [{stat, value, tags, event_id, option_id, remaining, label}]
var temp_effects: Array = []
## {event_id, weeks_left} — сюжетное событие «в пути»; пусто, если ничего не ждём
var pending_story: Dictionary = {}
## region -> [event_id] — уже выпавшие случайные события текущего круга пула
var random_used: Dictionary = {}
## event_id -> {character: String, enhancements: []}
var drafts: Dictionary = {}
var codex: Array = []
var log: Array = []
var game_over: bool = false
var demo_complete: bool = false
var rng_seed: int = 0
var rng_state: int = 0


func to_dict() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"week": week,
		"arc": arc,
		"region": region,
		"resources": resources.duplicate(true),
		"collection": collection.duplicate(true),
		"characters": characters.duplicate(true),
		"wear": wear.duplicate(true),
		"flags": flags.duplicate(true),
		"events": events.duplicate(true),
		"revealed": revealed.duplicate(true),
		"temp_effects": temp_effects.duplicate(true),
		"pending_story": pending_story.duplicate(true),
		"random_used": random_used.duplicate(true),
		"drafts": drafts.duplicate(true),
		"codex": codex.duplicate(true),
		"log": log.duplicate(true),
		"game_over": game_over,
		"demo_complete": demo_complete,
		# RNG хранится строкой: JSON теряет точность больших целых.
		"rng_seed": str(rng_seed),
		"rng_state": str(rng_state),
	}


static func from_dict(d: Dictionary) -> RunState:
	var s := RunState.new()
	s.week = int(d.get("week", 1))
	s.arc = str(d.get("arc", ""))
	s.region = str(d.get("region", ""))
	s.resources = _ints(d.get("resources", {}))
	s.collection = Array(d.get("collection", [])).duplicate(true)
	s.characters = Dictionary(d.get("characters", {})).duplicate(true)
	for cid: String in s.characters:
		var c: Dictionary = s.characters[cid]
		c["perm"] = _ints(c.get("perm", {}))
	s.wear = _ints(d.get("wear", {}))
	s.flags = Dictionary(d.get("flags", {})).duplicate(true)
	s.events = Dictionary(d.get("events", {})).duplicate(true)
	for eid: String in s.events:
		s.events[eid]["spawned_week"] = int(s.events[eid].get("spawned_week", 0))
	s.revealed = Array(d.get("revealed", [])).duplicate(true)
	s.temp_effects = Array(d.get("temp_effects", [])).duplicate(true)
	for e: Dictionary in s.temp_effects:
		e["value"] = int(e.get("value", 0))
		e["remaining"] = int(e.get("remaining", 1))
	s.pending_story = Dictionary(d.get("pending_story", {})).duplicate(true)
	if s.pending_story.has("weeks_left"):
		s.pending_story["weeks_left"] = int(s.pending_story["weeks_left"])
	s.random_used = Dictionary(d.get("random_used", {})).duplicate(true)
	s.drafts = Dictionary(d.get("drafts", {})).duplicate(true)
	s.codex = Array(d.get("codex", [])).duplicate(true)
	s.log = Array(d.get("log", [])).duplicate(true)
	for entry: Dictionary in s.log:
		for k: String in ["week", "chance", "roll"]:
			if entry.has(k):
				entry[k] = int(entry[k])
	s.game_over = bool(d.get("game_over", false))
	s.demo_complete = bool(d.get("demo_complete", false))
	s.rng_seed = int(str(d.get("rng_seed", "0")))
	s.rng_state = int(str(d.get("rng_state", "0")))
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

func owns(card_id: String) -> bool:
	return collection.has(card_id)


func character(cid: String) -> Dictionary:
	return characters.get(cid, {})


func is_alive(cid: String) -> bool:
	return bool(characters.get(cid, {}).get("alive", false))


func active_event_ids() -> Array:
	var out: Array = []
	for eid: String in events:
		if events[eid].get("status", "") == "active":
			out.append(eid)
	return out


func is_event_active(eid: String) -> bool:
	return events.has(eid) and events[eid].get("status", "") == "active"


func is_option_done(eid: String, oid: String) -> bool:
	return events.has(eid) and Array(events[eid].get("done_options", [])).has(oid)


func has_flag(flag: String) -> bool:
	return bool(flags.get(flag, false))


func draft_for(eid: String) -> Dictionary:
	return drafts.get(eid, {"character": "", "enhancements": []})


## Где сейчас стоит карта в черновике (для метки «Черновик: E03»).
func draft_event_of(card_id: String) -> String:
	for eid: String in drafts:
		var d: Dictionary = drafts[eid]
		if d.get("character", "") == card_id or Array(d.get("enhancements", [])).has(card_id):
			return eid
	return ""
