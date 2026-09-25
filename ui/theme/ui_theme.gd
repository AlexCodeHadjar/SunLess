class_name UITheme
extends RefCounted
## Шрифты и общая тема. Тема строится в коде, чтобы все размеры были в одном месте.

static var _theme: Theme
static var _fonts := {}


static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var f: Font
	match kind:
		"title":  # Cormorant Garamond SemiBold
			f = _variable("res://ui/fonts/CormorantGaramond-Variable.ttf", 600)
		"title_bold":
			f = _variable("res://ui/fonts/CormorantGaramond-Variable.ttf", 700)
		"title_italic":
			f = _variable("res://ui/fonts/CormorantGaramond-Italic-Variable.ttf", 500)
		"caps":
			f = load("res://ui/fonts/CormorantSC-SemiBold.ttf")
		"serif":
			f = load("res://ui/fonts/PT_Serif-Regular.ttf")
		"serif_italic":
			f = load("res://ui/fonts/PT_Serif-Italic.ttf")
		"sans_bold":
			f = load("res://ui/fonts/PT_Sans-Bold.ttf")
		_:
			f = load("res://ui/fonts/PT_Sans-Regular.ttf")
	_fonts[kind] = f
	return f


static func _variable(path: String, weight: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = load(path)
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return fv


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("sans")
	t.default_font_size = 18
	t.set_color("font_color", "Label", Palette.TEXT)
	t.set_color("default_color", "RichTextLabel", Palette.TEXT)
	t.set_font("normal_font", "RichTextLabel", font("serif"))
	t.set_font("italics_font", "RichTextLabel", font("serif_italic"))
	t.set_font("bold_font", "RichTextLabel", font("sans_bold"))
	t.set_font_size("normal_font_size", "RichTextLabel", 20)

	t.set_stylebox("normal", "Button", box(Palette.BG_RAISED, Palette.LINE, 1, 4, 10))
	t.set_stylebox("hover", "Button", box(Palette.BG_RAISED.lightened(0.08), Palette.SILVER, 1, 4, 10))
	t.set_stylebox("pressed", "Button", box(Palette.BG_PANEL, Palette.SILVER, 2, 4, 10))
	t.set_stylebox("disabled", "Button", box(Palette.BG_PANEL, Palette.LINE.darkened(0.3), 1, 4, 10))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), Palette.SILVER, 1, 4, 10))
	t.set_color("font_color", "Button", Palette.TEXT)
	t.set_color("font_hover_color", "Button", Palette.SILVER)
	t.set_color("font_disabled_color", "Button", Palette.TEXT_DIM.darkened(0.3))
	t.set_font("font", "Button", font("sans"))
	t.set_font_size("font_size", "Button", 18)

	t.set_stylebox("panel", "PanelContainer", box(Palette.BG_PANEL, Palette.LINE, 1, 4, 0))
	t.set_stylebox("panel", "Panel", box(Palette.BG_PANEL, Palette.LINE, 1, 4, 0))
	t.set_stylebox("panel", "TooltipPanel", box(Palette.BG_DEEP, Palette.LINE, 1, 4, 8))
	t.set_color("font_color", "TooltipLabel", Palette.TEXT)
	t.set_font_size("font_size", "TooltipLabel", 16)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.LINE
	sb.content_margin_top = 6
	t.set_stylebox("scroll", "HScrollBar", sb)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Palette.TEXT_DIM
	grab.set_corner_radius_all(3)
	t.set_stylebox("grabber", "HScrollBar", grab)
	t.set_stylebox("grabber_highlight", "HScrollBar", grab)
	t.set_stylebox("scroll", "VScrollBar", sb)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	_theme = t
	return t


static func box(bg: Color, border: Color, width: int = 1, radius: int = 4, pad: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	s.anti_aliasing = true
	return s


static func label(text: String, kind: String = "sans", size: int = 18, color: Color = Palette.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static var _emblems := {}


## Серебряные эмблемы из дизайна (Игра/assets/icons): power, will, cunning, monster, enhancement, character, story.
static func emblem(name: String) -> Texture2D:
	if not _emblems.has(name):
		var p := "res://art/ui/emblems/%s.png" % name
		_emblems[name] = load(p) if ResourceLoader.exists(p) else null
	return _emblems[name]


static func stat_icon(stat: String) -> Texture2D:
	var e := emblem(stat)
	return e if e else load("res://art/ui/icon_%s.png" % stat)


## Русское склонение по числу: plural(2, ["осколок", "осколка", "осколков"]) → «осколка».
static func plural(n: int, forms: Array) -> String:
	var m10 := absi(n) % 10
	var m100 := absi(n) % 100
	if m10 == 1 and m100 != 11:
		return str(forms[0])
	if m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14):
		return str(forms[1])
	return str(forms[2])
