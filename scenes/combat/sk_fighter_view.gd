class_name SkFighterView
extends Control
## Боец на экране «Схватки» (docs/24 §7): пока нет боевых поз — заглушка из карты (рисунок верхнего поля в рамке).
## Под ногами кольцо (ходит — золото, цель — багрянец у врага, зелень у союзника), ниже полоска здоровья, у героев —
## десять делений психики, значки состояний (наведение — что это и сколько осталось). Труп — тёмные останки.

signal picked(uid: String)
signal hovered(uid: String, on: bool)

const W := 168.0
const H := 286.0
const STATUS := {   # значок: буква и цвет
	"bleed": ["К", Color("#D0505A")], "poison": ["Я", Color("#7FB24A")], "burn": ["Г", Color("#F0B050")],
	"stun": ["О", Color("#E8D070")], "mark": ["М", Color("#E07040")], "guard": ["З", Color("#7FA8D8")],
	"guarding": ["З", Color("#5F88B8")], "riposte": ["Кт", Color("#C9CED6")], "stealth": ["С", Color("#9AA0A8")],
	"buff": ["↑", Color("#D9C27A")], "debuff": ["↓", Color("#C0666A")], "dodge": ["У", Color("#C9CED6")],
	"block": ["П", Color("#C49A5E")], "taunt": ["Пр", Color("#E0E0E0")], "foresight": ["Пв", Color("#8FB8E8")],
	"blind": ["Сл", Color("#F0F0F0")], "fear": ["Ст", Color("#B8A8D8")], "charm": ["Оч", Color("#D88FC8")],
	"grab": ["Зх", Color("#5FB8A8")], "whisper": ["Ш", Color("#A070D0")], "acid": ["Р", Color("#B8D050")],
	"rage": ["Яр", Color("#E05050")], "weak": ["Сб", Color("#A07070")], "sure": ["В", Color("#E8D8A0")],
	"empower": ["А", Color("#E8C880")], "ignite": ["Пл", Color("#F0D080")], "steady": ["Н", Color("#A8B0B8")],
	"stun_guard": ["", Color(0, 0, 0, 0)],
}

var sk: Skirmish
var uid := ""
var ring := ""            # "" | active | enemy_target | ally_target
var _tex: Texture2D
var _status_box: HBoxContainer


static func art_of(content: Content, card: String) -> String:
	for d: Dictionary in [content.characters.get(card, {}), content.enemies.get(card, {}), content.enhancements.get(card, {})]:
		var a := str(d.get("art", ""))
		if a != "" and ResourceLoader.exists(a):
			return a
	for ext: String in ["webp", "png"]:
		var p := "res://art/cards/%s.%s" % [card, ext]
		if ResourceLoader.exists(p):
			return p
	return ""


func setup(p_sk: Skirmish, p_uid: String) -> void:
	sk = p_sk
	uid = p_uid
	var f := fighter()
	var art := art_of(sk.content, f.card)
	if art == "" and f.echo:
		art = art_of(sk.content, str(sk.content.skirmish.get("echoes", {}).get(f.card, {}).get("base", "")))
	_tex = load(art) if art != "" else null
	custom_minimum_size = Vector2(W * f.size, H)
	size = custom_minimum_size
	pivot_offset = Vector2(size.x / 2.0, size.y)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void: hovered.emit(uid, true))
	mouse_exited.connect(func() -> void: hovered.emit(uid, false))
	_status_box = HBoxContainer.new()
	_status_box.add_theme_constant_override("separation", 3)
	_status_box.position = Vector2(4, H - 22)
	add_child(_status_box)
	refresh()


func fighter() -> SkFighter:
	return sk.by_uid(uid)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		picked.emit(uid)
		accept_event()


func refresh() -> void:
	var f := fighter()
	if f == null:
		return
	for ch in _status_box.get_children():
		ch.queue_free()
	if not f.corpse:
		for s: Dictionary in f.statuses:
			var t := str(s["type"])
			var st: Array = STATUS.get(t, [t.left(1), Palette.SILVER])
			if str(st[0]) == "":
				continue
			var l := UITheme.label(str(st[0]), "sans_bold", 13, st[1])
			l.custom_minimum_size = Vector2(22, 20)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.add_theme_stylebox_override("normal", UITheme.box(Color(0.06, 0.06, 0.08, 0.92), st[1], 1, 10))
			l.mouse_filter = Control.MOUSE_FILTER_STOP
			var more := ""
			if s.has("charges"):
				more = " · зарядов: %d" % int(s["charges"])
			elif int(s.get("turns", 0)) < 99 and s.has("turns"):
				more = " · ходов: %d" % int(s["turns"])
			if s.has("power"):
				more += " · сила %d" % int(s["power"])
			l.tooltip_text = str(SkStatus.NAMES.get(t, t)) + more
			_status_box.add_child(l)
	tooltip_text = _tip(f)
	queue_redraw()


