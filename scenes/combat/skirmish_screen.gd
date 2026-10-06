class_name SkirmishScreen
extends Control
## Экран пошагового боя «Схватка» (docs/24 §7; Ф4 — на заглушках). Играет готовый бой Skirmish: в ход героя игрок
## выбирает навык (кнопка или 1–9) и цель (щелчок по фигуре); враги ходят сами (SkAI). Сверху — поле, очередь
## ходов, свет, «Отступить»; сцена — строй героев слева, врагов справа; снизу — ходящий герой, его навыки с точками
## позиций, расчёт удара при наведении на цель (числа — только по наведению, решение владельца 25).
## Закрытие — сигнал closed(итог Skirmish.finish()).

signal closed(result: Dictionary)

const FOOT := 742.0          # линия ног бойцов
const SLOT := 178.0
const MID := 960.0
const GAP := 64.0
const PANEL_Y := 800.0
const BTN := Vector2(112, 150)
const LIGHT_DIM := {"bright": 0.9, "dim": 0.72, "dusk": 0.5, "dark": 0.34}
const LIGHT_TEXT := {"bright": "день — враги чаще застигнуты", "dim": "психика тает быстрее, добыча чуть богаче",
	"dusk": "враги точнее и злее, тени сильнее", "dark": "тьма: враги опаснее, добыча щедрее"}

var sk: Skirmish
var auto_heroes := false     # героями тоже ходит ИИ (автоснимки, просмотр)
var region := "forgotten_shore"
var sky := "day"
var _views := {}             # uid → SkFighterView
var _actor: SkFighter
var _skill: Dictionary = {}
var _targets: Array = []
var _hover := ""
var _busy := false
var _seen := 0               # сколько событий журнала уже показано
var _speed := 1.0
var _stage: Control
var _fx: Control
var _strip: HBoxContainer
var _round_lbl: Label
var _hero_box: VBoxContainer
var _skills_row: HBoxContainer
var _target_box: RichTextLabel
var _caption: Label
var _retreat_btn: Button


## Пробный бой (меню «Разработчик», автоснимки): отряд Берега с картами против врагов со строем.
static func demo(content: Content, enemies: Array, light: String = "dim", seed_value: int = 0, field: String = "F_17") -> Skirmish:
	var s := MissionFlow.new_run(content, seed_value if seed_value != 0 else randi() % 100000 + 1, "shore")
	for cid: String in ["P02", "P03", "P04"]:
		EffectApplier.add_card(content, s, cid)
	var kit := {"P01": [["U02", "L08", "U12"], ["A01", "A02", "A06"]], "P02": [["U14", "L12"], ["A03"]],
		"P03": [["K05", "L06"], ["A04"]], "P04": [["L13"], ["A05"]]}
	for cid2: String in kit:
		for card: String in kit[cid2][0]:
			if not s.owns(card):
				EffectApplier.add_card(content, s, card)
		s.character(cid2)["pocket"] = Array(kit[cid2][0]).duplicate()
		s.character(cid2)["abilities"] = Array(kit[cid2][1]).duplicate()
	return Skirmish.create(content, s, {"heroes": ["P02", "P01", "P04", "P03"], "enemies": enemies, "pack": true,
		"light": light, "field": field})


## Открыть бой поверх parent. region/sky — фон места (art/regions/<region>_<sky>.webp).
static func open(parent: Node, p_sk: Skirmish, p_region: String = "forgotten_shore", p_sky: String = "day") -> SkirmishScreen:
	var s := SkirmishScreen.new()
	s.sk = p_sk
	s.region = p_region
	s.sky = p_sky
	var layer := CanvasLayer.new()   # свой верхний слой: бой поверх любой сцены
	layer.layer = 60
	layer.add_child(s)
	parent.add_child(layer)
	return s


