class_name CardView
extends Control
## Одна карточка 7:12. Если у карты есть готовый арт — рисует его и накладывает живые значения;
## иначе рисует гравюрную рамку по спецификации (docs/11 §3).

signal clicked(card_id: String)
signal burned

const SIZE_PANEL := Vector2(140, 240)
const SIZE_SIDE := Vector2(112, 192)
const SIZE_POCKET := Vector2(210, 360)
const SIZE_FAN := Vector2(126, 216)
const SIZE_ZOOM := Vector2(280, 480)
const SIZE_TRAUMA := Vector2(84, 144)

var card_id := ""
var kind := ""          # character | enhancement | initiator | trauma | event
var draggable := true
var hover_lift := true
var dimmed := false
var highlight := false
var badge := ""          # короткая метка снизу: «Черновик: E03»
var sway := false        # лёгкое покачивание (карты событий на карте мира)
var smoke_on_hover := true
var _hover := false
var _smoke: CPUParticles2D
var _phase := randf() * TAU
var _burning := false
var _lift := 0.0
var _tex: Texture2D
var _art_framed := false


static func make(id: String, size_px: Vector2, can_drag: bool = true) -> CardView:
	var c := CardView.new()
	c.card_id = id
	c.custom_minimum_size = size_px
	c.size = size_px
	c.draggable = can_drag
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c._init_card()
	return c


func _init_card() -> void:
	var content := ContentDB.data
	kind = content.card_kind(card_id)
	if kind == "" and content.events.has(card_id):
		kind = "event"
	var def := _def()
	var art: String = def.get("art", "")
	if art != "" and ResourceLoader.exists(art):
		_tex = load(art)
		_art_framed = bool(def.get("art_has_frame", false))
	tooltip_text = " "  # включает кастомную подсказку-увеличение
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))


func _def() -> Dictionary:
	var c := ContentDB.data
	match kind:
		"character": return c.characters.get(card_id, {})
		"enhancement": return c.enhancements.get(card_id, {})
		"initiator": return c.initiators.get(card_id, {})
		"trauma": return c.traumas.get(card_id, {})
		"event": return c.events.get(card_id, {})
	return {}


func _on_hover(on: bool) -> void:
	if _burning:
		return
	_hover = on
	_animate_lift()
	if on:
		AudioManager.play("hover", -12.0)
	if smoke_on_hover and not Vfx.reduced():
		if _smoke == null and on:
			_smoke = Vfx.card_smoke(size)
			_smoke.show_behind_parent = true
			add_child(_smoke)
		if _smoke:
			_smoke.emitting = on
	set_process(sway or _hover)


func _ready() -> void:
	pivot_offset = size / 2
	set_process(sway)


func _process(_delta: float) -> void:
	if _burning or Vfx.reduced():
		rotation = 0.0
		return
	var target := 0.0
	if _hover:
		# наклон к курсору, не больше 6°
		var dx := (get_local_mouse_position().x - size.x / 2) / size.x
		target = deg_to_rad(clampf(dx * 10.0, -6.0, 6.0))
	elif sway:
		target = deg_to_rad(sin(Time.get_ticks_msec() / 1000.0 * 0.9 + _phase) * 1.4)
	rotation = lerp_angle(rotation, target, 0.15)


## Карта сгорает и осыпается пеплом; по окончании — сигнал burned и удаление.
func burn(duration: float = 1.3) -> void:
	_burning = true
	_hover = false
	_lift = 0.0
	if _smoke:
		_smoke.emitting = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	AudioManager.play("ash", -4.0, 0.6)
	if Vfx.reduced():
		var tw0 := create_tween()
		tw0.tween_property(self, "modulate:a", 0.0, 0.3)
		tw0.finished.connect(_on_burned)
		return
	material = Vfx.dissolve_material(size)
	var parent := get_parent()
	var rect := Rect2(position, size)
	var ash := Vfx.ash_burst(rect)
	var embers := Vfx.embers_burst(rect)
	parent.add_child(ash)
	parent.add_child(embers)
	Vfx.autofree(ash)
	Vfx.autofree(embers)
	var tw := create_tween()
	tw.tween_method(_set_burn, 0.0, 1.0, duration).set_ease(Tween.EASE_IN)
	tw.finished.connect(_on_burned)


