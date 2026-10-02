class_name FigurePiece
extends Control
## Каменная фигура главного героя на карте-плане (docs/18): где стоит — там лагерь. Наведение — свечение;
## зажать и вести — фигура поднимается и идёт за мышью (соседние участки подсвечивает карта); отпустить —
## сигнал dropped(глобальная точка). Картинка — art/map/figure/<герой>.(png|webp); нет — рисуется сама (paint).

signal drag_started
signal drag_moved(at: Vector2)
signal dropped(at: Vector2)
signal clicked

const W := 78.0
const H := 120.0
const DRAG_START := 6.0
const ART := {"P01": "sunny", "P02": "nephis", "P03": "cassie"}
const ACCENT := {"P01": Color(0.78, 0.84, 1.0), "P02": Color(1.0, 0.93, 0.75), "P03": Color(0.6, 0.85, 1.0)}

var hero := "P01"
var _tex: Texture2D
var _hover := false
var _press := false
var _drag := false
var _press_at := Vector2.ZERO
var _home := Vector2.ZERO
var _lift := 0.0
var _t := 0.0


static func make(hero_id: String) -> FigurePiece:
	var f := FigurePiece.new()
	f.hero = hero_id
	return f


## Картинка фигуры героя (null — рисовать самому).
static func art(hero_id: String) -> Texture2D:
	var key := str(ART.get(hero_id, "sunny"))
	for ext: String in ["webp", "png"]:
		var path := "res://art/map/figure/%s.%s" % [key, ext]
		if ResourceLoader.exists(path):
			return load(path)
	return null


func _ready() -> void:
	size = Vector2(W, H)
	pivot_offset = Vector2(W / 2.0, H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Фигура — здесь ваш лагерь. Зажмите и перенесите на соседний участок (1 день)"
	_tex = art(hero)
	mouse_entered.connect(func() -> void: _hover = true)
	mouse_exited.connect(func() -> void: _hover = false)


## Поставить фигуру основанием в точку foot (координаты родителя).
func stand_at(foot: Vector2, animate: bool = false) -> void:
	_home = foot - Vector2(W / 2.0, H)
	if not animate or Vfx.reduced():
		position = _home
		return
	var tw := create_tween()
	var mid := (position + _home) / 2.0 - Vector2(0, 90)
	tw.tween_method(func(k: float) -> void:
		var a := position.lerp(mid, k)
		position = a.lerp(mid.lerp(_home, k), k), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "scale", Vector2(1.12, 0.9), 0.08)
	tw.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)


func return_home() -> void:
	var tw := create_tween()
	tw.tween_property(self, "position", _home, 0.25).set_trans(Tween.TRANS_SINE)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_press = true
			_press_at = mb.global_position
		else:
			_press = false
			if _drag:
				_drag = false
				dropped.emit(mb.global_position)
			else:
				clicked.emit()
		accept_event()
	elif event is InputEventMouseMotion and _press:
		var mm := event as InputEventMouseMotion
		if not _drag and mm.global_position.distance_to(_press_at) >= DRAG_START:
			_drag = true
			drag_started.emit()
			AudioManager.play("place", -10.0, 0.7)
		if _drag:
			var parent := get_parent() as Control
			var local := mm.global_position - (parent.global_position if parent != null else Vector2.ZERO)
			position = local - Vector2(W / 2.0, H * 0.85)
			drag_moved.emit(mm.global_position)
		accept_event()


func _process(delta: float) -> void:
	_t += delta
	_lift = move_toward(_lift, 1.0 if _drag else 0.0, delta * 6.0)
	queue_redraw()


func _draw() -> void:
	var lift := _lift * 16.0
	# тень на земле: поднятая фигура — тень меньше и дальше
	var sh := Rect2(W * 0.12 + lift * 0.4, H - 14.0 + lift * 0.3, W * 0.76 - lift * 0.8, 16.0)
	draw_set_transform(sh.get_center(), 0.0, Vector2(1.0, sh.size.y / sh.size.x))
	draw_circle(Vector2.ZERO, sh.size.x / 2.0, Color(0, 0, 0, 0.45 - _lift * 0.2))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var glow := 0.0
	if _hover or _drag:
		glow = 0.55 + 0.25 * sin(_t * 5.0)
	paint(self, Rect2(0, -lift, W, H), _tex, ACCENT.get(hero, Color.WHITE), glow, _t)