## Закрыть экран (вместе с его слоем).
func close() -> void:
	var p := get_parent()
	if p is CanvasLayer:
		p.queue_free()
	else:
		queue_free()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Palette.BG_DEEP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var tex := _region_tex()
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.position = Vector2.ZERO
		tr.size = Vector2(1920, PANEL_Y)
		tr.modulate = Color(1, 1, 1) * float(LIGHT_DIM.get(sk.light, 0.8))
		tr.modulate.a = 1.0
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
	_stage = Control.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_build_top()
	_build_panel()
	_fx = Control.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)
	_caption = UITheme.label("", "caps", 30, Palette.TEXT)
	_caption.position = Vector2(0, 112)
	_caption.size = Vector2(1920, 44)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)
	_sync_views(false)
	_advance.call_deferred()


func _region_tex() -> Texture2D:
	for k: String in [sky, "day"]:
		var p := "res://art/regions/%s_%s.webp" % [region, k]
		if ResourceLoader.exists(p):
			return load(p)
	return null


# --- верх: поле, очередь, свет, отступление ---------------------------------------------------------------------------

func _plate(pos: Vector2, sz: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.size = sz
	p.add_theme_stylebox_override("panel", UITheme.box(Color(0.055, 0.06, 0.08, 0.88), Palette.LINE, 1, 8, 8))
	add_child(p)
	return p


func _build_top() -> void:
	var fp := _plate(Vector2(24, 16), Vector2(470, 70))
	var fv := VBoxContainer.new()
	fp.add_child(fv)
	var fd: Dictionary = sk.content.fields.get(sk.field, {})
	var fname := str(fd.get("name", "Поле боя"))
	var ftags := Array(fd.get("tags", [])).filter(func(t: String) -> bool: return t != "суша")
	fv.add_child(UITheme.label(fname.to_upper() + ("  ·  " + " · ".join(ftags) if not ftags.is_empty() else ""), "caps", 22, Palette.TEXT))
	fv.add_child(UITheme.label(str(fd.get("text", "")).left(70), "sans", 14, Palette.TEXT_DIM))
	var mp := _plate(Vector2(560, 12), Vector2(800, 80))
	var mv := VBoxContainer.new()
	mv.alignment = BoxContainer.ALIGNMENT_CENTER
	mp.add_child(mv)
	_round_lbl = UITheme.label("", "caps", 17, Palette.TEXT_DIM)
	_round_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(_round_lbl)
	_strip = HBoxContainer.new()
	_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	_strip.add_theme_constant_override("separation", 6)
	mv.add_child(_strip)
	var lp := _plate(Vector2(1410, 16), Vector2(320, 70))
	var lv := VBoxContainer.new()
	lp.add_child(lv)
	lv.add_child(UITheme.label("СВЕТ: " + sk.light_name().to_upper(), "caps", 22, Color("#D2BE8C")))
	lv.add_child(UITheme.label(str(LIGHT_TEXT.get(sk.light, "")), "sans", 14, Palette.TEXT_DIM))
	_retreat_btn = Button.new()
	_retreat_btn.text = "Отступить"
	_retreat_btn.position = Vector2(1748, 20)
	_retreat_btn.size = Vector2(150, 62)
	_retreat_btn.add_theme_font_override("font", UITheme.font("caps"))
	_retreat_btn.add_theme_font_size_override("font_size", 24)
	_retreat_btn.tooltip_text = "Отступить: шанс %d%%. Удача — бой окончен, событие останется; неудача — ход потерян." % sk.retreat_chance()
	_retreat_btn.pressed.connect(_on_retreat)
	add_child(_retreat_btn)
	var sp := Button.new()
	sp.text = "»"
	sp.tooltip_text = "Быстрее (×2)"
	sp.position = Vector2(1748, 88)
	sp.size = Vector2(56, 40)
	sp.toggle_mode = true
	sp.toggled.connect(func(on: bool) -> void: _speed = 2.0 if on else 1.0)
	add_child(sp)


func _update_strip() -> void:
	for ch in _strip.get_children():
		ch.queue_free()
	_round_lbl.text = "РАУНД %d · ОЧЕРЕДЬ ХОДОВ" % sk.round_no
	var order: Array = []
	if _actor != null:
		order.append(_actor.uid)
	order.append_array(sk.queue)
	for i in mini(order.size(), 9):
		var f := sk.by_uid(str(order[i]))
		if f == null or not f.alive():
			continue
		var art := SkFighterView.art_of(sk.content, f.card)
		var box := PanelContainer.new()
		var col := Palette.GOLD if i == 0 else (Palette.SILVER if f.side == "hero" else Palette.TRAUMA_BRIGHT)
		box.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.05, 0.07), col, 3 if i == 0 else 2, 22, 2))
		box.tooltip_text = f.name
		if art != "":
			var at := AtlasTexture.new()
			at.atlas = load(art)
			var ts: Vector2 = at.atlas.get_size()
			at.region = Rect2(ts.x * 0.2, ts.y * 0.06, ts.x * 0.6, ts.x * 0.6)
			var tr := TextureRect.new()
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.texture = at
			tr.custom_minimum_size = Vector2(40, 40)
			box.add_child(tr)
		else:
			box.add_child(UITheme.label(f.name.left(2), "caps", 18, col))
		_strip.add_child(box)


