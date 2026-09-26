class_name HintPopup
extends PanelContainer
## Подсказка обучения (docs/16 Ф12): узкая карточка у правого края — там, куда не заходят окна миссий,
## магазина и лагеря. Несколько — по очереди.

const W := 272.0

var _queue: Array = []
var _title: Label
var _text: Label


func _ready() -> void:
	top_level = true
	z_index = 80
	mouse_filter = Control.MOUSE_FILTER_STOP
	var st := UITheme.box(Color(0.07, 0.07, 0.09, 0.97), Palette.GOLD.darkened(0.2), 1, 8, 14)
	st.shadow_color = Color(0, 0, 0, 0.6)
	st.shadow_size = 18
	add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	v.add_child(UITheme.label("ПОДСКАЗКА", "sans_bold", 13, Palette.GOLD))
	_title = UITheme.label("", "title_bold", 22, Palette.TEXT)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = W - 28
	v.add_child(_title)
	_text = UITheme.label("", "serif", 17, Palette.SILVER)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = W - 28
	v.add_child(_text)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	v.add_child(row)
	var ok := Button.new()
	ok.text = "ПОНЯТНО"
	ok.custom_minimum_size = Vector2(W - 28, 38)
	ok.add_theme_font_override("font", UITheme.font("caps"))
	ok.add_theme_font_size_override("font_size", 16)
	ok.pressed.connect(_next)
	row.add_child(ok)
	var off := Button.new()
	off.text = "Больше не показывать"
	off.flat = true
	off.add_theme_font_size_override("font_size", 15)
	off.add_theme_color_override("font_color", Palette.TEXT_DIM)
	off.pressed.connect(func() -> void:
		SettingsService.set_value("tutorial", false)
		_queue.clear()
		visible = false)
	row.add_child(off)
	visible = false
	EventBus.tutorial_hint.connect(push)


func push(h: Dictionary) -> void:
	_queue.append(h)
	if not visible:
		_next()


func _next() -> void:
	if _queue.is_empty():
		visible = false
		return
	var h: Dictionary = _queue.pop_front()
	_title.text = str(h.get("title", ""))
	_text.text = str(h.get("text", ""))
	visible = true
	AudioManager.play("open", -10.0, 1.3)
	await get_tree().process_frame
	if not is_instance_valid(self):
		return
	size = get_combined_minimum_size()
	var vp := get_viewport_rect().size
	global_position = Vector2(vp.x - size.x - 6.0, 84.0)
