class_name Beams
extends Control
## Световые нити связей: луч летит от карты к карте, отражаясь от невидимых «стёкол»,
## на изломах вспыхивает, оставляет гаснущий шлейф; в точке попадания всплывает число.

signal landed(index: int)

const COLORS := {
	"synergy": Color(0.80, 0.90, 1.0),
	"conflict": Color(1.0, 0.33, 0.33),
	"env": Color(0.95, 0.80, 0.45),
	"intent": Color(0.72, 0.55, 1.0),
}

var _beams: Array = []   # [{pts, color, t, speed, life, index, flashed:[]}]
var _mat: CanvasItemMaterial


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = CanvasItemMaterial.new()
	_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = _mat
	set_process(true)


## Запускает луч из a в b через 1–2 точки отражения. Возвращает время полёта.
func fire(a: Vector2, b: Vector2, kind: String, index: int, glass: Array) -> float:
	var pts := PackedVector2Array([a])
	var mids := glass.duplicate()
	mids.shuffle()
	var bounces := 1 + (index % 2)
	for i in bounces:
		if mids.is_empty():
			break
		var pane: Array = mids.pop_back()
		var t := clampf(0.25 + randf() * 0.5, 0.0, 1.0)
		pts.append((pane[0] as Vector2).lerp(pane[1], t))
	pts.append(b)
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	var dur := clampf(total / 1900.0, 0.28, 0.6)
	if SettingsService.get_value("reduce_motion"):
		dur = 0.05
	_beams.append({"pts": pts, "color": COLORS.get(kind, COLORS["synergy"]), "t": 0.0, "dur": dur,
		"life": 1.0, "index": index, "flashed": [], "total": total, "done": false})
	return dur


func _process(delta: float) -> void:
	if _beams.is_empty():
		return
	for b: Dictionary in _beams:
		if not b["done"]:
			b["t"] = minf(1.0, float(b["t"]) + delta / float(b["dur"]))
			if float(b["t"]) >= 1.0:
				b["done"] = true
				landed.emit(int(b["index"]))
				_spark(b["pts"][-1], b["color"])
		else:
			b["life"] = float(b["life"]) - delta * 1.4
	_beams = _beams.filter(func(b: Dictionary) -> bool: return float(b["life"]) > 0.0)
	queue_redraw()


func _spark(at: Vector2, col: Color) -> void:
	if Vfx.reduced():
		return
	var p := Vfx.burst(at, true)
	p.amount = 14
	p.lifetime = 0.6
	p.initial_velocity_min = 60
	p.initial_velocity_max = 180
	p.color_ramp = null
	p.color = col
	p.scale_amount_min = 0.03
	p.scale_amount_max = 0.06
	get_parent().add_child(p)
	Vfx.autofree(p)


## Точка на ломаной при доле пути t.
func _point_at(pts: PackedVector2Array, total: float, t: float) -> Dictionary:
	var want := total * t
	var acc := 0.0
	for i in range(1, pts.size()):
		var seg := pts[i - 1].distance_to(pts[i])
		if acc + seg >= want:
			return {"pos": pts[i - 1].lerp(pts[i], (want - acc) / maxf(seg, 0.001)), "seg": i}
		acc += seg
	return {"pos": pts[-1], "seg": pts.size() - 1}


func _draw() -> void:
	for b: Dictionary in _beams:
		var pts: PackedVector2Array = b["pts"]
		var col: Color = b["color"]
		var head := _point_at(pts, float(b["total"]), float(b["t"]))
		var path := PackedVector2Array()
		for i in range(0, int(head["seg"])):
			path.append(pts[i])
		path.append(head["pos"])
		var life: float = b["life"]
		# свечение: несколько проходов разной толщины
		for pass_i in 4:
			var w: float = [14.0, 8.0, 4.0, 1.6][pass_i]
			var a: float = [0.06, 0.12, 0.28, 0.9][pass_i] * life
			if path.size() >= 2:
				draw_polyline(path, Color(col, a), w, true)
		# вспышки на изломах («стекло»)
		for i in range(1, int(head["seg"])):
			var p: Vector2 = pts[i]
			draw_circle(p, 10.0 * life, Color(col, 0.25 * life))
			draw_circle(p, 3.5, Color(1, 1, 1, 0.8 * life))
			# короткий преломлённый отблеск
			var d := (pts[i] - pts[i - 1]).normalized().orthogonal()
			draw_line(p - d * 26 * life, p + d * 26 * life, Color(col, 0.5 * life), 1.2, true)
		if not b["done"]:
			draw_circle(head["pos"], 7.0, Color(col, 0.5))
			draw_circle(head["pos"], 3.0, Color(1, 1, 1, 0.95))


## Всплывающее число над точкой попадания.
static func popup(parent: Control, at: Vector2, text: String, col: Color) -> void:
	var l := UITheme.label(text, "title_bold", 24, col)
	l.position = at - Vector2(120, 20)
	l.custom_minimum_size.x = 240
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.z_index = 40
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	parent.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y - 46, 1.2).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.2).set_delay(0.5)
	tw.tween_callback(l.queue_free)