# --- низ: герой, навыки, цель -----------------------------------------------------------------------------------------

func _build_panel() -> void:
	var bgp := Panel.new()
	bgp.position = Vector2(0, PANEL_Y)
	bgp.size = Vector2(1920, 1080 - PANEL_Y)
	bgp.add_theme_stylebox_override("panel", UITheme.box(Palette.BG_PANEL, Palette.GOLD.darkened(0.25), 2, 0))
	add_child(bgp)
	_hero_box = VBoxContainer.new()
	_hero_box.position = Vector2(24, PANEL_Y + 14)
	_hero_box.size = Vector2(520, 250)
	_hero_box.add_theme_constant_override("separation", 4)
	add_child(_hero_box)
	_skills_row = HBoxContainer.new()
	_skills_row.position = Vector2(560, PANEL_Y + 40)
	_skills_row.add_theme_constant_override("separation", 8)
	add_child(_skills_row)
	var sl := UITheme.label("НАВЫКИ  ·  1–9, пробел — пропуск, правая кнопка — отмена", "caps", 16, Palette.GOLD)
	sl.position = Vector2(560, PANEL_Y + 10)
	add_child(sl)
	_target_box = RichTextLabel.new()
	_target_box.bbcode_enabled = true
	_target_box.fit_content = true
	_target_box.position = Vector2(1560, PANEL_Y + 14)
	_target_box.size = Vector2(340, 250)
	_target_box.add_theme_font_size_override("normal_font_size", 16)
	_target_box.add_theme_font_size_override("bold_font_size", 18)
	_target_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_target_box)


func _show_hero(f: SkFighter) -> void:
	for ch in _hero_box.get_children():
		ch.queue_free()
	for ch2 in _skills_row.get_children():
		ch2.queue_free()
	if f == null or f.side != "hero":
		return
	_hero_box.add_child(UITheme.label(f.name.to_upper() + ("  ·  Эхо" if f.echo else ""), "caps", 30, Palette.TEXT))
	if f.is_hero():
		_hero_box.add_child(UITheme.label("%s · ядро %d/%d" % [CoreRules.rank_name(sk.content, sk.state, f.card), CoreRules.level(sk.state, f.card), CoreRules.LEVELS], "sans", 16, Palette.TEXT_DIM))
	_hero_box.add_child(UITheme.label("Здоровье %d / %d%s" % [f.hp, f.hp_max, "  — НА ГРАНИ" if f.edge else ""], "sans_bold", 18, Color("#E68282")))
	if f.is_hero():
		var psy := PsycheRules.psyche(sk.state, f.card)
		var cr := PsycheRules.crisis(sk.state, f.card)
		_hero_box.add_child(UITheme.label("Психика %d — %s" % [psy, PsycheRules.NAMES.get(cr, PsycheRules.word(psy)).to_lower()], "sans_bold", 18, Color("#96AAE1")))
	var tags := HFlowContainer.new()
	tags.custom_minimum_size = Vector2(500, 0)
	for t: String in f.tags:
		var l := UITheme.label(t, "sans", 15, Palette.SILVER)
		l.add_theme_stylebox_override("normal", UITheme.box(Palette.BG_RAISED, Palette.LINE, 1, 5, 4))
		tags.add_child(l)
	_hero_box.add_child(tags)
	var i := 0
	for o: Dictionary in sk.options(f):
		i += 1
		_skills_row.add_child(_skill_button(f, o, i))


