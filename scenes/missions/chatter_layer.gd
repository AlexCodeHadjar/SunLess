class_name ChatterLayer
extends Control
## Пузыри мыслей и реплик над картами героев в нижнем ряду (ChatterRules, data/chatter.json; просьбы владельца 03.10):
## редко (раз в минуту-полторы, settings.every) и по делу — место, сюжет, Воспоминания в кармашках.
## Реплика — светлый пузырь с хвостиком к карте; мысль — тёмное облачко с кружками; высказывание — курсив с золотой
## кромкой. Диалог — реплики по очереди над картами разных героев (следующая начинается, пока видна предыдущая).
## Молчат, пока открыто окно, подсказка или выключена настройка «Мысли и реплики героев».

const MAX_W := 270.0

var cards_of: Callable   # () -> Dictionary: герой -> его карта (Control) в нижнем ряду
var can_talk: Callable   # () -> bool: можно ли сейчас говорить (нет окон и подсказок)
var _rng := RandomNumberGenerator.new()
var _next := 8.0
var _recent: Array = []
var _queue: Array = []     # [герой, вид, текст] — следующие реплики диалога
var _gap := 0.0
var _bubbles := {}         # герой -> пузырь (у героя один пузырь сразу)
var _poke := ""            # событие экрана: реплика к нему вне очереди


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	var first: Array = _cfg().get("first", [6, 10])
	_next = _rng.randf_range(float(first[0]), float(first[1]))


func _cfg() -> Dictionary:
	return ContentDB.data.chatter.get("settings", {})


static func enabled() -> bool:
	return bool(SettingsService.get_value("chatter"))


## Событие экрана (after_win, after_loss, after_night, move): с шансом — реплика к нему вскоре.
func poke(event: String) -> void:
	if not enabled() or not _queue.is_empty() or _rng.randf() > float(_cfg().get("poke_chance", 0.75)):
		return
	_poke = event
	_next = minf(_next, 1.2)


func _process(delta: float) -> void:
	var ok := enabled() and (not can_talk.is_valid() or bool(can_talk.call()))
	if not ok:
		if not _bubbles.is_empty() or not _queue.is_empty():
			hush()
		return
	if not _queue.is_empty():
		_gap -= delta
		if _gap <= 0.0:
			_say_next()
		return
	_next -= delta
	if _next > 0.0:
		return
	var every: Array = _cfg().get("every", [16, 30])
	_next = _rng.randf_range(float(every[0]), float(every[1]))
	_speak()


func _speak() -> void:
	var cards: Dictionary = cards_of.call() if cards_of.is_valid() else {}
	var heroes: Array = []
	for cid: String in cards:
		var cv: Control = cards[cid]
		if is_instance_valid(cv) and cv.is_visible_in_tree() and GameState.state.is_alive(cid):
			heroes.append(cid)
	var ev := _poke
	_poke = ""
	if heroes.is_empty():
		return
	var r := ChatterRules.pick(ContentDB.data, GameState.state, heroes, [ev] if ev != "" else [], ev != "", _recent, _rng)
	if r.is_empty():
		return
	_recent.append(r["id"])
	while _recent.size() > int(_cfg().get("recent", 24)):
		_recent.pop_front()
	_queue = (r["lines"] as Array).duplicate()
	_gap = 0.0
	_say_next()


func _say_next() -> void:
	var l: Array = _queue.pop_front()
	_bubble(str(l[0]), str(l[1]), str(l[2]))
	_gap = ChatterRules.hold(str(l[2])) + 0.3   # реплики диалога — по очереди: следующая, когда прочитана эта


## Все замолкают (открылось окно): пузыри быстро гаснут, диалог обрывается.
func hush() -> void:
	_queue.clear()
	for cid: String in _bubbles:
		var b: Control = _bubbles[cid]
		if is_instance_valid(b):
			var tw := b.create_tween()
			tw.tween_property(b, "modulate:a", 0.0, 0.15)
			tw.tween_callback(b.queue_free)
	_bubbles.clear()


