class_name LocationPin
extends Control
## Локация на карте главы: число открытых миссий, кольцо таймера отряда в пути, «!» — отряд прибыл.

signal pressed(location_id: String)

const R := 34.0

var location_id := ""
var title := ""
var open_count := 0
var progress := -1.0      # 0..1 — отряд в пути; -1 — никого
var remaining := 0.0      # секунд до прибытия
var arrived := false
var _hover := false
var _t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(200, 124)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void:
		_hover = true
		AudioManager.play("hover", -14.0)
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		AudioManager.play("open", -6.0)
		pressed.emit(location_id)
		accept_event()


func _process(delta: float) -> void:
	_t += delta
	if arrived or progress >= 0.0:
		queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x / 2.0, R + 8.0)
	if arrived:
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		draw_circle(c, R + 12.0 + 4.0 * pulse, Color(Palette.GOLD, 0.18 + 0.12 * pulse))
	draw_circle(c, R, Color(0.07, 0.075, 0.1, 0.94))
	var border := Palette.GOLD if (_hover or arrived) else Palette.LINE
	draw_arc(c, R, 0.0, TAU, 56, border, 2.0, true)
	if progress >= 0.0:
		draw_arc(c, R + 6.0, 0.0, TAU, 56, Color(1, 1, 1, 0.1), 5.0, true)
		draw_arc(c, R + 6.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(progress, 0.0, 1.0), 56, Color("#E3C98E"), 5.0, true)
	var center := ""
	var col := Palette.TEXT
	if arrived:
		center = "!"
		col = Color("#E3C98E")
	elif progress >= 0.0:
		center = "%dс" % int(ceil(remaining))
	elif open_count > 0:
		center = str(open_count)
	else:
		center = "·"
		col = Palette.TEXT_DIM
	var f := UITheme.font("title_bold")
	var fs := 30 if center.length() <= 2 else 24
	var tw := f.get_string_size(center, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, c + Vector2(-tw / 2.0, fs * 0.34), center, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	var nf := UITheme.font("title")
	var nw := nf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
	var np := Vector2(size.x / 2.0 - nw / 2.0, c.y + R + 26.0)
	draw_string_outline(nf, np, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, 6, Color(0, 0, 0, 0.8))
	draw_string(nf, np, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Palette.TEXT if _hover else Palette.SILVER)
