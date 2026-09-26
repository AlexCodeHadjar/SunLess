class_name Content
extends RefCounted
## Неизменяемые описания карт, миссий и боя, загруженные из data/*.json.

var characters: Dictionary = {}
var enhancements: Dictionary = {}
var abilities: Dictionary = {}
var traumas: Dictionary = {}
var regions: Dictionary = {}
var tags: Dictionary = {}
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
# миссии и отряды (docs/15)
var locations: Dictionary = {}     # локации глав: data/locations.json
var missions: Dictionary = {}      # миссии: data/missions/*.json
var shops: Dictionary = {}         # магазины глав: data/shops.json
var bonds: Dictionary = {}         # связки героев: data/bonds.json (BondRules)
var tag_growth: Dictionary = {}    # рост тегов: data/tag_growth.json (GrowthRules)
var onslaught: Dictionary = {}     # натиск Кошмара по главам: data/onslaught.json (OnslaughtRules)
var tutorial: Dictionary = {}      # подсказки обучения: data/tutorial.json (TutorialRules)
var load_errors: Array[String] = []


static func load_from(dir: String = "res://data") -> Content:
	var c := Content.new()
	c.characters = c._load_map(dir + "/characters.json")
	c.enhancements = c._load_map(dir + "/enhancements.json")
	c.abilities = c._load_map(dir + "/abilities.json")
	c.traumas = c._load_map(dir + "/traumas.json")
	c.regions = c._load_map(dir + "/regions.json")
	c.tags = c._load_map(dir + "/tags.json")
	c.combat_tags = c._load_map(dir + "/combat/tags.json")
	c.synergies = c._load_map(dir + "/combat/synergies.json")
	c.conflicts = c._load_map(dir + "/combat/conflicts.json")
	c.fields = c._load_map(dir + "/combat/fields.json")
	c.round_cards = c._load_map(dir + "/combat/round_cards.json")
	c.enemies = c._load_map(dir + "/combat/enemies.json")
	c.tactics = c._load_map(dir + "/combat/tactics.json")
	c.enemy_abilities = c._load_map(dir + "/combat/enemy_abilities.json")
	c.lore = c._load_map(dir + "/lore.json")
	if FileAccess.file_exists(dir + "/locations.json"):
		c.locations = c._load_map(dir + "/locations.json")
	c.missions = c._load_dir(dir + "/missions", "миссии")
	if FileAccess.file_exists(dir + "/shops.json"):
		c.shops = c._load_map(dir + "/shops.json")
	if FileAccess.file_exists(dir + "/bonds.json"):
		c.bonds = c._load_map(dir + "/bonds.json")
	if FileAccess.file_exists(dir + "/tag_growth.json"):
		c.tag_growth = c._load_map(dir + "/tag_growth.json")
	if FileAccess.file_exists(dir + "/onslaught.json"):
		c.onslaught = c._load_map(dir + "/onslaught.json")
	if FileAccess.file_exists(dir + "/tutorial.json"):
		c.tutorial = c._load_map(dir + "/tutorial.json")
	return c


## Все *.json папки в один словарь id -> объект (папки может и не быть).
func _load_dir(path: String, what: String) -> Dictionary:
	var out := {}
	var d := DirAccess.open(path)
	if d == null:
		return out
	var files := d.get_files()
	files.sort()
	for f in files:
		if f.ends_with(".json"):
			var m := _load_map(path + "/" + f)
			for k: String in m:
				if out.has(k):
					load_errors.append("Дубликат: %s %s (%s)" % [what, k, f])
				out[k] = m[k]
	return out


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
	if abilities.has(card_id):
		return "ability"
	if traumas.has(card_id):
		return "trauma"
	if enemies.has(card_id):
		return "enemy"
	return ""


func card_name(card_id: String) -> String:
	for m: Dictionary in [characters, enhancements, abilities, traumas, enemies, missions]:
		if m.has(card_id):
			return str(m[card_id].get("name", m[card_id].get("title", card_id)))
	return card_id


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
