extends Node
## Сохранения: автосейв после каждого хода, запись через .tmp (защита от порчи файла).

const DIR := "user://saves"
const AUTOSAVE := "autosave"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func path_for(slot: String) -> String:
	return "%s/%s.json" % [DIR, slot]


func has_save(slot: String = AUTOSAVE) -> bool:
	return FileAccess.file_exists(path_for(slot))


func save_state(state: RunState, slot: String = AUTOSAVE) -> bool:
	var final_path := path_for(slot)
	var tmp_path := final_path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("Не удалось записать сохранение: %s" % tmp_path)
		return false
	f.store_string(JSON.stringify(state.to_dict(), "\t"))
	f.close()
	var dir := DirAccess.open(DIR)
	if dir.file_exists(final_path.get_file()):
		dir.remove(final_path.get_file())
	return dir.rename(tmp_path.get_file(), final_path.get_file()) == OK


## Возвращает {"ok": bool, "state": RunState, "error": String}.
func load_state(content: Content, slot: String = AUTOSAVE) -> Dictionary:
	var p := path_for(slot)
	if not FileAccess.file_exists(p):
		return {"ok": false, "error": "Сохранение не найдено"}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not (data is Dictionary):
		return {"ok": false, "error": "Файл сохранения повреждён"}
	if int(data.get("save_version", 0)) != RunState.SAVE_VERSION:
		return {"ok": false, "error": "Сохранение от другой версии игры"}
	var state := RunState.from_dict(data)
	var missing := missing_ids(content, state)
	if not missing.is_empty():
		return {"ok": false, "error": "В сохранении есть неизвестные карты: %s" % ", ".join(missing)}
	return {"ok": true, "state": state}


func delete_save(slot: String = AUTOSAVE) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(path_for(slot))


static func missing_ids(content: Content, state: RunState) -> Array:
	var out: Array = []
	for card: String in state.collection:
		if content.card_kind(card) == "":
			out.append(card)
	for eid: String in state.events:
		if not content.events.has(eid):
			out.append(eid)
	for mid: String in state.missions:
		if not content.missions.has(mid):
			out.append(mid)
	return out
