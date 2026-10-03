class_name DayIcon
extends Button
## Кнопки дня иконками (просьба владельца 03.10: без надписей): Разведка — глаз, Сбор — осколок души, Дозор — факел,
## «Переждать» — полсолнца над горизонтом (утро: до полудня) или месяц (после полудня: до ночи). Что делает кнопка,
## что за лагерь и что сегодня рядом — во всплывающей подсказке. Сделанное сегодня дело — с галочкой.

var kind := "scout"   # scout | forage | watch | wait
var late := false     # «Переждать» после полудня — до ночи (месяц)
var done := false     # дело лагеря сегодня уже сделано
var big := false


func _ready() -> void:
	flat = true
	text = ""
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(78, 78) if big else Vector2(60, 60)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())


func set_state(is_late: bool, is_done: bool, off: bool) -> void:
	if late == is_late and done == is_done and disabled == off:
		return
	late = is_late
	done = is_done
	disabled = off
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 4.0
	var hot := is_hovered() and not disabled
	var col: Color = Color(1.0, 0.86, 0.5) if kind == "wait" else Color(0.97, 0.98, 1.0)
	if disabled:
		col = Color(col.r, col.g, col.b, 0.38)
	# мягкий свет вокруг: ярче при наведении
	draw_circle(c, r + 5.0, Color(col.r, col.g, col.b, (0.2 if hot else 0.08) * col.a))
	draw_circle(c, r, Color(0.02, 0.022, 0.035, 0.96))
	draw_arc(c, r - 3.0, 0.0, TAU, 56, Color(col.r, col.g, col.b, 0.12 * col.a), 4.0, true)
	draw_arc(c, r, 0.0, TAU, 64, col, 3.2 if hot else 2.6, true)
	var k := r / 28.0
	match kind:
		"scout":
			_eye(c, k, col)
		"forage":
			_shard(c, k, col)
		"watch":
			_torch(c, k, col)
		"wait":
			if late:
				_moon(c, k, col)
			else:
				_sun(c, k, col)
	if done:
		var p := c + Vector2(r * 0.62, r * 0.62)
		draw_circle(p, 9.0, Color(0.1, 0.35, 0.18, 0.95))
		draw_polyline(PackedVector2Array([p + Vector2(-4, 0), p + Vector2(-1, 3.5), p + Vector2(4.5, -3.5)]), Color(0.75, 1.0, 0.8), 2.0, true)


## Разведка: глаз.
func _eye(c: Vector2, k: float, col: Color) -> void:
	var up := PackedVector2Array()
	var dn := PackedVector2Array()
	for i in 21:
		var t := i / 20.0
		var x := lerpf(-16.0, 16.0, t) * k
		var y := sin(t * PI) * 10.0 * k
		up.append(c + Vector2(x, -y))
		dn.append(c + Vector2(x, y))
	draw_polyline(up, col, 2.8, true)
	draw_polyline(dn, col, 2.8, true)
	draw_circle(c, 6.5 * k, col)
	draw_circle(c, 3.0 * k, Color(0.045, 0.05, 0.075))
	draw_circle(c + Vector2(-2.0, -2.0) * k, 1.4 * k, Color(1, 1, 1, col.a))


## Сбор: осколок души (кристалл) и искры.
func _shard(c: Vector2, k: float, col: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -15) * k, c + Vector2(8, -3) * k, c + Vector2(3, 15) * k,
		c + Vector2(-5, 13) * k, c + Vector2(-8, -2) * k])
	draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.25 * col.a))
	pts.append(pts[0])
	draw_polyline(pts, col, 2.6, true)
	draw_line(c + Vector2(0, -15) * k, c + Vector2(-1, 13) * k, Color(col.r, col.g, col.b, 0.6 * col.a), 1.4, true)
	for sp: Vector2 in [Vector2(13, -11), Vector2(-14, 6)]:
		var p := c + sp * k
		draw_line(p + Vector2(-3, 0) * k, p + Vector2(3, 0) * k, col, 1.4, true)
		draw_line(p + Vector2(0, -3) * k, p + Vector2(0, 3) * k, col, 1.4, true)


## Дозор: факел.
func _torch(c: Vector2, k: float, col: Color) -> void:
	draw_line(c + Vector2(3, 16) * k, c + Vector2(-2, -1) * k, Color(col.r * 0.8, col.g * 0.7, col.b * 0.6, col.a), 4.0 * k, true)
	var fire := Color(1.0, 0.7, 0.3, col.a)
	var flame := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		var rr := 7.5 * k
		var p := Vector2(cos(a) * rr, sin(a) * rr)
		if p.y < 0.0:
			p.y *= 1.9   # язык пламени вытянут вверх
		flame.append(c + Vector2(-3, -9) * k + p)
	draw_colored_polygon(flame, Color(fire.r, fire.g, fire.b, 0.35 * col.a))
	draw_polyline(flame, fire, 2.6, true)
	draw_circle(c + Vector2(-3, -7) * k, 3.0 * k, Color(1.0, 0.9, 0.6, col.a))


## Переждать до полудня: полсолнца над горизонтом.
func _sun(c: Vector2, k: float, col: Color) -> void:
	var base := c + Vector2(0, 6) * k
	draw_line(base + Vector2(-18, 0) * k, base + Vector2(18, 0) * k, col, 2.6, true)
	draw_arc(base, 9.0 * k, PI, TAU, 24, col, 3.0, true)
	for i in 5:
		var a := PI + PI * (i + 0.5) / 5.0
		var d := Vector2(cos(a), sin(a))
		draw_line(base + d * 13.0 * k, base + d * 18.0 * k, col, 2.6, true)


## Переждать до ночи: месяц и звёзды.
func _moon(c: Vector2, k: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a := lerpf(-PI * 0.55, PI * 0.55, i / 32.0) + PI
		pts.append(c + Vector2(cos(a), sin(a)) * 13.0 * k + Vector2(3, 0) * k)
	for i in 33:
		var a2 := lerpf(PI * 0.55, -PI * 0.55, i / 32.0) + PI
		pts.append(c + Vector2(cos(a2), sin(a2)) * 10.0 * k + Vector2(8, 0) * k)
	draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.85 * col.a))
	for st: Vector2 in [Vector2(10, -10), Vector2(14, 4)]:
		draw_circle(c + st * k, 1.6 * k, col)