func _set_burn(v: float) -> void:
	(material as ShaderMaterial).set_shader_parameter("progress", v)


func _on_burned() -> void:
	burned.emit()
	queue_free()


## Короткая дрожь (событие устояло после провала).
func shudder() -> void:
	if Vfx.reduced():
		return
	var base := position
	var tw := create_tween()
	for i in 6:
		tw.tween_property(self, "position", base + Vector2(randf_range(-4, 4), randf_range(-2, 2)), 0.04)
	tw.tween_property(self, "position", base, 0.05)


func _set_lift(v: float) -> void:
	_lift = v
	queue_redraw()


func _animate_lift() -> void:
	if not hover_lift or SettingsService.get_value("reduce_motion"):
		_lift = 12.0 if _hover else 0.0
		queue_redraw()
		return
	var tw := create_tween()
	tw.tween_method(_set_lift, _lift, 12.0 if _hover else 0.0, 0.12)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if get_global_rect().has_point(get_global_mouse_position()):
			clicked.emit(card_id)
			accept_event()


func _get_drag_data(_at: Vector2) -> Variant:
	if not draggable or dimmed:
		return null
	var preview := CardView.make(card_id, SIZE_PANEL * 0.9, false)
	preview.hover_lift = false
	preview.modulate.a = 0.85
	preview.rotation = deg_to_rad(-4)
	var holder := Control.new()
	holder.add_child(preview)
	preview.position = -SIZE_PANEL * 0.45
	set_drag_preview(holder)
	return {"card": card_id, "kind": kind}


func _make_custom_tooltip(_for_text: String) -> Object:
	if size.x >= SIZE_ZOOM.x - 1:
		return null
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var big := CardView.make(card_id, SIZE_ZOOM, false)
	big.hover_lift = false
	big.badge = badge
	box.add_child(big)
	var info := describe()
	if info != "":
		var l := RichTextLabel.new()
		l.bbcode_enabled = true
		l.fit_content = true
		l.custom_minimum_size = Vector2(300, 0)
		l.text = info
		l.add_theme_font_size_override("normal_font_size", 18)
		box.add_child(l)
	return box


## Текст для увеличенного просмотра.
func describe() -> String:
	var c := ContentDB.data
	var d := _def()
	var s := GameState.state
	var lines: Array[String] = ["[font_size=24][b]%s[/b][/font_size]" % str(d.get("name", d.get("title", card_id)))]
	match kind:
		"character":
			var ch: Dictionary = s.character(card_id) if s else {}
			var stage := c.stage_name(card_id, str(ch.get("stage", "")))
			if stage != "":
				lines.append("Стадия: %s" % stage)
			lines.append(str(d.get("role", "")))
			for tr: Dictionary in d.get("traits", []):
				lines.append("• %s — %s" % [tr.get("name", ""), tr.get("text", "")])
			for aid: String in ch.get("abilities", []):
				var a: Dictionary = c.abilities.get(aid, {})
				lines.append("[color=#C9CED6]✦ %s[/color] — %s" % [a.get("name", aid), a.get("text", "")])
			var traumas: Array = ch.get("traumas", [])
			if not traumas.is_empty():
				var names: Array = []
				for t: String in traumas:
					names.append(c.card_name(t))
				lines.append("[color=#B65F63]Травмы: %s[/color]" % ", ".join(names))
			var dc := TraumaRules.death_chance(TraumaRules.counted(traumas) + 1)
			if dc > 0:
				lines.append("[color=#B65F63]☠ Шанс смерти при следующей травме: %d%%[/color]" % dc)
		"enhancement":
			lines.append(str(d.get("text", "")))
			if s and WearRules.wears(c, s, card_id):
				lines.append("⚒ Шанс поломки после использования: %d%%" % WearRules.current(s, card_id))
			elif bool(d.get("wears", true)):
				lines.append("⚒ Сейчас не изнашивается")
			else:
				lines.append("Не изнашивается")
			lines.append("[color=#9A9CA6]%s · %s[/color]" % [d.get("canon", ""), d.get("source", "")])
		"initiator":
			lines.append(str(d.get("text", "")))
			lines.append("[color=#9A9CA6]Одноразовый. Перетащите на карту мира.[/color]")
		"trauma":
			var mods: Array = []
			for st: String in d.get("mods", {}):
				mods.append("%+d %s" % [int(d["mods"][st]), Palette.STAT_NAMES.get(st, st)])
			lines.append(", ".join(mods))
		"event":
			lines.append(str(d.get("text", "")))
	return "\n".join(lines)


