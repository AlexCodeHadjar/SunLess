class_name ChanceBar
extends Control
## Шкала шанса: трек 10 px, заполнение по градиенту, процент и метка всегда читаются.
## Умеет анимировать бросок: указатель бежит и останавливается на выпавшем числе.

signal roll_finished

var chance := 0
var show_label := true
var track_height := 10.0
var marker := -1          # выпавшее число или -1
var _shown := 0.0
var _marker_pos := -1.0


func _ready() -> void:
	custom_minimum_size.y = maxf(custom_minimum_size.y, track_height + 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_chance(v: int, animate: bool = true) -> void:
	chance = v
	if not animate or SettingsService.get_value("reduce_motion") or not is_inside_tree():
		_shown = v
		queue_redraw()
		return
	var tw := create_tween()
	tw.tween_method(_set_shown, _shown, float(v), 0.3).set_ease(Tween.EASE_OUT)


func _set_shown(v: float) -> void:
	_shown = v
	queue_redraw()


func _set_marker(v: float) -> void:
	_marker_pos = v
	queue_redraw()


## Анимация броска (~0.9 с при обычной скорости).
func play_roll(value: int) -> void:
	marker = value
	var speed: float = SettingsService.get_value("roll_speed")
	if speed <= 0.0 or SettingsService.get_value("reduce_motion"):
		_marker_pos = value
		queue_redraw()
		roll_finished.emit()
		return
	var tw := create_tween()
	tw.tween_method(_set_marker, 0.0, 100.0, 0.35 * speed).set_trans(Tween.TRANS_SINE)
	tw.tween_method(_set_marker, 100.0, float(value), 0.55 * speed).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.finished.connect(func() -> void: roll_finished.emit())


func _draw() -> void:
	var mono: bool = SettingsService.get_value("chance_monochrome")
	var h := track_height
	var y := (size.y - h) / 2
	var track := Rect2(0, y, size.x, h)
	draw_rect(track, Color("#0B0C11"))
	var fill_w := size.x * clampf(_shown / 100.0, 0.0, 1.0)
	if fill_w > 0:
		draw_rect(Rect2(0, y, fill_w, h), Palette.chance_color(int(_shown), mono))
	if chance >= 100 and not mono:
		draw_rect(track.grow(2), Color(0.88, 0.7, 0.24, 0.25), false, 2.0)
	if chance <= 0:
		var x := 0.0
		while x < size.x:
			draw_line(Vector2(x, y + h), Vector2(x + h, y), Color("#3A0E12"), 1.0)
			x += 8
	draw_rect(track, Palette.LINE, false, 1.0)
	if _marker_pos >= 0:
		var mx := size.x * clampf(_marker_pos / 100.0, 0.0, 1.0)
		draw_line(Vector2(mx, y - 6), Vector2(mx, y + h + 6), Palette.TEXT, 2.0)
		draw_colored_polygon(PackedVector2Array([Vector2(mx - 5, y - 10), Vector2(mx + 5, y - 10), Vector2(mx, y - 4)]), Palette.TEXT)
