class_name DevPanel
extends PanelContainer
## Панель разработчика (только в отладочной сборке): начало любой главы и свои точки сохранения.
## Начало главы — прохождение ботом (AutoPlay.to_chapter), сохраняется в слот dev_start_<глава> и потом грузится сразу.
## Свои точки — F5 на экране карты (слоты dev_pt_*).

signal loaded

const START := "dev_start_"
const POINT := "dev_pt_"

var _list: VBoxContainer
var _status: Label


static func enabled() -> bool:
	return OS.is_debug_build()


## Главы по порядку мест в data/locations.json: [[id, название]].
static func chapters(c: Content) -> Array:
	var out: Array = []
	var seen := {}
	for lid: String in c.locations:
		var loc: Dictionary = c.locations[lid]
		var ch := str(loc.get("chapter", ""))
		if ch == "" or seen.has(ch):
			continue
		seen[ch] = true
		out.append([ch, str(c.regions.get(str(loc.get("region", "")), {}).get("arc_name", ch))])
	return out


## Сохраняет текущее прохождение как точку разработчика. Возвращает имя слота.
static func save_point(state: RunState) -> String:
	var slot := "%s%s_%s" % [POINT, state.chapter, Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")]
	SaveService.save_state(state, slot)
	return slot


func _ready() -> void:
	add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.055, 0.075, 0.97), Palette.GOLD.darkened(0.3), 1, 6, 18))
	custom_minimum_size = Vector2(620, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var head := HBoxContainer.new()
	var t := UITheme.label("РАЗРАБОТЧИК", "caps", 24, Palette.GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := Button.new()
	x.text = "✕"
	x.flat = true
	x.pressed.connect(queue_free)
	head.add_child(x)
	v.add_child(head)
	v.add_child(UITheme.label("Начало главы — бот проходит игру до неё (первый раз — несколько секунд).\n↻ — пройти заново. Свои точки: F5 на экране карты.", "sans", 15, Palette.TEXT_DIM))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	v.add_child(_list)
	_status = UITheme.label("", "sans", 16, Palette.SILVER)
	v.add_child(_status)
	_fill()


func _fill() -> void:
	for ch in _list.get_children():
		ch.queue_free()
	var c := ContentDB.data
	_list.add_child(UITheme.label("Начало главы", "sans_bold", 17, Palette.TEXT))
	for pair: Array in chapters(c):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var b := Button.new()
		b.text = str(pair[1]) + ("" if SaveService.has_save(START + str(pair[0])) else "   (пройти ботом)")
		b.custom_minimum_size = Vector2(480, 44)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_start_chapter.bind(str(pair[0]), false))
		row.add_child(b)
		var again := Button.new()
		again.text = "↻"
		again.tooltip_text = "Пройти ботом заново"
		again.custom_minimum_size = Vector2(56, 44)
		again.pressed.connect(_start_chapter.bind(str(pair[0]), true))
		row.add_child(again)
		_list.add_child(row)
	var points := _points()
	if not points.is_empty():
		_list.add_child(UITheme.label("Свои точки", "sans_bold", 17, Palette.TEXT))
	for slot: String in points:
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 8)
		var lb := Button.new()
		lb.text = slot.substr(POINT.length()).replace("_", " ")
		lb.custom_minimum_size = Vector2(480, 40)
		lb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		lb.pressed.connect(_load.bind(slot))
		row2.add_child(lb)
		var del := Button.new()
		del.text = "✕"
		del.tooltip_text = "Удалить точку"
		del.custom_minimum_size = Vector2(56, 40)
		del.pressed.connect(func() -> void:
			SaveService.delete_save(slot)
			_fill())
		row2.add_child(del)
		_list.add_child(row2)


func _points() -> Array:
	var out: Array = []
	var d := DirAccess.open(SaveService.DIR)
	if d == null:
		return out
	for f: String in d.get_files():
		if f.begins_with(POINT) and f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	out.reverse()
	return out


func _start_chapter(chapter: String, regenerate: bool) -> void:
	var slot := START + chapter
	if SaveService.has_save(slot) and not regenerate:
		if bool(SaveService.load_state(ContentDB.data, slot)["ok"]):
			_load(slot)
			return
		# точка от прежней версии игры (сменился формат сохранения) — проходим заново
	_status.text = "Бот проходит игру до главы…"
	await get_tree().process_frame
	await get_tree().process_frame
	var r := AutoPlay.to_chapter(ContentDB.data, chapter, randi() % 100000)
	if not r["ok"]:
		_status.text = "Не вышло: %s" % r["error"]
		return
	SaveService.save_state(r["state"], slot)
	_load(slot)


func _load(slot: String) -> void:
	var r: Dictionary = SaveService.load_state(ContentDB.data, slot)
	if not r["ok"]:
		_status.text = str(r["error"])
		return
	GameState.state = r["state"]
	SaveService.save_state(GameState.state)   # дальше — обычный автосейв
	EventBus.state_changed.emit()
	loaded.emit()