# --- отрисовка ---------------------------------------------------------------

func _draw() -> void:
	var r := Rect2(Vector2(0, -_lift), size)
	var d := _def()
	var scale_k := size.x / SIZE_PANEL.x
	# тень
	draw_rect(Rect2(r.position + Vector2(0, 6 * scale_k), r.size), Color(0, 0, 0, 0.45 if _hover else 0.35))
	if _tex and _art_framed:
		draw_texture_rect(_tex, r, false)
	else:
		_draw_procedural(r, d, scale_k)
	_draw_overlays(r, d, scale_k)
	var border := _border_color(d)
	var w := 3.0 if (highlight or _hover) else 1.5
	draw_rect(r, border if (highlight or _hover) else border.darkened(0.25), false, w)
	if dimmed:
		draw_rect(r, Color(0.05, 0.05, 0.07, 0.62))


func _border_color(d: Dictionary) -> Color:
	match kind:
		"character": return Palette.SILVER
		"enhancement": return Color("#8C6B45") if d.get("origin", "") != "knowledge" else Palette.REQ_MET.darkened(0.2)
		"initiator": return Palette.INITIATOR.lightened(0.2)
		"trauma": return Palette.TRAUMA_BRIGHT
		"event":
			return Palette.GOLD if d.get("type", "") in ["story", "reward"] else (Palette.INITIATOR.lightened(0.2) if d.get("source_kind", "") == "initiator" else Palette.SILVER.darkened(0.2))
	return Palette.LINE


func _draw_procedural(r: Rect2, d: Dictionary, k: float) -> void:
	var paper := Color("#1B1C23") if kind != "trauma" else Color("#1A0E11")
	draw_rect(r, paper)
	var inset := 7.0 * k
	var inner := r.grow(-inset)
	draw_rect(inner, _border_color(d).darkened(0.55), false, 1.0)
	# верхний маркер: римская цифра события или самоцвет редкости
	var top := inner.position.y + 4 * k
	if kind == "event" and d.has("numeral"):
		_text(UITheme.font("title_bold"), Vector2(r.position.x, top + 18 * k), str(d["numeral"]), 20 * k, Palette.GOLD, r.size.x)
	else:
		var gem: Color = Palette.RARITY.get(d.get("rarity", "common"), Palette.RARITY["common"])
		var c := Vector2(r.get_center().x, top + 8 * k)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6 * k), c + Vector2(6 * k, 0), c + Vector2(0, 6 * k), c + Vector2(-6 * k, 0)]), gem)
	# поле иллюстрации
	var art := Rect2(inner.position + Vector2(0, 24 * k), Vector2(inner.size.x, inner.size.y * 0.56))
	if _tex:
		_draw_cover(_tex, art, 0.0, 0.72)
	else:
		_draw_art_placeholder(art, d, k)
	draw_rect(art, Palette.LINE, false, 1.0)
	# плашка имени
	var plate := Rect2(Vector2(inner.position.x, art.end.y + 4 * k), Vector2(inner.size.x, inner.end.y - art.end.y - 4 * k))
	draw_rect(plate, Color(0, 0, 0, 0.35))
	var name := str(d.get("name", d.get("title", card_id)))
	var title_size := (14.0 if name.length() > 16 else 16.0) * k
	_text_multi(UITheme.font("title"), Vector2(plate.position.x + 2, plate.position.y + title_size + 3 * k), name, title_size, Palette.TEXT, plate.size.x - 4, 2)
	var sub := _subtitle(d)
	if sub != "":
		_text(UITheme.font("sans"), Vector2(plate.position.x + 3, plate.end.y - 5 * k), sub, 10.5 * k, Palette.TEXT_DIM, plate.size.x - 6)


