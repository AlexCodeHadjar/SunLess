class_name MemoryChoice
extends Control
## Выбор Воспоминания (docs/16 §11.3, LootRules): три карты усилений раскрываются по одной;
## взять можно только одну — выбранная вспыхивает и уходит в коллекцию, остальные рассыпаются.

signal done

const CARD := Vector2(280, 480)
const GAP := 70.0
const RARITY_NAMES := {"common": "Обычная", "rare": "Редкая", "epic": "Эпическая", "legendary": "Легендарная"}

var offer: Dictionary = {}
var _slots: Array = []        # [{box: Control, card: CardView, id}]
var _busy := false


static func open(parent: Node, p_offer: Dictionary) -> MemoryChoice:
	var w := MemoryChoice.new()
	w.offer = p_offer
	parent.add_child(w)
	return w


func _ready() -> void:
	# размер — явно: окно открывается из _process карты, якоря ещё не пересчитаны
	position = Vector2.ZERO
	var par := get_parent() as Control
	size = par.size if par != null and par.size.x > 0.0 else Vector2(1920, 1080)
	var w := size.x
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.012, 0.02, 0.86)
	dim.position = Vector2(-400, -400)
	dim.size = size + Vector2(800, 800)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var c := ContentDB.data
	var title := UITheme.label("Воспоминание", "title", 52, Palette.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 92)
	title.size = Vector2(w, 68)
	add_child(title)
	var sub := UITheme.label("«%s» · %s. Возьмите одну карту — остальные рассыпятся." % [offer.get("title", ""),
		LootRules.TIER_NAMES.get(str(offer.get("tier", "")), "")], "sans", 21, Palette.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(0, 164)
	sub.size = Vector2(w, 36)
	add_child(sub)
	var ids: Array = offer.get("options", [])
	var total := ids.size() * CARD.x + (ids.size() - 1) * GAP
	var x0 := (w - total) / 2.0
	for i in ids.size():
		var id := str(ids[i])
		var e: Dictionary = c.enhancements.get(id, {})
		var box := Control.new()
		box.position = Vector2(x0 + i * (CARD.x + GAP), 240)
		box.size = Vector2(CARD.x, 760)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(box)
		var cv := CardView.make(id, CARD, false)
		cv.pivot_offset = CARD / 2.0
		cv.clicked.connect(func(_x: String) -> void: _choose(i))
		cv.mouse_entered.connect(func() -> void: _hover(i, true))
		cv.mouse_exited.connect(func() -> void: _hover(i, false))
		box.add_child(cv)
		var rar := str(e.get("rarity", "common"))
		var rl := UITheme.label(RARITY_NAMES.get(rar, rar), "title", 24, Palette.RARITY.get(rar, Palette.SILVER))
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rl.position = Vector2(0, CARD.y + 12)
		rl.size = Vector2(CARD.x, 30)
		box.add_child(rl)
		var tx := UITheme.label(_describe(c, e), "sans", 17, Palette.TEXT)
		tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tx.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tx.position = Vector2(-20, CARD.y + 48)
		tx.size = Vector2(CARD.x + 40, 200)
		box.add_child(tx)
		_slots.append({"box": box, "card": cv, "id": id})
		# раскрытие по одной: карта разворачивается из ребра
		if not Vfx.reduced():
			box.modulate.a = 0.0
			cv.scale = Vector2(0.05, 1.0)
			var tw := create_tween()
			tw.tween_interval(0.25 + 0.3 * i)
			tw.tween_callback(func() -> void: AudioManager.play("open", -8.0, 0.9 + 0.1 * i))
			tw.tween_property(box, "modulate:a", 1.0, 0.15)
			tw.parallel().tween_property(cv, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var skip := Button.new()
	skip.text = "Распылить на осколки (+%d ✧)" % int(ContentDB.data.loot.get("dust", 5))
	skip.flat = true
	skip.add_theme_font_size_override("font_size", 18)
	skip.add_theme_color_override("font_color", Palette.COINS)
	skip.position = Vector2(w / 2.0 - 160, 1000)
	skip.size = Vector2(320, 40)
	skip.pressed.connect(func() -> void: _finish(""))
	add_child(skip)


func _describe(c: Content, e: Dictionary) -> String:
	var t := str(e.get("text", ""))
	var m: Dictionary = e.get("memory", {})
	if not m.is_empty():
		t += "\nНавык «%s»: %s — %s" % [m.get("name", ""), str(m.get("cond", "")).to_lower(), m.get("text", "")]
	if e.has("weapon"):
		t += "\nОружие: %s" % e["weapon"]
	return t


func _hover(i: int, on: bool) -> void:
	if _busy:
		return
	var cv: CardView = _slots[i]["card"]
	create_tween().tween_property(cv, "scale", Vector2(1.05, 1.05) if on else Vector2.ONE, 0.12)


func _choose(i: int) -> void:
	if _busy:
		return
	_busy = true
	AudioManager.play("bell", -4.0, 1.3)
	for j in _slots.size():
		var box: Control = _slots[j]["box"]
		var cv: CardView = _slots[j]["card"]
		var tw := create_tween().set_parallel(true)
		if j == i:
			# выбранная: вспышка и подъём
			tw.tween_property(cv, "scale", Vector2(1.14, 1.14), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(cv, "modulate", Color(1.5, 1.4, 1.1), 0.2)
			tw.chain().tween_property(cv, "modulate", Color.WHITE, 0.4)
		else:
			# остальные рассыпаются: тускнеют, падают и сжимаются
			tw.tween_property(box, "modulate:a", 0.0, 0.6).set_delay(0.1)
			tw.tween_property(box, "position:y", box.position.y + 90.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(cv, "scale", Vector2(0.8, 0.8), 0.6)
			tw.tween_property(cv, "rotation", deg_to_rad(-8.0 if j < i else 8.0), 0.6)
	var id := str(_slots[i]["id"])
	get_tree().create_timer(1.1).timeout.connect(func() -> void: _finish(id))


func _finish(id: String) -> void:
	var out := GameState.take_memory(id)
	if id == "":
		AudioManager.play("bell", -8.0, 1.6)
		EventBus.toast.emit("Воспоминание распалось на осколки: +%d ✧" % int(ContentDB.data.loot.get("dust", 5)))
	elif not out.is_empty():
		EventBus.toast.emit("В коллекции: %s" % ContentDB.data.card_name(id))
	done.emit()
	queue_free()
