extends Node
## Профиль игрока вне прохождений: открытые связи тегов (метапрогресс, навсегда).

const PATH := "user://profile.json"

var discovered: Dictionary = {}   # id связи -> true


func _ready() -> void:
	if FileAccess.file_exists(PATH):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			discovered = Dictionary(d.get("discovered_links", {}))


func is_known(link_id: String) -> bool:
	return discovered.has(link_id)


## Отмечает связи открытыми; возвращает только новые.
func discover(ids: Array) -> Array:
	var fresh: Array = []
	for id: String in ids:
		if id != "" and not discovered.has(id):
			discovered[id] = true
			fresh.append(id)
	if not fresh.is_empty():
		_save()
	return fresh


func known_count() -> int:
	return discovered.size()


func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"discovered_links": discovered}, "\t"))
