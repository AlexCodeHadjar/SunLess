class_name ShopWindow
extends Control
## Окно магазина главы (docs/15 §11): витрина карт за осколки душ.
## Персонаж после покупки сразу встаёт в ряд героев; усиление — в коллекцию, его можно положить в кармашек.
## Вкладка «Услуги» (docs/16 §9): лечение травм, заточка и починка усилений — ServiceRules.

signal closed

const PANEL := Rect2(250, 110, 1420, 820)
const KIND_NAMES := {"character": "Персонаж", "enhancement": "Усиление"}

var shop_id := ""
var _body: VBoxContainer
var _status: Label
var _row: HBoxContainer
var _center: CenterContainer
var _svc: ScrollContainer
var _tab := "goods"
var _tabs: Array = []


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
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	_body.add_child(bar)
	_status = UITheme.label("", "sans_bold", 19, Palette.COINS)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_status)
	if not Array(sh.get("services", [])).is_empty():
		for tt: Array in [["ТОВАР", "goods"], ["УСЛУГИ", "services"]]:
			var tb := Button.new()
			tb.text = tt[0]
			tb.toggle_mode = true
			tb.custom_minimum_size = Vector2(170, 44)
			tb.add_theme_font_override("font", UITheme.font("caps"))
			tb.add_theme_font_size_override("font_size", 18)
			tb.set_meta("tab", tt[1])
			tb.pressed.connect(func() -> void:
				_tab = tt[1]
				_refresh())
			bar.add_child(tb)
			_tabs.append(tb)
	_center = CenterContainer.new()
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_center)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 34)
	_center.add_child(_row)
	_svc = ScrollContainer.new()
	_svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_svc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_svc.visible = false
	_body.add_child(_svc)
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
	for tb: Button in _tabs:
		tb.button_pressed = tb.get_meta("tab") == _tab
	_center.visible = _tab == "goods"
	_svc.visible = _tab == "services"
	if _tab == "services":
		_status.text = "У вас ✧ %d %s душ" % [shards, UITheme.plural(shards, ["осколок", "осколка", "осколков"])]
		_build_services()
		return
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


# --- услуги -----------------------------------------------------------------------

func _build_services() -> void:
	for ch in _svc.get_children():
		ch.queue_free()
	var c := ContentDB.data
	var s := GameState.state
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_svc.add_child(cols)
	var heal: Array = []
	var sharpen: Array = []
	var unwear: Array = []
	if ServiceRules.offers(c, shop_id, "heal"):
		for cid: String in MissionFlow.heroes(c, s):
			for tid: String in s.character(cid).get("traumas", []):
				heal.append(_svc_row(cid, "%s — %s" % [c.card_name(cid), c.card_name(tid)],
					"на миссии" if MissionFlow.on_mission(s, cid) else "", ServiceRules.heal_price(c, tid), "ЛЕЧИТЬ",
					_service.bind("heal", cid, tid), MissionFlow.on_mission(s, cid)))
	for card: String in s.collection:
		if c.card_kind(card) != "enhancement":
			continue
		if ServiceRules.offers(c, shop_id, "sharpen") and not Array(c.enhancements.get(card, {}).get("bonuses", [])).is_empty():
			var done := ServiceRules.sharpened(s, card)
			var bon: Dictionary = c.enhancements[card]["bonuses"][0]
			sharpen.append(_svc_row(card, c.card_name(card), "заточено до конца главы" if done else "+1 %s в проверках до конца главы" % Palette.STAT_NAMES.get(str(bon.get("stat", "")), ""),
				ServiceRules.SHARPEN_PRICE, "ЗАТОЧИТЬ", _service.bind("sharpen", card, ""), done))
		if ServiceRules.offers(c, shop_id, "unwear") and WearRules.wears(c, s, card) and WearRules.current(s, card) > WearRules.START:
			unwear.append(_svc_row(card, c.card_name(card), "износ %d%% → %d%%" % [WearRules.current(s, card), WearRules.START],
				ServiceRules.UNWEAR_PRICE, "ПОЧИНИТЬ", _service.bind("unwear", card, ""), false))
	for col: Array in [["heal", "Лечение травм", heal, "Травм нет — лечить некого."], ["sharpen", "Заточка", sharpen, "Нечего затачивать."],
			["unwear", "Починка", unwear, "Всё цело."]]:
		if not ServiceRules.offers(c, shop_id, col[0]):
			continue
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(v)
		v.add_child(UITheme.label(col[1], "caps", 22, Palette.SILVER))
		if Array(col[2]).is_empty():
			v.add_child(UITheme.label(col[3], "serif_italic", 18, Palette.TEXT_DIM))
		for r: Control in col[2]:
			v.add_child(r)


func _svc_row(card: String, title: String, note: String, price: int, verb: String, action: Callable, blocked: bool) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var cv := CardView.make(card, Vector2(70, 120), false)
	cv.inspect_requested.connect(func(id: String) -> void: CardInspector.open_for(self, id))
	h.add_child(cv)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var t := UITheme.label(title, "sans_bold", 17, Palette.TEXT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 250
	v.add_child(t)
	if note != "":
		v.add_child(UITheme.label(note, "sans", 15, Palette.TEXT_DIM))
	var b := Button.new()
	b.text = "✧ %d   %s" % [price, verb]
	b.custom_minimum_size = Vector2(200, 40)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_override("font", UITheme.font("caps"))
	b.add_theme_font_size_override("font_size", 16)
	var enough := int(GameState.state.resources.get("shards", 0)) >= price
	b.disabled = blocked or not enough
	if not enough:
		b.tooltip_text = "Не хватает осколков душ"
	b.pressed.connect(action)
	v.add_child(b)
	return h


func _service(kind: String, target: String, extra: String) -> void:
	var err := GameState.shop_service(shop_id, kind, target, extra)
	if err != "":
		EventBus.toast.emit(err)
	else:
		EventBus.toast.emit("%s: %s" % [ServiceRules.NAMES.get(kind, kind), ContentDB.data.card_name(extra if kind == "heal" else target)])
	_refresh()


func _buy(card: String) -> void:
	var err := GameState.shop_buy(shop_id, card)
	if err != "":
		EventBus.toast.emit(err)
	else:
		var what := "К отряду присоединяется" if ContentDB.data.card_kind(card) == "character" else "Куплено:"
		EventBus.toast.emit("%s %s" % [what, ContentDB.data.card_name(card)])
	_refresh()
