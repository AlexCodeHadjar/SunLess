class_name LinkGraph
extends Control
## Полупрозрачная сетка связей вокруг тега (по удержанию Shift).
## Серебряные линии — симбиоз, багровый пунктир — конфликт, толщина — сила связи.
## Неоткрытые связи — тусклый узел «???»: игрок знает, что связь есть, но не знает с чем.

var tag := ""
var highlight_id := ""     # только что открытая связь — горит ярче
var _nodes: Array = []     # [{pos, text, type, known, value, id}]
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 55
	visible = false


func show_for(p_tag: String, p_highlight: String = "") -> void:
	tag = p_tag
	highlight_id = p_highlight
	var links := TagText.links_of(tag)
	_nodes.clear()
	var n := links.size()
	var center := get_viewport_rect().size / 2
	for i in n:
		var l: Dictionary = links[i]
		var ang := TAU * i / maxf(1, n) - PI / 2
		var r := 250.0 + (i % 2) * 70.0
		_nodes.append({"pos": center + Vector2(cos(ang), sin(ang)) * r, "text": l["other"], "type": l["type"],
			"known": ProfileService.is_known(l["id"]) or l["id"] == highlight_id, "value": float(l["value"]),
			"id": l["id"], "name": l["name"]})
	visible = true
	_t = 0.0
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if highlight_id != "":
		queue_redraw()


func _draw() -> void:
	if tag == "":
		return
	var vp := get_viewport_rect().size
	var center := vp / 2
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.02, 0.03, 0.55))
	var f := UITheme.font("sans")
	var fb := UITheme.font("title")
	for nd: Dictionary in _nodes:
		var p: Vector2 = nd["pos"]
		var syn: bool = nd["type"] == "synergy"
		var col := Palette.SILVER if syn else Palette.STAT_DOWN
		var w := 1.0 + clampf(absf(float(nd["value"])) * 8.0, 0.0, 5.0)
		var alpha := 0.85 if nd["known"] else 0.18
		if nd["id"] == highlight_id:
			alpha = 0.6 + 0.4 * sin(_t * 6.0)
			w += 2.0
		var c := Color(col, alpha)
		if syn:
			draw_line(center, p, c, w, true)
		else:
			var dir := (p - center).normalized()
			var len := center.distance_to(p)
			var t := 0.0
			while t < len:
				draw_line(center + dir * t, center + dir * minf(t + 12, len), c, w, true)
				t += 22
		var box := Rect2(p - Vector2(95, 20), Vector2(190, 40))
		draw_rect(box, Color(0.06, 0.06, 0.08, 0.9 if nd["known"] else 0.5))
		draw_rect(box, c, false, 1.0)
		var label: String = nd["text"] if nd["known"] else "???"
		draw_string(f, box.position + Vector2(0, 17), label, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 15, Color(Palette.TEXT, alpha + 0.1))
		if nd["known"]:
			draw_string(f, box.position + Vector2(0, 34), str(nd["name"]), HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 12, Color(col, 0.8))
	# центр
	var cbox := Rect2(center - Vector2(110, 30), Vector2(220, 60))
	draw_rect(cbox, Color(0.08, 0.08, 0.1, 0.95))
	draw_rect(cbox, Palette.GOLD, false, 2.0)
	draw_string(fb, cbox.position + Vector2(0, 40), tag, HORIZONTAL_ALIGNMENT_CENTER, cbox.size.x, 28, Palette.TEXT)
	var known := 0
	for nd: Dictionary in _nodes:
		if nd["known"]:
			known += 1
	draw_string(f, Vector2(0, vp.y - 40), "Связи тега «%s»: открыто %d из %d · серебро — симбиоз, багровый пунктир — конфликт" % [tag, known, _nodes.size()],
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 16, Palette.TEXT_DIM)