func _tip(f: SkFighter) -> String:
	if f.corpse:
		return "Труп: %s — держит место в строю (%d здоровья, истлеет через %d р.)" % [f.name, f.hp, f.corpse_rounds]
	var lines := ["%s — здоровье %d / %d" % [f.name, f.hp, f.hp_max]]
	lines.append("скорость %d · точность %+d · уклонение %d · крит %d%% · защита %d%%" % [f.speed, f.acc, f.dodge, f.crit, int(f.prot * 100)])
	lines.append("сопротивления: кровотечение %d%%, яд %d%%, оглушение %d%%, сдвиг %d%%" % [int(f.res.get("bleed", 0)), int(f.res.get("poison", 0)),
		int(f.res.get("stun", 0)), int(f.res.get("move", 0))])
	if not f.tags.is_empty():
		lines.append(", ".join(f.tags))
	return "\n".join(lines)


func _draw() -> void:
	var f := fighter()
	if f == null:
		return
	var w := size.x
	var foot := H - 52.0
	# кольцо под ногами
	var rc := {"active": Palette.GOLD, "enemy_target": Palette.TRAUMA_BRIGHT, "ally_target": Color("#6FA47B")}
	if rc.has(ring):
		draw_set_transform(Vector2(w / 2.0, foot), 0, Vector2(1, 0.22))
		draw_circle(Vector2.ZERO, w * 0.44, Color(rc[ring], 0.25))
		draw_arc(Vector2.ZERO, w * 0.44, 0, TAU, 48, rc[ring], 9.0, true)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if f.corpse:
		draw_set_transform(Vector2(w / 2.0, foot - 8), 0, Vector2(1, 0.3))
		draw_circle(Vector2.ZERO, w * 0.36, Color(0.12, 0.1, 0.1, 0.95))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		var cl := UITheme.font("serif_italic")
		draw_string(cl, Vector2(0, foot - 30), "труп", HORIZONTAL_ALIGNMENT_CENTER, w, 18, Palette.TEXT_DIM)
		return
	# «фигура»: верхнее поле карты в рамке (заглушка до боевых поз)
	var r := Rect2(Vector2(10, 6), Vector2(w - 20, foot - 14))
	draw_rect(r, Color(0.05, 0.05, 0.07))
	if _tex:
		var ts := _tex.get_size()
		var src := Rect2(ts.x * 0.06, ts.y * 0.05, ts.x * 0.88, ts.y * 0.58)
		var k := maxf(r.size.x / src.size.x, r.size.y / src.size.y)
		var cut := Vector2(r.size.x / k, r.size.y / k)
		src = Rect2(src.position + (src.size - cut) / 2.0, cut)
		var mod := Color(1, 1, 1) if not f.edge else Color(0.75, 0.6, 0.6)
		if f.has_status("stealth"):
			mod.a = 0.55
		draw_texture_rect_region(_tex, r, src, mod)
	var frame := Palette.SILVER if f.side == "hero" else Palette.TRAUMA_BRIGHT.darkened(0.2)
	if f.echo:
		frame = Color("#8FB8E8")
	draw_rect(r, frame, false, 2.0)
	if f.edge:
		draw_rect(r, Color(0.8, 0.1, 0.15, 0.35 + 0.15 * sin(Time.get_ticks_msec() / 250.0)), false, 5.0)
	# имя
	var fnt := UITheme.font("caps")
	var fs := 17
	while fs > 11 and fnt.get_string_size(f.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - 12:
		fs -= 1
	draw_string(fnt, Vector2(0, r.position.y + 22), f.name, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Palette.TEXT)
	# здоровье
	var by := foot + 8
	draw_rect(Rect2(12, by, w - 24, 9), Color(0.16, 0.06, 0.07))
	draw_rect(Rect2(12, by, (w - 24) * clampf(float(f.hp) / maxf(1.0, f.hp_max), 0, 1), 9), Palette.TRAUMA_BRIGHT)
	draw_rect(Rect2(12, by, w - 24, 9), Color.BLACK, false, 1.0)
	if f.is_hero():
		var psy := PsycheRules.psyche(sk.state, f.card)
		var on := int(round(psy / 10.0))
		var cr := PsycheRules.crisis(sk.state, f.card)
		var pc := Color("#96AAE1") if cr == "" else (Color("#D06060") if cr == "panic" else Palette.GOLD)
		for i in 10:
			draw_rect(Rect2(14 + i * ((w - 28) / 10.0), by + 13, (w - 28) / 10.0 - 3, 6), pc if i < on else Color(0.15, 0.17, 0.23))


func _process(_d: float) -> void:
	var f := fighter()
	if f != null and f.edge:
		queue_redraw()
