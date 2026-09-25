class_name ShopIcon
extends Control
## Магазин на карте главы (docs/15 §11): отдельная иконка — не локация и не миссия.
## Пульсирует «новый товар», пока игрок не заглянул после обновления витрины.

signal pressed(shop_id: String)

const R := 32.0

var shop_id := ""
var title := ""
var news := false
var refresh_in := 0
var _hover := false
var _t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(220, 140)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Магазин: карты усилений и персонажей за осколки душ. Товар обновляется раз в несколько миссий."
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
		pressed.emit(shop_id)
		accept_event()


func set_state(has_news: bool, missions_left: int) -> void:
	if has_news != news or missions_left != refresh_in:
		news = has_news
		refresh_in = missions_left
		queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if news:
		queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x / 2.0, R + 10.0)
	var glow := Palette.COINS
	if news:
		var pulse := 0.5 + 0.5 * sin(_t * 3.0)
		draw_circle(c, R + 10.0 + 4.0 * pulse, Color(glow, 0.14 + 0.12 * pulse))
	# ромб-лавка: огонёк в ромбе, как осколок души
	var pts := PackedVector2Array([c + Vector2(0, -R), c + Vector2(R, 0), c + Vector2(0, R), c + Vector2(-R, 0)])
	draw_colored_polygon(pts, Color(0.07, 0.065, 0.1, 0.95))
	pts.append(pts[0])
	draw_polyline(pts, glow if (_hover or news) else Palette.LINE, 2.0, true)
	var f := UITheme.font("title_bold")
	var g := "✧"
	var gw := f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	draw_string(f, c + Vector2(-gw / 2.0, 12), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, glow)
	_caption(title, c.y + R + 26.0, "title", 21, Palette.TEXT if _hover else Palette.SILVER)
	var sub := "новый товар!" if news else ("товар обновится через %d %s" % [refresh_in, _missions_word(refresh_in)])
	_caption(sub, c.y + R + 48.0, "sans_bold" if news else "sans", 15, glow if news else Palette.TEXT_DIM)


func _caption(text: String, y: float, kind: String, fs: int, col: Color) -> void:
	var f := UITheme.font(kind)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2(size.x / 2.0 - w / 2.0, y)
	draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.85))
	draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


static func _missions_word(n: int) -> String:
	return UITheme.plural(n, ["миссию", "миссии", "миссий"])
