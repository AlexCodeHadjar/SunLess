class_name Content
extends RefCounted
## Неизменяемые описания карт и событий, загруженные из data/*.json.

var characters: Dictionary = {}
var enhancements: Dictionary = {}
var abilities: Dictionary = {}
var traumas: Dictionary = {}
var initiators: Dictionary = {}
var events: Dictionary = {}
var regions: Dictionary = {}
var tags: Dictionary = {}
var thoughts: Dictionary = {}
# бой
var combat_tags: Dictionary = {}
var synergies: Dictionary = {}
var conflicts: Dictionary = {}
var fields: Dictionary = {}
var round_cards: Dictionary = {}
var enemies: Dictionary = {}
var tactics: Dictionary = {}
var enemy_abilities: Dictionary = {}
var lore: Dictionary = {}          # сюжетные описания «По книге» (tools/gen_lore.py)
var load_errors: Array[String] = []


static func load_from(dir: String = "res://data") -> Content:
	var c := Content.new()
	c.characters = c._load_map(dir + "/characters.json")
	c.enhancements = c._load_map(dir + "/enhancements.json")
	c.abilities = c._load_map(dir + "/abilities.json")
	c.traumas = c._load_map(dir + "/traumas.json")
	c.initiators = c._load_map(dir + "/initiators.json")
	c.regions = c._load_map(dir + "/regions.json")
	c.tags = c._load_map(dir + "/tags.json")
	c.thoughts = c._load_map(dir + "/thoughts.json")
	c.combat_tags = c._load_map(dir + "/combat/tags.json")
	c.synergies = c._load_map(dir + "/combat/synergies.json")
	c.conflicts = c._load_map(dir + "/combat/conflicts.json")
	c.fields = c._load_map(dir + "/combat/fields.json")
	c.round_cards = c._load_map(dir + "/combat/round_cards.json")
	c.enemies = c._load_map(dir + "/combat/enemies.json")
	c.tactics = c._load_map(dir + "/combat/tactics.json")
	c.enemy_abilities = c._load_map(dir + "/combat/enemy_abilities.json")
	c.lore = c._load_map(dir + "/lore.json")
	var ev_dir := DirAccess.open(dir + "/events")
	if ev_dir == null:
		c.load_errors.append("Нет папки %s/events" % dir)
	else:
		var files := ev_dir.get_files()
		files.sort()
		for f in files:
			if f.ends_with(".json"):
				var m := c._load_map(dir + "/events/" + f)
				for k: String in m:
					if c.events.has(k):
						c.load_errors.append("Дубликат события %s (%s)" % [k, f])
					c.events[k] = m[k]
	return c


## Файл — массив объектов с полем "id"; превращаем в словарь id -> объект.
func _load_map(path: String) -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(path):
		load_errors.append("Нет файла %s" % path)
		return out
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		load_errors.append("%s: строка %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return out
	var data: Variant = json.data
	if not (data is Array):
		load_errors.append("%s: ожидается массив объектов" % path)
		return out
	for item: Variant in data:
		if not (item is Dictionary) or not item.has("id"):
			load_errors.append("%s: объект без id" % path)
			continue
		var id := str(item["id"])
		if out.has(id):
			load_errors.append("%s: дубликат id %s" % [path, id])
		out[id] = item
	return out


# --- доступ --------------------------------------------------------------

func card_kind(card_id: String) -> String:
	if characters.has(card_id):
		return "character"
	if enhancements.has(card_id):
		return "enhancement"
	if initiators.has(card_id):
		return "initiator"
	if abilities.has(card_id):
		return "ability"
	if traumas.has(card_id):
		return "trauma"
	if enemies.has(card_id):
		return "enemy"
	return ""


func card_name(card_id: String) -> String:
	for m: Dictionary in [characters, enhancements, initiators, abilities, traumas, events, enemies]:
		if m.has(card_id):
			return str(m[card_id].get("name", m[card_id].get("title", card_id)))
	return card_id


func option(event_id: String, option_id: String) -> Dictionary:
	for o: Dictionary in events.get(event_id, {}).get("options", []):
		if o.get("id", "") == option_id:
			return o
	return {}


## Базовые характеристики стадии персонажа.
func stage_stats(character_id: String, stage: String) -> Dictionary:
	var c: Dictionary = characters.get(character_id, {})
	var stages: Dictionary = c.get("stages", {})
	if stages.has(stage):
		return stages[stage].get("stats", {})
	return c.get("stats", {})


func stage_name(character_id: String, stage: String) -> String:
	var c: Dictionary = characters.get(character_id, {})
	return str(c.get("stages", {}).get(stage, {}).get("name", ""))