func _skill_button(f: SkFighter, o: Dictionary, n: int) -> Control:
	var s: Dictionary = o["skill"]
	var ok := str(o["why"]) == ""
	var b := Button.new()
	b.custom_minimum_size = BTN
	b.disabled = not ok
	b.toggle_mode = false
	b.tooltip_text = "%d. %s\n%s%s" % [n, str(s.get("name", "")), describe(s), "" if ok else "\nСейчас нельзя: " + str(o["why"])]
	b.add_theme_stylebox_override("normal", UITheme.box(Palette.BG_RAISED, Palette.GOLD if _skill.get("id", "") == s["id"] else Palette.LINE, 2 if _skill.get("id", "") == s["id"] else 1, 6))
	var v := Control.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(v)
	var card := str(s.get("card", ""))
	var art := SkFighterView.art_of(sk.content, card) if card != "" else ""
	if art != "":
		var at := AtlasTexture.new()
		at.atlas = load(art)
		var ts: Vector2 = at.atlas.get_size()
		at.region = Rect2(ts.x * 0.07, ts.y * 0.05, ts.x * 0.86, ts.y * 0.5)
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # до размера: иначе рисунок растягивает кнопку
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.texture = at
		tr.position = Vector2(4, 4)
		tr.size = Vector2(BTN.x - 8, 82)
		tr.clip_contents = true
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.modulate = Color(1, 1, 1, 1.0 if ok else 0.4)
		v.add_child(tr)
	else:
		var ic := UITheme.label(str(n), "caps", 40, Palette.TEXT_DIM if ok else Palette.LINE)
		ic.position = Vector2(4, 14)
		ic.size = Vector2(BTN.x - 8, 60)
		ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(ic)
	var nm := UITheme.label(str(s.get("name", "")), "sans", 13, Palette.TEXT if ok else Palette.TEXT_DIM)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.clip_text = true
	nm.position = Vector2(2, 88)
	nm.size = Vector2(BTN.x - 4, 34)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_constant_override("line_spacing", -4)
	v.add_child(nm)
	var dots := _Dots.new()
	dots.from = s.get("from", [])
	dots.to = s.get("to", [])
	dots.side = str(s.get("side", "enemy"))
	dots.position = Vector2(14, 126)
	dots.size = Vector2(90, 10)
	v.add_child(dots)
	var lim := ""
	if bool(s.get("once", false)):
		lim = "раз за бой"
	elif int(s.get("cooldown", 0)) > 0:
		lim = "%d ход" % int(s["cooldown"])
	elif card != "" and str(s.get("weapon", "")) != "":
		lim = "оружие"
	if not ok and str(o["why"]).begins_with("перезарядка"):
		lim = str(o["why"])
	if lim != "":
		var ll := UITheme.label(lim, "serif_italic", 12, Palette.TEXT_DIM)
		ll.position = Vector2(0, 136)
		ll.size = Vector2(BTN.x, 14)
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(ll)
	b.pressed.connect(_pick_skill.bind(s))
	return b


