class_name ShopWindow
extends Control
## Окно магазина главы (docs/15 §11): витрина карт за осколки душ.
## Персонаж после покупки сразу встаёт в ряд героев; усиление — в коллекцию, его можно положить в кармашек.

signal closed

const PANEL := Rect2(250, 110, 1420, 820)
const KIND_NAMES := {"character": "Персонаж", "enhancement": "Усиление"}

var shop_id := ""
var _body: VBoxContainer
var _status: Label
var _row: HBoxContainer


static func open_for(parent: Node, sid: String) -> ShopWindow:
	var w := ShopWindow.new()
	w.shop_id = sid
	parent.add_child(w)
	return w


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(dim)
	var panel := PanelContainer.new()
	panel.position = PANEL.position
	panel.size = PANEL.size
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.055, 0.055, 0.08, 0.98), Palette.COINS.darkened(0.45), 1, 6, 0))
	add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(m)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 16)
	m.add_child(_body)
	var sh: Dictionary = ContentDB.data.shops[shop_id]
	var head := HBoxContainer.new()
	var t := UITheme.label(str(sh.get("name", shop_id)), "title_bold", 40, Palette.TEXT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := Button.new()
	x.text = "✕"
	x.flat = true
	x.add_theme_font_size_override("font_size", 26)
	x.pressed.connect(close)
	head.add_child(x)
	_body.add_child(head)
	var text := UITheme.label(str(sh.get("text", "")), "serif_italic", 19, Palette.SILVER)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = PANEL.size.x - 56
	_body.add_child(text)
	_status = UITheme.label("", "sans_bold", 19, Palette.COINS)
	_body.add_child(_status)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(center)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 34)
	center.add_child(_row)
	GameState.shop_seen(shop_id)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	closed.emit()
	queue_free()


func _refresh() -> void:
	var c := ContentDB.data
	var s := GameState.state
	var cur := ShopRules.ensure(c, s, shop_id)
	var left := ShopRules.missions_to_refresh(c, s, shop_id)
	var shards := int(s.resources.get("shards", 0))
	_status.text = "У вас ✧ %d %s душ   ·   новый товар через %d %s" % [shards, UITheme.plural(shards, ["осколок", "осколка", "осколков"]), left, ShopIcon._missions_word(left)]
	for ch in _row.get_children():
		ch.queue_free()
	var items: Array = cur["items"]
	if items.is_empty():
		_row.add_child(UITheme.label("Прилавок пуст — загляните после следующих миссий.", "serif_italic", 22, Palette.TEXT_DIM))
		return
	for it: Dictionary in items:
		_row.add_child(_item(it))


func _item(it: Dictionary) -> Control:
	var c := ContentDB.data
	var s := GameState.state
	var card := str(it["card"])
	var sold := bool(it.get("sold", false)) or s.owns(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var cv := CardView.make(card, CardView.SIZE_ZOOM * 0.78, false)
	cv.dimmed = sold
	cv.inspect_requested.connect(func(id: String) -> void: CardInspector.open_for(self, id))
	v.add_child(cv)
	var kind := UITheme.label(KIND_NAMES.get(c.card_kind(card), ""), "sans", 16, Palette.TEXT_DIM)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(kind)
	var b := Button.new()
	b.custom_minimum_size = Vector2(cv.size.x, 52)
	b.add_theme_font_override("font", UITheme.font("caps"))
	b.add_theme_font_size_override("font_size", 20)
	var price := int(it["price"])
	if sold:
		b.text = "ПРОДАНО"
		b.disabled = true
	else:
		b.text = "✧ %d   КУПИТЬ" % price
		var enough := int(s.resources.get("shards", 0)) >= price
		b.disabled = not enough
		if not enough:
			b.tooltip_text = "Не хватает осколков душ"
		b.pressed.connect(_buy.bind(card))
	v.add_child(b)
	return v


func _buy(card: String) -> void:
	var err := GameState.shop_buy(shop_id, card)
	if err != "":
		EventBus.toast.emit(err)
	else:
		var what := "К отряду присоединяется" if ContentDB.data.card_kind(card) == "character" else "Куплено:"
		EventBus.toast.emit("%s %s" % [what, ContentDB.data.card_name(card)])
	_refresh()
