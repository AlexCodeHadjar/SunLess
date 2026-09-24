class_name ThoughtBubble
extends Control
## Облачко мыслей над картой героя: тёмный пергамент, курсив, печатная машинка, хвостик вниз.

const MAX_W := 380.0

var _panel: PanelContainer
var _label: RichTextLabel
var _tail_x := 0.0
var _tail_y := 0.0
var _beside := false
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	z_index = 50
	_panel = PanelContainer.new()
	var st := UITheme.box(Color(0.09, 0.085, 0.10, 0.94), Palette.SILVER.darkened(0.35), 1, 12, 18)
	st.shadow_color = Color(0, 0, 0, 0.55)
	st.shadow_size = 18
	_panel.add_theme_stylebox_override("panel", st)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(MAX_W - 36, 0)
	_label.add_theme_font_override("normal_font", UITheme.font("serif_italic"))
	_label.add_theme_font_size_override("normal_font_size", 18)
	_label.add_theme_color_override("default_color", Palette.TEXT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	visible = false


## anchor — глобальный прямоугольник карты героя; облачко встаёт над ним,
## а при beside — сбоку (в бою, чтобы не закрывать весы), хвостиком к карте.
func say(text: String, anchor: Rect2, beside: bool = false) -> void:
	if _tween:
		_tween.kill()
	_label.text = text
	_label.visible_ratio = 0.0
	visible = true
	modulate.a = 0.0
	await get_tree().process_frame
	var sz := _panel.get_combined_minimum_size()
	sz.x = MAX_W
	_panel.size = sz
	var vp := get_viewport_rect().size
	_beside = beside
	var pos: Vector2
	if beside:
		# слева от карты; не влезает — справа
		pos = Vector2(anchor.position.x - 22 - sz.x, anchor.position.y + 24)
		if pos.x < 12:
			pos.x = anchor.end.x + 22
		pos.y = clampf(pos.y, 12, vp.y - sz.y - 12)
		_tail_y = clampf(anchor.get_center().y - pos.y, 20, sz.y - 20)
		_tail_x = -1.0 if pos.x > anchor.position.x else sz.x + 1.0
		global_position = pos
		size = sz
	else:
		pos = Vector2(anchor.get_center().x - sz.x / 2, anchor.position.y - sz.y - 22)
		pos.x = clampf(pos.x, 12, vp.x - sz.x - 12)
		pos.y = maxf(pos.y, 12)
		global_position = pos
		size = sz + Vector2(0, 22)
		_tail_x = clampf(anchor.get_center().x - pos.x, 24, sz.x - 24)
	queue_redraw()
	var read_time := 3.2 + text.length() * 0.035
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.25)
	_tween.parallel().tween_property(_label, "visible_ratio", 1.0, minf(1.6, text.length() * 0.025))
	_tween.tween_interval(read_time)
	_tween.tween_property(self, "modulate:a", 0.0, 0.6)
	_tween.tween_callback(hide)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible and _tween:
		_tween.kill()


func _draw() -> void:
	var pts: PackedVector2Array
	if _beside:
		var dir := -1.0 if _tail_x < 0 else 1.0
		var x := _tail_x
		pts = PackedVector2Array([Vector2(x, _tail_y - 12), Vector2(x, _tail_y + 12), Vector2(x + dir * 18, _tail_y)])
	else:
		var y := _panel.size.y - 1
		pts = PackedVector2Array([Vector2(_tail_x - 12, y), Vector2(_tail_x + 12, y), Vector2(_tail_x, y + 18)])
	draw_colored_polygon(pts, Color(0.09, 0.085, 0.10, 0.94))
	draw_polyline(PackedVector2Array([pts[0], pts[2], pts[1]]), Palette.SILVER.darkened(0.35), 1.0)