## Описание навыка словами (подсказка на кнопке).
static func describe(s: Dictionary) -> String:
	var parts: Array = []
	var side := str(s.get("side", "enemy"))
	var fr: Array = s.get("from", [])
	var to: Array = s.get("to", [])
	var rng_txt := func(a: Array) -> String: return "%d–%d" % [int(a.min()), int(a.max())] if a.size() > 1 else (str(int(a[0])) if a.size() == 1 else "")
	if side == "enemy":
		parts.append("с позиций %s по %s%s" % [rng_txt.call(fr), "всем " if bool(s.get("aoe", false)) else "", rng_txt.call(to)])
		var dm: Array = s.get("dmg", [])
		if not dm.is_empty() and int(dm[1]) == 0:
			parts.append("без урона")
		elif not dm.is_empty():
			parts.append("урон %d–%d" % [int(dm[0]), int(dm[1])])
		elif float(s.get("mult", 1.0)) != 1.0:
			parts.append("урон оружия ×%.2f" % float(s["mult"]))
		else:
			parts.append("удар оружием")
	elif side == "ally":
		parts.append("на союзника%s" % (" (всех)" if bool(s.get("aoe", false)) else ""))
	else:
		parts.append("на себя")
	for e: Dictionary in s.get("effects", []):
		var t := str(e["type"])
		var nm := str(SkStatus.NAMES.get(t, {"push": "отброс", "pull": "притянуть", "heal": "лечение", "heal_pct": "лечение",
			"psyche": "психика", "cleanse": "снять состояния", "summon": "призвать Эхо", "extra_turn": "ещё ход", "swap": "поменяться местами",
			"unstealth": "снять скрытность", "unstealth_all": "снять скрытность со всех", "remove_buffs": "снять усиления",
			"summon_enemy": "призыв", "devour": "пожрать падаль", "light_ward": "тьма не давит", "reveal": "раскрыть теги"}.get(t, t)))
		var x := nm
		if e.has("value") and t in ["psyche", "buff", "debuff"]:
			x += " " + ("+" if float(e["value"]) > 0 else "") + str(snappedf(float(e["value"]), 0.01))
		if e.has("chance") and int(e["chance"]) < 100:
			x += " (%d%%)" % int(e["chance"])
		if bool(e.get("self", false)):
			x += " — себе"
		parts.append(x)
	if int(s.get("self_move", 0)) != 0:
		parts.append("шаг %s" % ("назад" if int(s["self_move"]) > 0 else "вперёд"))
	return " · ".join(parts)


# --- ход ----------------------------------------------------------------------------------------------------------

func _advance() -> void:
	if not is_inside_tree():
		return
	_busy = true
	_skill = {}
	_targets = []
	while sk.outcome == "":
		var f := sk.turn()
		await _play(_new_events())
		if f == null:
			break
		_actor = f
		_update_strip()
		_mark_rings()
		if f.side == "enemy" or auto_heroes:
			_show_hero(null if f.side == "enemy" else f)
			await get_tree().create_timer(0.45 / _speed).timeout
			if not is_inside_tree():
				return
			sk.ai_act(f)
			await _play(_new_events())
			continue
		_show_hero(f)
		_retreat_btn.disabled = false
		_busy = false
		return
	_show_result()


func _new_events() -> Array:
	var ev := sk.log.slice(_seen)
	_seen = sk.log.size()
	return ev


func _pick_skill(s: Dictionary) -> void:
	if _busy or _actor == null:
		return
	var tg := sk.targets(_actor, s)
	if tg.is_empty() or sk.usable_why(_actor, s) != "":
		return
	AudioManager.play("pick", -8.0)
	if str(s.get("kind", "")) == "pass" or str(s.get("side", "")) == "self" and str(s.get("kind", "")) != "step" or tg == ["all"] or tg.size() == 1 and tg[0] == _actor.uid:
		_do(s, str(tg[0]))
		return
	_skill = s
	_targets = tg
	_show_hero(_actor)
	_mark_rings()


func _do(s: Dictionary, target: String) -> void:
	_busy = true
	_skill = {}
	_targets = []
	_retreat_btn.disabled = true
	sk.act(_actor, str(s["id"]), target)
	_mark_rings()
	await _play(_new_events())
	_advance()


func _on_pick(uid: String) -> void:
	if _busy or _skill.is_empty():
		return
	if _targets.has(uid):
		_do(_skill, uid)


func _on_hover(uid: String, on: bool) -> void:
	_hover = uid if on else ""
	_show_target()


func _on_retreat() -> void:
	if _busy or _actor == null or _actor.side != "hero":
		return
	_busy = true
	sk.retreat(_actor)
	await _play(_new_events())
	_advance()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and not _busy and _actor != null and _actor.side == "hero":
		var k: int = e.keycode
		if k >= KEY_1 and k <= KEY_9:
			var opts := sk.options(_actor)
			var i := k - KEY_1
			if i < opts.size():
				_pick_skill(opts[i]["skill"])
			accept_event()
		elif k == KEY_SPACE:
			_pick_skill(_actor.skill("PASS"))
			accept_event()
		elif k == KEY_ESCAPE:
			_cancel()
			accept_event()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
		_cancel()


