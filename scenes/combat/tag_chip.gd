class_name TagChip
extends Control
## Тег на поле боя: иконка категории + имя (или только иконка, если места мало).
## Наведение — карточка тега; луч связи прилетает прямо в чип, и тот вспыхивает.

signal hovered(tag: String, on: bool)

const ICON_GAP := 3.0

var tag := ""
var font_size := 13
var icon_only := false
var _icon: Texture2D
var _color := Color("#C9CED6")
var _hover := false
var _glow := 0.0
var _glow_color := Color.WHITE


static func make(p_tag: String, fs: int, p_icon_only: bool = false) -> TagChip:
	var c := TagChip.new()
	c.tag = p_tag
	c.font_size = fs
	c.icon_only = p_icon_only
	c.custom_minimum_size = Vector2(width_of(p_tag, fs, p_icon_only), fs + 6)
	return c


static func width_of(p_tag: String, fs: int, p_icon_only: bool) -> float:
	if p_icon_only:
		return fs + 2.0
	return fs + ICON_GAP + UITheme.font("serif").get_string_size(p_tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_HELP
	var cat := TagText.category(tag)
	var path := TagText.icon_path(cat)
	if ResourceLoader.exists(path):
		_icon = load(path)
	_color = Color(TagText.CATEGORY_COLORS.get(cat, "#C9CED6"))
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))


func _set_hover(on: bool) -> void:
	_hover = on
	hovered.emit(tag, on)
	queue_redraw()


## Точка, куда бьёт луч.
func anchor() -> Vector2:
	return get_global_rect().get_center()


func flash(col: Color) -> void:
	_glow_color = col
	var tw := create_tween()
	tw.tween_method(_set_glow, 1.0, 0.0, 1.1).set_ease(Tween.EASE_IN)


func _set_glow(v: float) -> void:
	_glow = v
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if _glow > 0.0:
		draw_rect(r.grow(3), Color(_glow_color, 0.28 * _glow))
		draw_rect(r.grow(3), Color(_glow_color, 0.9 * _glow), false, 1.5)
	var fs := float(font_size)
	var y0 := (size.y - fs) / 2.0
	if _icon:
		draw_texture_rect(_icon, Rect2(0, y0, fs, fs), false)
	if icon_only:
		if _hover:
			draw_rect(r.grow(2), Color(_color, 0.8), false, 1.0)
		return
	var f := UITheme.font("serif")
	var base := (size.y + f.get_ascent(font_size) - f.get_descent(font_size)) / 2.0
	var col := _color.lightened(0.25) if _hover else _color
	draw_string(f, Vector2(fs + ICON_GAP, base), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
	draw_line(Vector2(fs + ICON_GAP, base + 2), Vector2(size.x, base + 2), Color(col, 0.9 if _hover else 0.55), 1.0)
