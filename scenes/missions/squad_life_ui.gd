class_name SquadLifeUI
extends Control
## Интерфейс «живого отряда» (docs/16 §5–7, §9г): значок доверия и шкала психики для планшета героя,
## подсказки при наведении и строка для брифинга. Правила — TrustRules, BondRules, PsycheRules.

const PANIC_COLOR := Color("#C0343F")
const UPLIFT_COLOR := Color("#E8C46A")

var mode := "trust"     # trust | panic (шкала психики)
var card_id := ""


static func make(m: String, cid: String, sz: Vector2 = Vector2(76, 76)) -> SquadLifeUI:
	var n := SquadLifeUI.new()
	n.mode = m
	n.card_id = cid
	n.custom_minimum_size = sz
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return n


## Цвет психики: крепок — холодное серебро, держится — янтарь, на пределе — рыжий, ломается — кровь.
static func psyche_color(psy: int) -> Color:
	if psy >= 70:
		return Color("#8FB3C9")
	if psy >= 40:
		return Palette.REQ_MISS
	if psy >= 15:
		return Color("#D07A3A")
	return Palette.TRAUMA_BRIGHT


## Цвет с учётом кризиса героя.
static func hero_psyche_color(cid: String) -> Color:
	var s := GameState.state
	match PsycheRules.crisis(s, cid):
		"panic":
			return PANIC_COLOR
		"uplift":
			return UPLIFT_COLOR
	return psyche_color(PsycheRules.psyche(s, cid))


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
		var psy := PsycheRules.psyche(s, card_id) if s else PsycheRules.MAX
		var col := hero_psyche_color(card_id) if s else psyche_color(psy)
		draw_arc(c, rad, 0, TAU, 48, Palette.LINE, 5.0, true)
		if psy > 0:
			draw_arc(c, rad, -PI / 2, -PI / 2 + TAU * psy / float(PsycheRules.MAX), 48, col, 5.0, true)
		# отметки: «на пределе» и «ломается»
		for th: int in [40, 15]:
			var a := -PI / 2 + TAU * th / float(PsycheRules.MAX)
			draw_line(c + Vector2.from_angle(a) * (rad - 7), c + Vector2.from_angle(a) * (rad + 7), Palette.TEXT_DIM, 2.0)
		# пульс в центре: ровнее, когда психика крепка
		var amp := 0.2 + 0.4 * (1.0 - psy / float(PsycheRules.MAX))
		var pts := PackedVector2Array()
		for i in 7:
			var x := c.x - rad * 0.55 + rad * 1.1 * i / 6.0
			var y: float = c.y + [0.0, 0.0, -1.0, 0.9, -0.45, 0.0, 0.0][i] * rad * amp
			pts.append(Vector2(x, y))
		draw_polyline(pts, col.lightened(0.2), 3.0, true)
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


## Подсказка шкалы психики.
static func panic_hint(cid: String) -> String:
	var c := ContentDB.data
	var s := GameState.state
	var psy := PsycheRules.psyche(s, cid)
	var st := PsycheRules.crisis(s, cid)
	var head := "[b]Психика: %d / %d[/b] — [color=#%s]%s[/color]" % [psy, PsycheRules.MAX, hero_psyche_color(cid).to_html(false),
		PsycheRules.NAMES[st].to_upper() if st != "" else PsycheRules.word(psy)]
	return head + "\nНа нуле — кризис: [color=#C0343F]паника[/color] (−30%%, срывы, упрёки, порча вещей) или [color=#E8C46A]подъём духа[/color] (+50%%, поддержка, доверие, рост тегов вдвое). Кризис длится до конца боя или миссии.\n\n[b]Бьёт по психике:[/b] угроза, тёмные места, травмы, провалы, вражда в отряде, перевес врага.\n[b]Лечит:[/b] удачи, доверие в отряде, светлые места, отдых и лагерь.\n\n[b]Характер:[/b] %s" % PsycheRules.reaction(c, s, cid)


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
		var psy := PsycheRules.psyche(s, cid)
		if psy <= 60 and TutorialRules.enabled(s, "panic"):
			out.append("[color=#%s]♥ %s: психика %d — %s[/color] · %s" % [psyche_color(psy).to_html(false), c.card_name(cid), psy, PsycheRules.word(psy),
				PsycheRules.reaction(c, s, cid)])
	for i in heroes.size():
		for j in range(i + 1, heroes.size()):
			if TrustRules.value(s, heroes[i], heroes[j]) <= -2 and TutorialRules.enabled(s, "panic"):
				out.append("[color=#B65F63]⚡ %s и %s в ссоре — обоим тяжелее держаться (психика −%d)[/color]" % [c.card_name(heroes[i]), c.card_name(heroes[j]), -PsycheRules.FEUD])
	return "\n".join(out)