func _cancel() -> void:
	if _skill.is_empty():
		return
	_skill = {}
	_targets = []
	_show_hero(_actor)
	_mark_rings()


# --- цель: расчёт удара по наведению -----------------------------------------------------------------------------------

func _show_target() -> void:
	var t := sk.by_uid(_hover)
	if t == null:
		_target_box.text = ""
		return
	var txt := "[b]%s[/b]\n[color=#9A9CA6]Здоровье %d / %d · %s[/color]\n" % [t.name.to_upper(), t.hp, t.hp_max, ", ".join(t.tags.slice(0, 4))]
	if not _skill.is_empty() and _targets.has(t.uid) and _actor != null:
		var pv := SkStrike.preview(sk, _actor, _skill, t)
		if str(_skill.get("side", "")) == "enemy":
			txt += "Попадание [b]%d%%[/b]\n" % int(pv["hit"])
			if int(pv["max"]) > 0:
				txt += "Урон [color=#E68282][b]%d–%d[/b][/color] · крит [color=#B89A5E]%d%%[/color]\n" % [int(pv["min"]), int(pv["max"]), int(pv["crit"])]
		for e: Dictionary in pv["effects"]:
			if int(e["chance"]) > 0:
				txt += "%s — %d%%\n" % [str(SkStatus.NAMES.get(str(e["type"]), str(e["type"]))), int(e["chance"])]
		for w: String in pv["why"]:
			txt += "[color=#9A9CA6]· %s[/color]\n" % w
	elif t.corpse:
		txt += "[i]труп — держит место[/i]"
	_target_box.text = txt


func _mark_rings() -> void:
	for uid: String in _views:
		var v: SkFighterView = _views[uid]
		var r := ""
		if _actor != null and uid == _actor.uid:
			r = "active"
		elif _targets.has(uid):
			r = "enemy_target" if v.fighter().side != _actor.side else "ally_target"
		v.ring = r
		v.refresh()


# --- сцена и анимация -----------------------------------------------------------------------------------------------

func _pos_of(f: SkFighter) -> Vector2:
	var k := f.pos - 1 + f.size / 2.0
	var cx := MID - GAP - k * SLOT if f.side == "hero" else MID + GAP + k * SLOT
	return Vector2(cx - SkFighterView.W * f.size / 2.0, FOOT + 52.0 - SkFighterView.H)


func _sync_views(animate: bool = true) -> void:
	for f: SkFighter in sk.fighters:
		var v: SkFighterView = _views.get(f.uid)
		if f.in_line():
			if v == null:
				v = SkFighterView.new()
				v.setup(sk, f.uid)
				v.picked.connect(_on_pick)
				v.hovered.connect(_on_hover)
				_stage.add_child(v)
				_views[f.uid] = v
				v.position = _pos_of(f)
				v.modulate.a = 0.0
				create_tween().tween_property(v, "modulate:a", 1.0, 0.3)
			elif animate:
				create_tween().tween_property(v, "position", _pos_of(f), 0.3 / _speed).set_trans(Tween.TRANS_SINE)
			else:
				v.position = _pos_of(f)
			v.refresh()
		elif v != null:
			_views.erase(f.uid)
			var tw := create_tween()
			tw.tween_property(v, "modulate:a", 0.0, 0.4)
			tw.tween_callback(v.queue_free)


func _float(uid: String, text: String, col: Color, fs: int = 26) -> void:
	var v: SkFighterView = _views.get(uid)
	if v == null:
		return
	var l := UITheme.label(text, "sans_bold", fs, col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.position = v.position + Vector2(0, 30 + randf() * 30)
	l.size = Vector2(v.size.x, 40)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fx.add_child(l)
	var tw := create_tween()
	tw.set_parallel()
	tw.tween_property(l, "position:y", l.position.y - 60, 1.1 / _speed)
	tw.tween_property(l, "modulate:a", 0.0, 1.1 / _speed).set_delay(0.4 / _speed)
	tw.chain().tween_callback(l.queue_free)


func _say(text: String) -> void:
	_caption.text = text
	_caption.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_caption, "modulate:a", 0.0, 0.6).set_delay(1.0 / _speed)


