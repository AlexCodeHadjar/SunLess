class_name StartScreen
extends Control
## Экран «разбитое стекло» (docs/16 §11.5, StartRules): три осколка — Санни / Нефис / Касси. Наведение — осколок
## светлеет; щелчок — планшет старта: кто в отряде, какие карты, сколько осколков, короткий рассказ; «Начать» — игра с
## Забытого Берега. Внизу — «С самого начала» (Первый Кошмар и Академия, обучение). Сложность словами не подписана.

signal chosen(start_id: String)
signal from_beginning
signal back

const SHARD := Vector2(330, 520)

var _panel: PanelContainer
var _shards: Array = []
var _picked := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.get_theme()
	var shade := ColorRect.new()
	shade.color = Color(0.012, 0.013, 0.02, 1.0)   # экран выбора — на весь экран, меню под ним не видно
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var vp := get_viewport_rect().size
	var title := UITheme.label("С ЧЕГО НАЧНЁТСЯ СОН", "caps", 34, Palette.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(vp.x, 50)
	title.position = Vector2(0, 70)
	add_child(title)
	var sub := UITheme.label("Забытый Берег. Санни всегда в отряде — осколок решает, кто и что будет рядом с ним.", "serif_italic", 20, Palette.SILVER)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size = Vector2(vp.x, 30)
	sub.position = Vector2(0, 122)
	add_child(sub)
	var starts := StartRules.list(ContentDB.data)
	var gap := 60.0
	var x0 := (vp.x - (SHARD.x * starts.size() + gap * (starts.size() - 1))) / 2.0
	for i in starts.size():
		var st: Dictionary = starts[i]
		var sh := _Shard.new()
		sh.start = st
		sh.seed_k = i
		sh.size = SHARD
		sh.position = Vector2(x0 + i * (SHARD.x + gap), 190 + (18.0 if i == 1 else 0.0))
		sh.pressed.connect(_pick.bind(str(st["id"])))
		add_child(sh)
		_shards.append(sh)
	var low := HBoxContainer.new()
	low.add_theme_constant_override("separation", 40)
	low.position = Vector2(x0, 780)
	add_child(low)
	var begin := _link("С самого начала — Первый Кошмар и Академия", func() -> void: from_beginning.emit())
	begin.tooltip_text = "Полное прохождение с обучением: Первый Кошмар, Академия, потом Берег"
	low.add_child(begin)
	low.add_child(_link("Назад", func() -> void: back.emit()))


func _link(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.text = text
	b.add_theme_font_override("font", UITheme.font("caps"))
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Palette.SILVER)
	b.add_theme_color_override("font_hover_color", Palette.TEXT)
	b.pressed.connect(cb)
	return b


## Планшет старта: рассказ, отряд, карты, осколки и «Начать».
func _pick(id: String) -> void:
	AudioManager.play("open", -6.0)
	_picked = id
	for sh: _Shard in _shards:
		sh.selected = str(sh.start["id"]) == id
		sh.queue_redraw()
	if is_instance_valid(_panel):
		_panel.queue_free()
	var st := StartRules.get_start(ContentDB.data, id)
	var c := ContentDB.data
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.04, 0.045, 0.06, 0.97), Palette.GOLD.darkened(0.3), 1, 12, 22))
	var vp := get_viewport_rect().size
	_panel.position = Vector2(vp.x / 2.0 - 560, 840)
	_panel.custom_minimum_size = Vector2(1120, 0)
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	_panel.add_child(row)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(UITheme.label("%s · %s" % [st.get("name", ""), st.get("title", "")], "title", 26, Palette.GOLD))
	var t := UITheme.label(str(st.get("text", "")), "sans", 16, Palette.TEXT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 560
	col.add_child(t)
	var squad: Array = ["Санни"]
	for h: String in st.get("heroes", []):
		squad.append(c.card_name(h))
	col.add_child(UITheme.label("Отряд: %s · осколков души: %d" % [", ".join(squad), int(st.get("shards", 0))], "sans_bold", 16, Palette.SILVER))
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 10)
	row.add_child(cards)
	for card: String in Array(["P01"]) + Array(st.get("heroes", [])) + Array(st.get("cards", [])):
		var cv := CardView.make(card, CardView.SIZE_PANEL * 0.55, false)
		cv.custom_minimum_size = cv.size
		cards.add_child(cv)
	var go := Button.new()
	go.text = "НАЧАТЬ ›"
	go.custom_minimum_size = Vector2(200, 60)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.add_theme_font_override("font", UITheme.font("caps"))
	go.add_theme_font_size_override("font_size", 24)
	go.pressed.connect(func() -> void: chosen.emit(_picked))
	row.add_child(go)


