class_name DropZone
extends Control
## Область, принимающая перетаскиваемые карты определённых типов.

signal dropped(card_id: String)

var accepts: Array[String] = []
var hint := ""
var show_frame := true
var _hot := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	var ok: bool = data is Dictionary and accepts.has(str(data.get("kind", "")))
	if ok != _hot:
		_hot = ok
		queue_redraw()
	return ok


func _drop_data(_at: Vector2, data: Variant) -> void:
	_hot = false
	queue_redraw()
	AudioManager.play("place")
	dropped.emit(str(data["card"]))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		if _hot:
			_hot = false
			queue_redraw()


func _draw() -> void:
	if not show_frame and not _hot:
		return
	var r := Rect2(Vector2.ZERO, size)
	var c := Palette.SILVER if _hot else Palette.LINE
	draw_rect(r, Color(1, 1, 1, 0.04) if _hot else Color(0, 0, 0, 0.15))
	# пунктирная рамка
	var dash := 8.0
	for side in 4:
		var a: Vector2 = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)][side]
		var b: Vector2 = [Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position][side]
		var len := a.distance_to(b)
		var dir := (b - a) / len
		var t := 0.0
		while t < len:
			draw_line(a + dir * t, a + dir * minf(t + dash, len), c, 1.0)
			t += dash * 2
	if hint != "" and get_child_count() == 0:
		draw_multiline_string(UITheme.font("sans"), Vector2(8, size.y / 2), hint, HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 16, 3, Palette.TEXT_DIM)