## Кадр действия: бьющий и цель выдвигаются к середине и увеличиваются (наезд камеры — заглушка до поз).
func _lunge(who: String, target: String) -> void:
	var a: SkFighterView = _views.get(who)
	if a == null:
		return
	var dir := 1.0 if a.fighter().side == "hero" else -1.0
	var tw := create_tween()
	tw.set_parallel()
	tw.tween_property(a, "scale", Vector2(1.12, 1.12), 0.15 / _speed)
	tw.tween_property(a, "position:x", a.position.x + 40 * dir, 0.15 / _speed)
	tw.chain().set_parallel()
	tw.tween_property(a, "scale", Vector2.ONE, 0.25 / _speed)
	tw.tween_property(a, "position:x", a.position.x, 0.25 / _speed)
	var t: SkFighterView = _views.get(target)
	if t != null and t != a:
		var t2 := create_tween()
		t2.tween_property(t, "scale", Vector2(1.06, 1.06), 0.15 / _speed)
		t2.tween_property(t, "scale", Vector2.ONE, 0.2 / _speed)


func _shake(uid: String) -> void:
	var v: SkFighterView = _views.get(uid)
	if v == null:
		return
	var x := v.position.x
	var tw := create_tween()
	for i in 3:
		tw.tween_property(v, "position:x", x + (8 if i % 2 == 0 else -8), 0.04)
	tw.tween_property(v, "position:x", x, 0.04)


func _name(uid: String) -> String:
	var f := sk.by_uid(uid)
	return f.name if f != null else uid


func _play(events: Array) -> void:
	for e: Dictionary in events:
		if not is_inside_tree():
			return
		var k := str(e.get("kind", ""))
		var who := str(e.get("who", ""))
		var to := str(e.get("to", ""))
		var pause := 0.0
		match k:
			"round":
				_say("Раунд %d" % int(e["n"]))
				pause = 0.35
			"skill":
				_say("%s — %s" % [_name(who), str(e.get("name", ""))])
				_lunge(who, str(e.get("target", "")))
				AudioManager.play("place", -6.0)
				pause = 0.35
			"hit":
				_float(to, ("КРИТ −%d" if bool(e["crit"]) else "−%d") % int(e["dmg"]), Palette.GOLD if bool(e["crit"]) else Color("#EB5A5A"), 34 if bool(e["crit"]) else 28)
				_shake(to)
				AudioManager.play("trauma" if bool(e["crit"]) else "fail", -8.0)
				pause = 0.3
			"miss":
				_float(to, "Промах", Palette.SILVER)
				pause = 0.2
			"dodge":
				_float(who, "Уклон", Palette.SILVER)
			"block":
				_float(who, "Панцирь", Color("#C49A5E"), 20)
			"status":
				var st: Array = SkFighterView.STATUS.get(str(e["type"]), ["", Palette.SILVER])
				_float(to, str(SkStatus.NAMES.get(str(e["type"]), e["type"])), st[1], 20)
				pause = 0.12
			"heal":
				_float(who, "+%d" % int(e["value"]), Color("#7DB38A"))
			"psyche":
				_float(who, "%+d психики" % int(e["value"]), Color("#96AAE1"), 18)
			"dot":
				_float(who, "−%d" % int(e["value"]), Color("#C05050"), 22)
				pause = 0.2
			"stunned":
				_float(who, "Оглушён", Color("#E8D070"))
				pause = 0.3
			"edge":
				_say("%s — на грани смерти" % _name(who))
				AudioManager.play("trauma", -4.0)
				pause = 0.5
			"shield":
				_say("Карта принимает удар — %s не на грани" % _name(who))
				pause = 0.4
			"survive":
				_float(who, "выжил (%d/%d)" % [int(e["roll"]), int(e["chance"])], Palette.SILVER, 18)
				pause = 0.4
			"death":
				_say("%s погибает" % _name(who))
				AudioManager.play("death", -2.0)
				pause = 0.8
			"kill", "corpse":
				AudioManager.play("ash", -8.0)
			"crisis":
				_say("%s: %s" % [_name(who), "ПАНИКА" if str(e["state"]) == "panic" else "ПОДЪЁМ ДУХА"])
				pause = 0.7
			"phase", "flee", "summon", "recall", "echo_lost", "guarded", "riposte", "charmed", "extra_turn", "retreat_failed", "retreat_blocked":
				var tx: String = {"phase": str(e.get("text", "")), "flee": "%s бежит" % _name(who), "summon": "%s — в строю" % _name(who),
					"recall": "%s уходит из боя" % _name(who), "echo_lost": "%s рассыпается" % _name(who),
					"guarded": "%s заслоняет" % _name(str(e.get("by", ""))), "riposte": "%s отвечает ударом" % _name(who),
					"charmed": "%s очарован — бьёт своих" % _name(who), "extra_turn": "%s — ещё ход" % _name(who),
					"retreat_failed": "Отступить не удалось", "retreat_blocked": "От него не уйти"}.get(k, "")
				_say(tx)
				pause = 0.45
		if k in ["move", "corpse_gone", "kill", "death", "summon", "recall", "flee", "echo_lost", "swap", "devour"]:
			_sync_views()
		for v: SkFighterView in _views.values():
			v.refresh()
		if pause > 0.0:
			await get_tree().create_timer(pause / _speed).timeout
	_sync_views()
	_show_target()