## Нарисовать фигуру в прямоугольнике r (основание — низ r). Используют фигура на поле и сцена лагеря.
static func paint(ci: CanvasItem, r: Rect2, tex: Texture2D, accent: Color, glow: float = 0.0, t: float = 0.0) -> void:
	if glow > 0.0:
		for k in 4:
			ci.draw_circle(r.position + Vector2(r.size.x / 2.0, r.size.y * 0.55), r.size.x * (0.55 + 0.1 * k), Color(1.0, 0.85, 0.5, 0.06 * glow))
	if tex != null:
		ci.draw_texture_rect(tex, r, false)
		return
	var w := r.size.x
	var h := r.size.y
	var o := r.position
	var stone := Color(0.42, 0.44, 0.49)
	var dark := Color(0.2, 0.21, 0.25)
	var light := Color(0.66, 0.68, 0.73)
	# постамент: две ступени
	_ellipse(ci, o + Vector2(w / 2.0, h - 9.0), Vector2(w * 0.46, 9.0), dark)
	_ellipse(ci, o + Vector2(w / 2.0, h - 13.0), Vector2(w * 0.46, 8.0), stone)
	_ellipse(ci, o + Vector2(w / 2.0, h - 19.0), Vector2(w * 0.36, 7.0), dark)
	_ellipse(ci, o + Vector2(w / 2.0, h - 22.0), Vector2(w * 0.36, 6.5), stone.lightened(0.1))
	# плащ: колокол до постамента
	var cloak := PackedVector2Array([o + Vector2(w * 0.5, h * 0.3), o + Vector2(w * 0.7, h * 0.4), o + Vector2(w * 0.8, h * 0.8),
		o + Vector2(w * 0.5, h * 0.84), o + Vector2(w * 0.2, h * 0.8), o + Vector2(w * 0.3, h * 0.4)])
	ci.draw_colored_polygon(cloak, stone)
	var lit := PackedVector2Array([o + Vector2(w * 0.5, h * 0.3), o + Vector2(w * 0.3, h * 0.4), o + Vector2(w * 0.2, h * 0.8),
		o + Vector2(w * 0.42, h * 0.83), o + Vector2(w * 0.46, h * 0.42)])
	ci.draw_colored_polygon(lit, light)   # свет слева сверху
	ci.draw_polyline(PackedVector2Array([o + Vector2(w * 0.56, h * 0.42), o + Vector2(w * 0.6, h * 0.82)]), dark, 1.5, true)
	# меч — вдоль ноги, остриём вниз
	ci.draw_line(o + Vector2(w * 0.74, h * 0.46), o + Vector2(w * 0.82, h * 0.86), dark, 3.0, true)
	ci.draw_line(o + Vector2(w * 0.74, h * 0.46), o + Vector2(w * 0.82, h * 0.86), accent.darkened(0.3) * Color(1, 1, 1, 0.6), 1.0, true)
	# голова и волосы
	ci.draw_circle(o + Vector2(w * 0.5, h * 0.24), w * 0.15, stone)
	ci.draw_circle(o + Vector2(w * 0.46, h * 0.22), w * 0.12, light)
	ci.draw_arc(o + Vector2(w * 0.5, h * 0.22), w * 0.16, PI * 1.05, PI * 1.95, 16, dark, 3.0, true)
	# глаза — слабое свечение героя
	var pulse := 0.6 + 0.4 * sin(t * 2.0)
	ci.draw_circle(o + Vector2(w * 0.45, h * 0.245), 1.6, accent * Color(1, 1, 1, pulse))
	ci.draw_circle(o + Vector2(w * 0.55, h * 0.245), 1.6, accent * Color(1, 1, 1, pulse))
	# трещины камня
	ci.draw_polyline(PackedVector2Array([o + Vector2(w * 0.33, h * 0.55), o + Vector2(w * 0.37, h * 0.6), o + Vector2(w * 0.34, h * 0.66)]), dark, 1.0, true)


static func _ellipse(ci: CanvasItem, c: Vector2, rad: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * rad.x, sin(a) * rad.y))
	ci.draw_colored_polygon(pts, col)