func _subtitle(d: Dictionary) -> String:
	match kind:
		"enhancement":
			return {"knowledge": "Знание", "memory": "Воспоминание", "improvised": "Подручное"}.get(d.get("origin", ""), "Усиление")
		"initiator":
			return "Инициатор · одноразовый"
		"trauma":
			var mods: Array = []
			for st: String in d.get("mods", {}):
				mods.append("%+d %s" % [int(d["mods"][st]), Palette.STAT_SHORT.get(st, st)])
			return " ".join(mods)
		"character":
			var s := GameState.state
			var st2 := ContentDB.data.stage_name(card_id, str(s.character(card_id).get("stage", ""))) if s else ""
			return st2 if st2 != "" else str(d.get("role", "")).split(" /")[0]
		"event":
			var tags: Array = []
			for t: String in Array(d.get("tags", [])).slice(0, 2):
				tags.append(str(ContentDB.data.tags.get(t, {}).get("name", t)))
			return " · ".join(tags)
	return ""


func _draw_art_placeholder(art: Rect2, d: Dictionary, k: float) -> void:
	var top := Color("#2A2D3A")
	var bottom := Color("#101117")
	if kind == "trauma":
		top = Color("#3A1418")
	elif kind == "initiator":
		top = Color("#2E2640")
	var steps := 12
	for i in steps:
		var y0 := art.position.y + art.size.y * i / steps
		draw_rect(Rect2(art.position.x, y0, art.size.x, art.size.y / steps + 1), top.lerp(bottom, float(i) / steps))
	if kind == "trauma":
		# трещина
		var c := art.get_center()
		var pts := PackedVector2Array([c + Vector2(-art.size.x * 0.35, -art.size.y * 0.2), c + Vector2(-8 * k, -4 * k), c + Vector2(6 * k, 10 * k), c + Vector2(art.size.x * 0.3, art.size.y * 0.25)])
		draw_polyline(pts, Palette.TRAUMA_BRIGHT, 2.0 * k)
		return
	var glyph := ""
	match kind:
		"initiator": glyph = "🕯"
		"event": glyph = "✦"
		_:
			var n := str(d.get("name", d.get("title", "?")))
			glyph = n.substr(0, 1)
	_text(UITheme.font("title"), Vector2(art.position.x, art.get_center().y + 20 * k), glyph, 54 * k, Palette.SILVER.darkened(0.35), art.size.x)


func _draw_cover(tex: Texture2D, dst: Rect2, v_from: float, v_to: float) -> void:
	var ts := tex.get_size()
	var src_h := ts.y * (v_to - v_from)
	var src := Rect2(0, ts.y * v_from, ts.x, src_h)
	var want := dst.size.x / dst.size.y
	var have := src.size.x / src.size.y
	if have > want:
		var nw := src.size.y * want
		src.position.x += (src.size.x - nw) / 2
		src.size.x = nw
	else:
		var nh := src.size.x / want
		src.position.y += (src.size.y - nh) * 0.35
		src.size.y = nh
	draw_texture_rect_region(tex, dst, src)


