class_name HintPopup
extends PanelContainer
## Подсказка обучения (docs/16 Ф12) — «прожектор»:
## 1) экран на пару секунд темнеет, а то, о чём речь (`target`, см. HintTargets), остаётся светлым окном
##    в золотой рамке с уголками;
## 2) карточка подсказки встаёт рядом с целью (справа, слева, снизу или сверху — где есть место),
##    маленький золотой уголок на её краю смотрит на цель;
## 3) затемнение плавно уходит, рамка тихо пульсирует до «Понятно». Играть подсказка не мешает:
##    затемнение не ловит щелчки. Без цели — карточка у правого края, без затемнения.

const W := 300.0
const GOLD := Color("#D9B870")
const GOLD_BRIGHT := Color("#FFE7A8")
const DIM := 0.62          # сила затемнения
const DIM_HOLD := 2.4      # сколько держится затемнение, с
const DIM_FADE := 0.9      # как долго уходит
const PAD := 10.0          # поля светлого окна вокруг цели
const GAP := 26.0          # от цели до карточки

var _queue: Array = []
var _title: Label
var _text: Label
var _target := ""
var _spot: Control
var _age := 0.0            # сколько показывается текущая подсказка
var _t := 0.0
var _side := ""            # с какой стороны цели стоит карточка: right|left|below|above
var _missing := 0.0        # сколько цели не видно (ушла под окно, ещё не появилась)


func _ready() -> void:
	top_level = true
	z_index = 80
	mouse_filter = Control.MOUSE_FILTER_STOP
	var st := UITheme.box(Color(0.07, 0.07, 0.09, 0.98), GOLD.darkened(0.25), 1, 8, 14)
	st.shadow_color = Color(0, 0, 0, 0.7)
	st.shadow_size = 22
	add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	v.add_child(UITheme.label("ПОДСКАЗКА", "sans_bold", 13, GOLD))
	_title = UITheme.label("", "title_bold", 22, Palette.TEXT)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = W - 28
	v.add_child(_title)
	_text = UITheme.label("", "serif", 17, Palette.SILVER)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = W - 28
	v.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var ok := Button.new()
	ok.text = "ПОНЯТНО"
	ok.custom_minimum_size = Vector2(130, 38)
	ok.add_theme_font_override("font", UITheme.font("caps"))
	ok.add_theme_font_size_override("font_size", 16)
	ok.pressed.connect(_next)
	row.add_child(ok)
	var off := Button.new()
	off.text = "Больше не показывать"
	off.flat = true
	off.add_theme_font_size_override("font_size", 14)
	off.add_theme_color_override("font_color", Palette.TEXT_DIM)
	off.pressed.connect(func() -> void:
		SettingsService.set_value("tutorial", false)
		_queue.clear()
		_hide())
	row.add_child(off)
	# затемнение и рамка — отдельный слой под карточкой, щелчки не ловит
	_spot = Control.new()
	_spot.top_level = true
	_spot.z_as_relative = false
	_spot.z_index = 79
	_spot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spot.draw.connect(_draw_spot)
	add_child(_spot)
	visible = false
	EventBus.tutorial_hint.connect(push)


func push(h: Dictionary) -> void:
	_queue.append(h)
	if not visible:
		_next()


func _hide() -> void:
	visible = false
	_target = ""
	_spot.queue_redraw()


func _next() -> void:
	if _queue.is_empty():
		_hide()
		return
	var h: Dictionary = _queue.pop_front()
	_title.text = str(h.get("title", ""))
	_text.text = str(h.get("text", ""))
	_target = str(h.get("target", ""))
	_age = 0.0
	_side = ""
	_missing = 0.0
	modulate.a = 0.0
	visible = true
	AudioManager.play("open", -10.0, 1.3)
	await get_tree().process_frame
	if not is_instance_valid(self):
		return
	size = get_combined_minimum_size()
	_place()