func _show_result() -> void:
	_busy = true
	_actor = null
	_mark_rings()
	_show_hero(null)
	var res := sk.finish()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var box := _plate(Vector2(660, 330), Vector2(600, 300))
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 12)
	box.add_child(v)
	var title: String = {"win": "ПОБЕДА", "loss": "ПОРАЖЕНИЕ", "retreat": "ОТСТУПЛЕНИЕ"}.get(sk.outcome, "БОЙ ОКОНЧЕН")
	var col: Color = {"win": Palette.GOLD, "loss": Palette.TRAUMA_BRIGHT}.get(sk.outcome, Palette.SILVER)
	var tl := UITheme.label(title, "caps", 44, col)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tl)
	var lost := sk.fighters.filter(func(f: SkFighter) -> bool: return f.is_hero() and f.dead).map(func(f: SkFighter) -> String: return f.name)
	var edge := sk.fighters.filter(func(f: SkFighter) -> bool: return f.is_hero() and f.edge and not f.dead).map(func(f: SkFighter) -> String: return f.name)
	var lines := ["Раундов: %d" % sk.round_no]
	if not edge.is_empty():
		lines.append("На грани: " + ", ".join(edge))
	if not lost.is_empty():
		lines.append("Погибли: " + ", ".join(lost))
	var ll := UITheme.label("\n".join(lines), "sans", 18, Palette.TEXT)
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ll)
	var b := Button.new()
	b.text = "Дальше"
	b.custom_minimum_size = Vector2(200, 50)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void:
		closed.emit(res)
		close())
	v.add_child(b)


## Точки позиций на кнопке навыка: 4 своих (золото — откуда) и 4 вражеских (багрянец — куда; у навыков на союзника — зелень).
class _Dots:
	extends Control
	var from: Array = []
	var to: Array = []
	var side := "enemy"

	func _draw() -> void:
		for i in 4:
			var p := 4 - i
			draw_circle(Vector2(5 + i * 10, 5), 3.5, Palette.GOLD if from.has(p) else Color(0.2, 0.21, 0.26))
		var tc := Palette.TRAUMA_BRIGHT if side == "enemy" else Color("#6FA47B")
		for i in 4:
			var p2 := i + 1
			var on := (side == "enemy" and to.has(p2)) or (side == "ally" and (to.is_empty() or to.has(p2)))
			draw_circle(Vector2(52 + i * 10, 5), 3.5, tc if on else Color(0.2, 0.21, 0.26))