func _draw_overlays(r: Rect2, d: Dictionary, k: float) -> void:
	var s := GameState.state
	if s == null:
		return
	if kind == "character":
		var ch := s.character(card_id)
		if _art_framed:
			_draw_framed_stats(r, ch, k)
		else:
			_draw_plain_stats(r, ch, k)
		var traumas: Array = ch.get("traumas", [])
		for i in traumas.size():
			var tr := Rect2(r.position + Vector2(6 * k + i * 16 * k, 6 * k), Vector2(13 * k, 20 * k))
			draw_rect(tr, Palette.TRAUMA)
			draw_rect(tr, Palette.TRAUMA_BRIGHT, false, 1.0)
		var dc := TraumaRules.death_chance(TraumaRules.counted(traumas) + 1)
		if dc > 0 and TraumaRules.counted(traumas) >= 2:
			_pill(Vector2(r.end.x - 6 * k, r.position.y + 8 * k), "☠ %d%%" % dc, 11 * k, Palette.TRAUMA_BRIGHT, true)
		if not s.is_alive(card_id):
			draw_rect(r, Color(0, 0, 0, 0.6))
	elif kind == "enhancement":
		if WearRules.wears(ContentDB.data, s, card_id):
			var wv := WearRules.current(s, card_id)
			_pill(Vector2(r.end.x - 6 * k, r.position.y + 8 * k), "⚒ %d%%" % wv, 11 * k, Palette.STAT_DOWN if wv >= 30 else Palette.TEXT_DIM, true)
	if badge != "":
		_pill(Vector2(r.get_center().x, r.end.y - 10 * k), badge, 11 * k, Palette.REQ_MET, false, true)


func _draw_framed_stats(r: Rect2, ch: Dictionary, k: float) -> void:
	var content := ContentDB.data
	var base := content.stage_stats(card_id, str(ch.get("stage", "")))
	var perm: Dictionary = ch.get("perm", {})
	var xs := {"power": 0.224, "will": 0.501, "cunning": 0.775}
	for st: String in xs:
		var v := int(base.get(st, 0)) + int(perm.get(st, 0))
		var c := Vector2(r.position.x + r.size.x * xs[st], r.position.y + r.size.y * 0.935)
		var rad := 9.0 * k
		draw_circle(c, rad, Color(0.05, 0.05, 0.07, 0.92))
		draw_arc(c, rad, 0, TAU, 20, Palette.SILVER.darkened(0.2), 1.0)
		_text(UITheme.font("title_bold"), Vector2(c.x - rad, c.y + 5 * k), str(v), 14 * k, Palette.TEXT, rad * 2)


func _draw_plain_stats(r: Rect2, ch: Dictionary, k: float) -> void:
	var content := ContentDB.data
	var base := content.stage_stats(card_id, str(ch.get("stage", "")))
	var perm: Dictionary = ch.get("perm", {})
	var i := 0
	for st: String in ["power", "will", "cunning"]:
		var v := int(base.get(st, 0)) + int(perm.get(st, 0))
		var c := Vector2(r.position.x + r.size.x * (0.25 + 0.25 * i), r.position.y + r.size.y * 0.63)
		var rad := 10.0 * k
		draw_circle(c, rad, Color(0.05, 0.05, 0.07, 0.9))
		draw_arc(c, rad, 0, TAU, 20, Palette.SILVER.darkened(0.3), 1.0)
		_text(UITheme.font("title_bold"), Vector2(c.x - rad, c.y + 5 * k), str(v), 14 * k, Palette.TEXT, rad * 2)
		_text(UITheme.font("sans"), Vector2(c.x - rad, c.y - 12 * k), Palette.STAT_SHORT[st], 9 * k, Palette.TEXT_DIM, rad * 2)
		i += 1


func _pill(anchor: Vector2, text: String, fs: float, color: Color, right_align: bool, centered: bool = false) -> void:
	var f := UITheme.font("sans_bold")
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x + 8
	var pos := anchor
	if right_align:
		pos.x -= w
	elif centered:
		pos.x -= w / 2
	var rect := Rect2(pos - Vector2(0, fs * 0.2), Vector2(w, fs + 6))
	draw_rect(rect, Color(0.04, 0.04, 0.06, 0.9))
	draw_rect(rect, color.darkened(0.2), false, 1.0)
	draw_string(f, Vector2(rect.position.x + 4, rect.position.y + fs + 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), color)


func _text(f: Font, pos: Vector2, text: String, fs: float, color: Color, width: float) -> void:
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, maxi(6, int(fs)), color)


func _text_multi(f: Font, pos: Vector2, text: String, fs: float, color: Color, width: float, lines: int) -> void:
	draw_multiline_string(f, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, maxi(6, int(fs)), lines, color)