## Осколок стекла: неровный многоугольник с серебряной кромкой, внутри — портрет героя, ниже — имя.
class _Shard:
	extends Control
	signal pressed
	var start: Dictionary = {}
	var seed_k := 0
	var selected := false
	var _tex: Texture2D
	var _hot := false
	var _pts := PackedVector2Array()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var art := "res://art/cards/%s.webp" % start.get("hero", "P01")
		if ResourceLoader.exists(art):
			_tex = load(art)
		var rng := RandomNumberGenerator.new()
		rng.seed = 91 + seed_k * 7
		var w := size.x
		var h := size.y
		# неровные края: по 3–4 излома на сторону
		var base := [Vector2(0.06, 0.02), Vector2(0.55, 0.0), Vector2(0.97, 0.05), Vector2(1.0, 0.45), Vector2(0.94, 0.98),
			Vector2(0.4, 1.0), Vector2(0.02, 0.93), Vector2(0.0, 0.5)]
		for p: Vector2 in base:
			_pts.append(Vector2((p.x + rng.randf_range(-0.03, 0.03)) * w, (p.y + rng.randf_range(-0.02, 0.02)) * h))
		mouse_entered.connect(func() -> void:
			_hot = true
			AudioManager.play("hover", -14.0)
			queue_redraw())
		mouse_exited.connect(func() -> void:
			_hot = false
			queue_redraw())

	func _has_point(p: Vector2) -> bool:
		return Geometry2D.is_point_in_polygon(p, _pts)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()

	func _draw() -> void:
		var lit := 1.0 if (_hot or selected) else 0.62
		if _tex != null:
			var uvs := PackedVector2Array()
			# портрет — верхняя часть карты героя (без плашки с именем)
			for p: Vector2 in _pts:
				uvs.append(Vector2(p.x / size.x, p.y / size.y * 0.72))
			var cols := PackedColorArray()
			for i in _pts.size():
				cols.append(Color(lit, lit, lit * 1.04))
			draw_polygon(_pts, cols, uvs, _tex)
		else:
			draw_colored_polygon(_pts, Color(0.1, 0.1, 0.13))
		var edge := _pts.duplicate()
		edge.append(_pts[0])
		var gold := selected
		var ec: Color = Palette.GOLD if gold else Color(0.86, 0.9, 1.0, 0.9 if _hot else 0.55)
		draw_polyline(edge, Color(ec.r, ec.g, ec.b, 0.25), 7.0, true)
		draw_polyline(edge, ec, 2.0, true)
		# трещины от излома
		var c := Vector2(size.x * 0.62, size.y * 0.3)
		for k in 3:
			var a := -0.9 + k * 0.85
			draw_line(c, c + Vector2(cos(a), sin(a)) * size.x * 0.22, Color(1, 1, 1, 0.18), 1.2, true)
		var f := UITheme.font("caps")
		var name := str(start.get("name", "")).to_upper()
		var nw := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		var np := Vector2(size.x / 2.0 - nw / 2.0, size.y - 46.0)
		draw_string_outline(f, np, name, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 8, Color(0, 0, 0, 0.95))
		draw_string(f, np, name, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Palette.GOLD if gold else Palette.TEXT)
