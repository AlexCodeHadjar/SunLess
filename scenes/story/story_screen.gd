class_name StoryScreen
extends Control
## Сюжетное окно (docs/16 §9е): картинка с одной стороны, текст с другой. Текст проявляется слово за словом;
## зажатая правая кнопка мыши — показать сразу; «Дальше» — затемнение и следующая страница.
## После последней — чёрный экран, название главы, и экран растворяется, открывая карту.

signal finished

const WORD_SEC := 0.075        # пауза между словами
const STOP_SEC := 0.32         # лишняя пауза после точки, тире, запятой
const HOLD_SEC := 0.35         # сколько держать правую кнопку, чтобы показать текст сразу
const FADE_SEC := 0.45
const IMAGE_W := 900.0

var pages: Array = []
var chapter_title := ""
var _page := -1
var _body: Label
var _ends: Array = []
var _word := 0
var _timer := 0.0
var _hold := 0.0
var _holding := false
var _done := false
var _busy := false
var _next: Button
var _hint: Label
var _ring: Control
var _layer: Control
var _veil: ColorRect
var _title: Label        # название главы в финале (перекладывается при смене размера окна)


## Показывает страницы поверх parent. title — название главы для финальной заставки.
static func play(parent: Node, p_pages: Array, title: String) -> StoryScreen:
	var sc := StoryScreen.new()
	sc.pages = p_pages
	sc.chapter_title = title
	parent.add_child(sc)
	return sc


func _ready() -> void:
	add_to_group(HintTargets.LAYER)
	top_level = true
	z_index = 90
	position = Vector2.ZERO
	size = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.get_theme()
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_layer = Control.new()
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_layer)
	_veil = ColorRect.new()
	_veil.color = Color(0, 0, 0, 1)
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)
	get_viewport().size_changed.connect(_on_resize)
	_show_page(0)


## Окно сменило размер (переход в полный экран во время истории — баг, найденный владельцем 03.10): экран истории
## растягивается на всё окно и перестраивает страницу, чтобы карта под ним не проступала. Прочитанное — не печатается
## заново.
func _on_resize() -> void:
	if not is_inside_tree():
		return
	size = get_viewport_rect().size
	if _title != null:
		_title.custom_minimum_size = Vector2(size.x, 0)
		_title.size.x = size.x
		_title.position = Vector2(0, size.y / 2 - 60)
		return
	if _body == null:
		return
	var word := _word
	var done := _done
	_show_page(_page)
	if done:
		_reveal_all()
	elif word > 0 and word <= _ends.size():
		_word = word
		_body.visible_characters = _ends[word - 1]


