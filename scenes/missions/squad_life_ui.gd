class_name SquadLifeUI
extends Control
## Интерфейс «живого отряда» (docs/16 §5–7): значок доверия и шкала паники для планшета героя,
## подсказки при наведении и строка для брифинга. Правила — TrustRules, BondRules, PanicRules.

var mode := "trust"     # trust | panic
var card_id := ""


static func make(m: String, cid: String, sz: Vector2 = Vector2(76, 76)) -> SquadLifeUI:
	var n := SquadLifeUI.new()
	n.mode = m
	n.card_id = cid
	n.custom_minimum_size = sz
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return n


static func panic_color(v: int) -> Color:
	if v >= PanicRules.BREAK:
		return Palette.TRAUMA_BRIGHT
	if v >= PanicRules.REACT:
		return Color("#D07A3A")
	if v >= 30:
		return Palette.REQ_MISS
	return Palette.STAT_NEUTRAL


static func portrait(cid: String) -> String:
	var art := str(ContentDB.data.characters.get(cid, {}).get("art", ""))
	if art != "" and ResourceLoader.exists(art):
		return art
	for ext: String in ["webp", "png"]:
		var p := "res://art/cards/%s.%s" % [cid, ext]
		if ResourceLoader.exists(p):
			return p
	return ""


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var c := r.get_center()
	var rad := minf(size.x, size.y) * 0.42
	var s := GameState.state
	if mode == "panic":
		var v := PanicRules.value(s, card_id) if s else 0
		draw_arc(c, rad, 0, TAU, 48, Palette.LINE, 5.0, true)
		if v > 0:
			draw_arc(c, rad, -PI / 2, -PI / 2 + TAU * v / float(PanicRules.MAX), 48, panic_color(v), 5.0, true)
		# отметки порогов реакции
		for th: int in [PanicRules.REACT, PanicRules.BREAK]:
			var a := -PI / 2 + TAU * th / float(PanicRules.MAX)
			draw_line(c + Vector2.from_angle(a) * (rad - 7), c + Vector2.from_angle(a) * (rad + 7), Palette.TEXT_DIM, 2.0)
		# сердце-пульс в центре
		var pts := PackedVector2Array()
		for i in 7:
			var x := c.x - rad * 0.55 + rad * 1.1 * i / 6.0
			var y: float = c.y + [0.0, 0.0, -0.45, 0.4, -0.2, 0.0, 0.0][i] * rad
			pts.append(Vector2(x, y))
		draw_polyline(pts, panic_color(v).lightened(0.2), 3.0, true)
	else:
		# две сцепленные серебряные дуги
		var off := rad * 0.36
		var rr := rad * 0.58
		draw_arc(c - Vector2(off, 0), rr, 0, TAU, 40, Palette.SILVER, 4.0, true)
		draw_arc(c + Vector2(off, 0), rr, 0, TAU, 40, Palette.SILVER.darkened(0.25), 4.0, true)
		draw_arc(c - Vector2(off, 0), rr, -0.5, 0.5, 12, Palette.SILVER, 4.0, true)


## Подсказка значка доверия: топ-5 положительных и топ-5 отрицательных.
static func trust_hint(cid: String) -> String:
	var c := ContentDB.data
	var top := TrustRules.top(c, GameState.state, cid)
	var lines: Array[String] = ["[b]Доверие[/b]  [color=#9A9CA6](от −5 до +5)[/color]"]
	if Array(top["positive"]).is_empty() and Array(top["negative"]).is_empty():
		lines.append("[color=#9A9CA6]Пока ни с кем не сложилось. Доверие растёт от успехов вместе и падает от провалов, бегства и ссор.[/color]")
		return "\n".join(lines)
	for part: Array in [["Доверяет", top["positive"]], ["Не доверяет", top["negative"]]]:
		if Array(part[1]).is_empty():
			continue
		lines.append("")
		lines.append("[b]%s[/b]" % part[0])
		for rec: Dictionary in part[1]:
			lines.append(_trust_row(rec))
	lines.append("")
	lines.append("[color=#9A9CA6]При %+d и выше — +%d%% в бою вместе; при %d и ниже в один отряд не идут.[/color]" % [TrustRules.HIGH, int(TrustRules.COMBAT_HIGH * 100), TrustRules.REFUSE_AT])
	return "\n".join(lines)


static func _trust_row(rec: Dictionary) -> String:
	var v := int(rec["value"])
	var col := "#6FA47B" if v > 0 else "#B65F63"
	var bar := "[color=%s]%s[/color][color=#3A3E4E]%s[/color]" % [col, "■".repeat(absi(v)), "■".repeat(TrustRules.MAX - absi(v))]
	var pic := portrait(str(rec["hero"]))
	var img := "[img=34x52]%s[/img] " % pic if pic != "" else ""
	var note := str(rec.get("note", ""))
	return "%s[b]%s[/b]  %s  [color=%s]%+d[/color]%s" % [img, ContentDB.data.card_name(str(rec["hero"])), bar, col, v,
		("\n      [color=#9A9CA6][i]%s[/i][/color]" % note) if note != "" else ""]


## Подсказка шкалы паники.
static func panic_hint(cid: String) -> String:
	var c := ContentDB.data
	var s := GameState.state
	var v := PanicRules.value(s, cid)
	return "[b]Паника: %d / %d[/b] — [color=#%s]%s[/color]\nРастёт от опасных миссий, провалов, травм и гибели товарищей; спадает, пока герой отдыхает.\n\n[b]В панике:[/b] %s" % [
		v, PanicRules.MAX, panic_color(v).to_html(false), PanicRules.word(v), PanicRules.reaction(c, s, cid)]


## Строка для брифинга: связки, паника, отказ по доверию. "" — нечего сказать.
static func squad_text(heroes: Array) -> String:
	var c := ContentDB.data
	var s := GameState.state
	var out: Array[String] = []
	var refuse := TrustRules.refusal(c, s, heroes)
	if refuse != "":
		out.append("[color=#B65F63]✕ %s[/color]" % refuse)
	for b: Dictionary in BondRules.active(c, s, heroes):
		out.append("[color=#E3C98E]⚭ Связка «%s»[/color] — %s" % [b.get("name", ""), b.get("text", "")])
	for i in heroes.size():
		for j in range(i + 1, heroes.size()):
			var t := TrustRules.value(s, heroes[i], heroes[j])
			if t >= TrustRules.HIGH:
				out.append("[color=#6FA47B]♦ %s и %s доверяют друг другу (%+d): +%d%% в бою[/color]" % [c.card_name(heroes[i]), c.card_name(heroes[j]), t, int(TrustRules.COMBAT_HIGH * 100)])
	for cid: String in heroes:
		var v := PanicRules.value(s, cid)
		if v >= 30:
			out.append("[color=#%s]♥ %s %s (%d)[/color] — %s" % [panic_color(v).to_html(false), c.card_name(cid), PanicRules.word(v), v, PanicRules.reaction(c, s, cid)])
	return "\n".join(out)
