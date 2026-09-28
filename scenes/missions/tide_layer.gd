class_name TideLayer
extends Control
## Прилив на карте (TideRules): под метками мест — вода.
## Предупреждение: у мест, которые уйдут под воду, пульсирует кольцо и поднимается рябь.
## Прилив: чёрная вода под затопленными местами, волны, общий холодный отлив цвета над картой.

var phase := ""                 # "" | warn | flood
var spots: Array = []           # [Vector2] — точки затопляемых мест (подножие метки)
var names: Array = []           # подписи мест (метки миссий смыло — место всё равно видно)
var urgency := 0.0              # warn: 0 → 1 по мере приближения воды
var _t := 0.0
var _flood_a := 0.0             # общий налёт воды над картой (плавно)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func show_tide(p_phase: String, p_spots: Array, p_urgency: float, p_names: Array = []) -> void:
	phase = p_phase
	spots = p_spots
	names = p_names
	urgency = clampf(p_urgency, 0.0, 1.0)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	var want := 1.0 if phase == "flood" else 0.0
	_flood_a = move_toward(_flood_a, want, delta * 0.6)
	if phase != "" or _flood_a > 0.0:
		queue_redraw()


func _draw() -> void:
	if _flood_a > 0.0:
		# вода пришла: весь лабиринт темнеет и холодеет
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.06, 0.12, 0.22 * _flood_a))
	for i in spots.size():
		var p: Vector2 = spots[i]
		if phase == "flood":
			var nm := str(names[i]) if i < names.size() else ""
			_pool(p, 1.0, ("%s · под водой" % nm) if nm != "" else "")
		elif phase == "warn":
			_warn(p)


## Затопленное место: тёмная вода с мягкими краями, расходящиеся круги, подпись места.
func _pool(c: Vector2, k: float, label: String) -> void:
	var w := 290.0
	var h := 74.0
	var a := k * maxf(_flood_a, 0.35)
	var o := c + Vector2(0, -10)
	# мягкий край: слои от широкого прозрачного к плотному центру
	for i in 7:
		var f := 1.0 - i * 0.075
		_ellipse(o, w / 2.0 * f, h / 2.0 * f, Color(0.02, 0.07, 0.13, 0.16 * a))
	for i in 3:
		var ph := fposmod(_t * 0.3 + i / 3.0, 1.0)
		_ellipse_line(o, w / 2.0 * (0.25 + 0.65 * ph), h / 2.0 * (0.25 + 0.65 * ph), Color(0.6, 0.82, 1.0, 0.28 * (1.0 - ph) * a), 1.5)
	if label != "":
		_caption(c + Vector2(0, 30), label, Color(0.72, 0.88, 1.0, 0.95 * a))


## Вода идёт: пульсирующее кольцо и мелкая рябь, чем ближе — тем ярче.
func _warn(c: Vector2) -> void:
	var pulse := 0.5 + 0.5 * sin(_t * (3.0 + 5.0 * urgency))
	var a := 0.25 + 0.55 * urgency
	_ellipse(c + Vector2(0, -8), 150.0, 36.0, Color(0.05, 0.14, 0.24, 0.25 + 0.35 * urgency))
	_ellipse_line(c + Vector2(0, -8), 150.0 + 8.0 * pulse, 36.0 + 3.0 * pulse, Color(0.45, 0.75, 1.0, a * (0.6 + 0.4 * pulse)), 3.0)
	for i in 2:
		var ph := fposmod(_t * 0.6 + i * 0.5, 1.0)
		_ellipse_line(c + Vector2(0, -8), 150.0 * ph, 36.0 * ph, Color(0.6, 0.85, 1.0, a * (1.0 - ph)), 1.5)


func _caption(at: Vector2, text: String, col: Color) -> void:
	var f := UITheme.font("title")
	var fs := 19
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := at - Vector2(tw / 2.0, 0)
	draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0.02, 0.05, 0.85 * col.a))
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 40:
		var ang := TAU * i / 40.0
		pts.append(c + Vector2(cos(ang) * rx, sin(ang) * ry))
	draw_colored_polygon(pts, col)


func _ellipse_line(c: Vector2, rx: float, ry: float, col: Color, w: float) -> void:
	if rx < 1.0 or ry < 1.0:
		return
	var pts := PackedVector2Array()
	for i in 41:
		var ang := TAU * i / 40.0
		pts.append(c + Vector2(cos(ang) * rx, sin(ang) * ry))
	draw_polyline(pts, col, w, true)