func _process(delta: float) -> void:
	_t += delta
	if not visible:
		return
	# цели нет: следующая подсказка — вперёд; если очереди нет, карточка прячется и ждёт цель
	if _target != "" and _target_rect().size == Vector2.ZERO:
		_missing += delta
		if _missing > 0.4 and not _queue.is_empty():
			var cur := {"title": _title.text, "text": _text.text, "target": _target}
			_next()
			_queue.append(cur)
			return
		modulate.a = maxf(0.0, modulate.a - delta * 6.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_spot.queue_redraw()
		return
	if _missing > 0.0:
		_missing = 0.0
		_age = 0.0     # цель вернулась — снова ненадолго затемнить
	mouse_filter = Control.MOUSE_FILTER_STOP
	_age += delta
	modulate.a = minf(1.0, modulate.a + delta * 4.0)
	_place()
	_spot.position = Vector2.ZERO
	_spot.size = get_viewport_rect().size
	_spot.queue_redraw()


## Рамка цели на экране (с полями) или пустая.
func _target_rect() -> Rect2:
	if _target == "":
		return Rect2()
	var r := HintTargets.rect(_target)
	return r.grow(PAD) if r.size != Vector2.ZERO else Rect2()


## Карточка — рядом с целью, где хватает места; иначе у правого края.
func _place() -> void:
	var vp := get_viewport_rect().size
	var r := _target_rect()
	size = get_combined_minimum_size()
	if r.size == Vector2.ZERO:
		_side = ""
		global_position = Vector2(vp.x - size.x - 12.0, 84.0)
		return
	var tries := {
		"right": Vector2(r.end.x + GAP, r.get_center().y - size.y * 0.5),
		"left": Vector2(r.position.x - GAP - size.x, r.get_center().y - size.y * 0.5),
		"below": Vector2(r.get_center().x - size.x * 0.5, r.end.y + GAP),
		"above": Vector2(r.get_center().x - size.x * 0.5, r.position.y - GAP - size.y),
	}
	var order := ["right", "left", "below", "above"]
	if _side != "":
		order.erase(_side)
		order.push_front(_side)   # не прыгать между сторонами без нужды
	for sd: String in order:
		var p: Vector2 = tries[sd]
		var fits := p.x >= 8.0 and p.y >= 8.0 and p.x + size.x <= vp.x - 8.0 and p.y + size.y <= vp.y - 8.0
		if sd in ["right", "left"]:
			fits = (p.x >= 8.0 and p.x + size.x <= vp.x - 8.0)
		elif sd in ["below", "above"]:
			fits = (p.y >= 8.0 and p.y + size.y <= vp.y - 8.0)
		if fits:
			_side = sd
			p.x = clampf(p.x, 8.0, vp.x - size.x - 8.0)
			p.y = clampf(p.y, 8.0, vp.y - size.y - 8.0)
			global_position = p
			return
	_side = ""
	global_position = Vector2(vp.x - size.x - 12.0, 84.0)


func _draw_spot() -> void:
	if not visible:
		return
	var r := _target_rect()
	if r.size == Vector2.ZERO:
		return
	var vp := _spot.size
	var appear := minf(1.0, _age * 3.0)
	# затемнение вокруг окна: держится DIM_HOLD, потом уходит
	var dim := DIM * appear * clampf(1.0 - (_age - DIM_HOLD) / DIM_FADE, 0.0, 1.0)
	if dim > 0.005:
		var c := Color(0.0, 0.0, 0.02, dim)
		_spot.draw_rect(Rect2(0, 0, vp.x, r.position.y), c)
		_spot.draw_rect(Rect2(0, r.end.y, vp.x, vp.y - r.end.y), c)
		_spot.draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), c)
		_spot.draw_rect(Rect2(r.end.x, r.position.y, vp.x - r.end.x, r.size.y), c)
	# рамка: тонкая золотая нить + ореол, уголки ярче; сначала «стягивается» к цели
	var pulse := 0.6 + 0.4 * sin(_t * 2.6)
	var rr := r.grow(24.0 * (1.0 - appear))
	for i in 4:
		_spot.draw_rect(rr.grow(2.0 + i * 3.0), Color(GOLD, 0.09 * (4 - i) / 4.0 * pulse * appear), false, 3.0)
	_spot.draw_rect(rr, Color(GOLD, 0.75 * appear), false, 1.5)
	var L := minf(26.0, minf(rr.size.x, rr.size.y) * 0.3)
	var cw := Color(GOLD_BRIGHT, (0.75 + 0.25 * pulse) * appear)
	for corner: Array in [[rr.position, Vector2(1, 1)], [Vector2(rr.end.x, rr.position.y), Vector2(-1, 1)],
			[Vector2(rr.position.x, rr.end.y), Vector2(1, -1)], [rr.end, Vector2(-1, -1)]]:
		var p: Vector2 = corner[0]
		var d: Vector2 = corner[1]
		_spot.draw_line(p, p + Vector2(d.x * L, 0), cw, 3.0, true)
		_spot.draw_line(p, p + Vector2(0, d.y * L), cw, 3.0, true)
	# уголок-указатель на краю карточки, смотрит на цель
	if _side != "":
		var cr := get_global_rect()
		var tip: Vector2
		var a: Vector2
		var b: Vector2
		match _side:
			"right":
				var y := clampf(r.get_center().y, cr.position.y + 18, cr.end.y - 18)
				tip = Vector2(cr.position.x - 12, y)
				a = Vector2(cr.position.x + 1, y - 10)
				b = Vector2(cr.position.x + 1, y + 10)
			"left":
				var y2 := clampf(r.get_center().y, cr.position.y + 18, cr.end.y - 18)
				tip = Vector2(cr.end.x + 12, y2)
				a = Vector2(cr.end.x - 1, y2 - 10)
				b = Vector2(cr.end.x - 1, y2 + 10)
			"below":
				var x := clampf(r.get_center().x, cr.position.x + 18, cr.end.x - 18)
				tip = Vector2(x, cr.position.y - 12)
				a = Vector2(x - 10, cr.position.y + 1)
				b = Vector2(x + 10, cr.position.y + 1)
			_:
				var x2 := clampf(r.get_center().x, cr.position.x + 18, cr.end.x - 18)
				tip = Vector2(x2, cr.end.y + 12)
				a = Vector2(x2 - 10, cr.end.y - 1)
				b = Vector2(x2 + 10, cr.end.y - 1)
		_spot.draw_colored_polygon(PackedVector2Array([a, tip, b]), Color(0.07, 0.07, 0.09, modulate.a))
		_spot.draw_polyline(PackedVector2Array([a, tip, b]), Color(GOLD, 0.9 * modulate.a), 1.5, true)