func _show_page(i: int) -> void:
	_page = i
	for ch in _layer.get_children():
		ch.queue_free()
	var p: Dictionary = pages[i]
	var left := str(p.get("side", "left")) == "left"
	var img_x := 0.0 if left else size.x - IMAGE_W
	# картинка: у рисунка карты — только сам рисунок (без рамки и подписи)
	var tex: Texture2D = load(str(p.get("image", ""))) if ResourceLoader.exists(str(p.get("image", ""))) else null
	if tex != null and str(p.get("crop", "")) == "card":
		var at := AtlasTexture.new()
		at.atlas = tex
		var ts := tex.get_size()
		at.region = Rect2(ts.x * 0.06, ts.y * 0.045, ts.x * 0.88, ts.y * 0.70)
		tex = at
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.position = Vector2(img_x, 0)
		tr.size = Vector2(IMAGE_W, size.y)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_layer.add_child(tr)
		# край картинки растворяется в черноте со стороны текста
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0))
		g.set_color(1, Color(0, 0, 0, 1))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.width = 256
		gt.height = 4
		if not left:
			gt.fill_from = Vector2(1, 0)
			gt.fill_to = Vector2(0, 0)
		var edge := TextureRect.new()
		edge.texture = gt
		edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		edge.stretch_mode = TextureRect.STRETCH_SCALE
		edge.size = Vector2(300, size.y)
		edge.position = Vector2(img_x + IMAGE_W - 300 if left else img_x, 0)
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_layer.add_child(edge)
	var tx := IMAGE_W + 90.0 if left else 130.0
	var tw := size.x - IMAGE_W - 220.0
	var title := UITheme.label(str(p.get("title", "")), "title_bold", 58, Palette.GOLD)
	title.position = Vector2(tx, 250)
	title.custom_minimum_size.x = tw
	_layer.add_child(title)
	var line := ColorRect.new()
	line.color = Color(Palette.GOLD, 0.35)
	line.position = Vector2(tx, 336)
	line.size = Vector2(160, 2)
	_layer.add_child(line)
	_body = UITheme.label(str(p.get("text", "")), "serif", 31, Palette.TEXT)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.position = Vector2(tx, 370)
	_body.custom_minimum_size.x = tw
	_body.size.x = tw
	_body.add_theme_constant_override("line_spacing", 8)
	_body.visible_characters = 0
	_layer.add_child(_body)
	_ends = StoryRules.word_ends(_body.text)
	_word = 0
	_timer = 0.5
	_done = false
	_hold = 0.0
	var foot_y := size.y - 150.0
	_hint = UITheme.label("Зажмите правую кнопку мыши — показать текст сразу", "sans", 17, Palette.TEXT_DIM)
	_hint.position = Vector2(tx + 36, foot_y + 20)
	_layer.add_child(_hint)
	_ring = Control.new()
	_ring.position = Vector2(tx + 12, foot_y + 32)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(func() -> void:
		_ring.draw_arc(Vector2.ZERO, 11, 0, TAU, 32, Color(Palette.TEXT_DIM, 0.4), 2.0)
		if _hold > 0.0:
			_ring.draw_arc(Vector2.ZERO, 11, -PI / 2, -PI / 2 + TAU * minf(1.0, _hold / HOLD_SEC), 32, Palette.GOLD, 3.0))
	_layer.add_child(_ring)
	var n := UITheme.label("%d / %d" % [i + 1, pages.size()], "sans", 16, Palette.TEXT_DIM)
	n.position = Vector2(tx, 200)
	_layer.add_child(n)
	_next = Button.new()
	_next.text = "ДАЛЬШЕ ›" if i < pages.size() - 1 else "НАЧАТЬ ›"
	_next.custom_minimum_size = Vector2(300, 64)
	_next.add_theme_font_override("font", UITheme.font("caps"))
	_next.add_theme_font_size_override("font_size", 28)
	_next.position = Vector2(tx + tw - 300, foot_y)
	_next.modulate.a = 0.0
	_next.disabled = true
	_next.pressed.connect(_advance)
	_layer.add_child(_next)
	_busy = true
	var tw2 := create_tween()
	tw2.tween_property(_veil, "color:a", 0.0, FADE_SEC * 1.4)
	tw2.tween_callback(func() -> void: _busy = false)


func _process(delta: float) -> void:
	if _body == null or _busy:
		return
	if not _done:
		if _holding:
			_hold += delta
			_ring.queue_redraw()
			if _hold >= HOLD_SEC:
				_reveal_all()
				return
		_timer -= delta
		if _timer <= 0.0:
			if _word >= _ends.size():
				_reveal_all()
				return
			var at: int = _ends[_word]
			_body.visible_characters = at
			var last := _body.text[at - 1] if at > 0 else " "
			_timer = WORD_SEC + (STOP_SEC if last in [".", ",", "—", ":", "!", "?", "…"] else 0.0)
			_word += 1


func _reveal_all() -> void:
	_done = true
	_body.visible_characters = -1
	_hold = 0.0
	_ring.visible = false
	_hint.text = "Пробел или «Дальше» — продолжить"
	_next.disabled = false
	create_tween().tween_property(_next, "modulate:a", 1.0, 0.3)
	_next.grab_focus()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		_holding = event.pressed
		if not _holding:
			_hold = 0.0
			if _ring:
				_ring.queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode in [KEY_SPACE, KEY_ENTER]:
		if not _done:
			_reveal_all()
		elif not _busy:
			_advance()
		get_viewport().set_input_as_handled()


## «Дальше»: экран темнеет, следующая страница; после последней — название главы и растворение в карту.
func _advance() -> void:
	if _busy or not _done:
		return
	_busy = true
	_next.disabled = true
	AudioManager.play("open", -6.0)
	var tw := create_tween()
	tw.tween_property(_veil, "color:a", 1.0, FADE_SEC)
	if _page < pages.size() - 1:
		tw.tween_callback(func() -> void: _show_page(_page + 1))
		return
	tw.tween_callback(_finale)


func _finale() -> void:
	for ch in _layer.get_children():
		ch.queue_free()
	var t := UITheme.label(chapter_title.to_upper(), "title_bold", 84, Palette.GOLD)
	_title = t
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.custom_minimum_size = Vector2(size.x, 0)
	t.position = Vector2(0, size.y / 2 - 60)
	t.modulate.a = 0.0
	add_child(t)
	var tw := create_tween()
	tw.tween_property(t, "modulate:a", 1.0, 0.9)
	tw.tween_interval(0.9)
	tw.tween_callback(func() -> void: finished.emit())
	tw.tween_property(self, "modulate:a", 0.0, 1.4)
	tw.tween_callback(queue_free)