func _bubble(cid: String, kind: String, text: String) -> void:
	var cards: Dictionary = cards_of.call() if cards_of.is_valid() else {}
	if not cards.has(cid) or not is_instance_valid(cards[cid]):
		return
	if _bubbles.has(cid) and is_instance_valid(_bubbles[cid]):
		(_bubbles[cid] as Control).queue_free()
	var card: Control = cards[cid]
	var bg := Color(0.93, 0.91, 0.86, 0.97)
	var edge := Color(0.2, 0.18, 0.15, 0.9)
	var col := Color(0.09, 0.08, 0.1)
	var font := "sans"
	var fs := 15
	match kind:
		"thought":
			bg = Color(0.055, 0.06, 0.085, 0.93)
			edge = Color(0.62, 0.66, 0.76, 0.7)
			col = Color(0.84, 0.87, 0.94)
			font = "serif_italic"
			fs = 17
		"wisdom":
			bg = Color(0.06, 0.05, 0.035, 0.94)
			edge = Color(Palette.GOLD, 0.85)
			col = Color(1.0, 0.9, 0.68)
			font = "serif_italic"
			fs = 17
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var panel := PanelContainer.new()
	var st := UITheme.box(bg, edge, 1, 14 if kind != "say" else 10, 0)
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 8
	st.content_margin_bottom = 9
	panel.add_theme_stylebox_override("panel", st)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(panel)
	var shown := text
	var lbl := UITheme.label(shown, font, fs, col)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var f := UITheme.font(font)
	lbl.custom_minimum_size.x = minf(f.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 2.0, MAX_W)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)
	panel.reset_size()
	var ps := panel.get_combined_minimum_size()
	panel.size = ps
	# хвостик к карте: у реплики и высказывания — уголок, у мысли — кружки
	var tail := Control.new()
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tail)
	var cr := card.get_global_rect()
	var scr := get_viewport_rect().size
	var x := clampf(cr.get_center().x - ps.x / 2.0, 8.0, scr.x - ps.x - 8.0)
	var y := cr.position.y - ps.y - 16.0
	holder.position = Vector2(x, y)
	# пузырь соседа, который этот закрыл бы, гаснет: два пузыря друг на друге не лежат
	var mine := Rect2(Vector2(x, y), ps).grow(6.0)
	for other: String in _bubbles.keys():
		var ob: Control = _bubbles[other]
		if other == cid or not is_instance_valid(ob):
			continue
		var op := ob.get_child(0) as Control
		if mine.intersects(Rect2(ob.position, op.size)):
			_bubbles.erase(other)
			var ft := ob.create_tween()
			ft.tween_property(ob, "modulate:a", 0.0, 0.15)
			ft.tween_callback(ob.queue_free)
	var tip := Vector2(cr.get_center().x - x, ps.y + 14.0)
	tail.draw.connect(func() -> void:
		if kind == "thought":
			tail.draw_circle(tip + Vector2(-6, -8), 4.5, bg)
			tail.draw_arc(tip + Vector2(-6, -8), 4.5, 0.0, TAU, 16, edge, 1.0, true)
			tail.draw_circle(tip + Vector2(-1, 0), 2.6, bg)
			tail.draw_arc(tip + Vector2(-1, 0), 2.6, 0.0, TAU, 12, edge, 1.0, true)
		else:
			var bx := clampf(tip.x, 18.0, ps.x - 18.0)
			var tri := PackedVector2Array([Vector2(bx - 8, ps.y - 1), Vector2(bx + 8, ps.y - 1), Vector2(tip.x, tip.y - 2)])
			tail.draw_colored_polygon(tri, bg)
			tail.draw_line(tri[0] + Vector2(0, 1), tri[2], edge, 1.0, true)
			tail.draw_line(tri[1] + Vector2(0, 1), tri[2], edge, 1.0, true))
	tail.queue_redraw()
	_bubbles[cid] = holder
	# появление: снизу вверх, затем держится и гаснет
	var quick := Vfx.reduced()
	holder.modulate.a = 0.0
	holder.position.y += 0.0 if quick else 8.0
	var tw := holder.create_tween()
	tw.set_parallel(true)
	tw.tween_property(holder, "modulate:a", 1.0, 0.0 if quick else 0.22)
	tw.tween_property(holder, "position:y", y, 0.0 if quick else 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(ChatterRules.hold(text))
	tw.chain().tween_property(holder, "modulate:a", 0.0, 0.0 if quick else 0.45)
	tw.chain().tween_callback(func() -> void:
		if _bubbles.get(cid) == holder:
			_bubbles.erase(cid)
		holder.queue_free())
