class_name SleeperMap
extends Control
## «Карта Спящего» (docs/16 §11.6) — карта главы планом сверху. Только отрисовка: что где и в каком облике,
## решают MapRules и TideRules. Слои снизу вверх:
##   основа → вода прилива (шейдер по карте высот) → тропы между открытыми местами → виньетки мест
##   (облик — MapRules.place_state, смена — наплывом) → тени облаков → туман неизвестного (шейдер)
##   → кольца «вода идёт», подписи мест, дождь и молнии.
## Небо не рисуется: день, ночь, кровавая луна, шторм и затмение — цветом всей карты и эффектами.
## Угрозы-точки (GateRules): проломы на стене по стадии, рой — полоса следа и тёмное пятно, метки мест по облику
## (сирены, баррикады, копоть, слизь), Тревога — красные отблески. Карта без поля height — без воды.
## Основа покрывает всё окно с запасом (`zoom`), карту можно чуть сдвинуть мышью (`pan`, сигнал `panned`).

const WATER_SHADER := preload("res://scenes/map/sleeper_water.gdshader")
const FOG_SHADER := preload("res://scenes/map/sleeper_fog.gdshader")
const GLOW_SHADER := preload("res://scenes/map/sleeper_glow.gdshader")
const SILVER := Color(0.82, 0.88, 1.0)
const GOLDEN := Color(1.0, 0.8, 0.42)
const FADE := 0.9
const REVEAL_R := 0.17           # радиус открытого круга — доля высоты основы
const LEVEL_SPEED := 18.0        # сколько единиц высоты вода проходит за секунду
const SKY_TINT := {"night": Color(0.8, 0.84, 0.97), "day": Color(1.05, 1.03, 0.99), "eclipse": Color(0.5, 0.5, 0.64),
	"blood_moon": Color(1.06, 0.62, 0.6), "storm": Color(0.62, 0.68, 0.8)}

signal panned(offset: Vector2)

var cfg: Dictionary = {}
var view := Rect2(0, 0, 1920, 1080)     # область экрана под карту
var rect := Rect2()                      # где лежит основа (в координатах _clip, без сдвига)
var pan := Vector2.ZERO                  # сдвиг карты мышью (в пределах запаса основы)
var sky := ""

var _clip: Control
var _world: Control
var _bg: TextureRect
var _aspect := 2.0
var _content: Content      # последнее состояние из sync — чтобы переложить места при смене размера окна
var _state: RunState
var _water: ColorRect
var _ink: Control
var _sprites_layer: Control
var _shade: Control
var _fog: ColorRect
var _over: Control
var _threat: Control
var _weather: Control
var _sprites := {}        # место -> TextureRect
var _shown := {}          # место -> облик на экране ("" — место скрыто)
var _tex := {}            # путь -> Texture2D
var _level := 55.0
var _level_to := 55.0
var _reveal := {}         # место -> 0..1 (проявление тушью)
var _info := {}           # что рисовать поверх: {revealed, flooded, warn, names}
var _t := 0.0
var _flash := 0.0
var _next_flash := 5.0
var _clouds: Array = []
var _rng := RandomNumberGenerator.new()
# фигура (docs/18): лагерь рисует не костёр-точка, а сцена у фигуры; при перетаскивании — подсветка участков
var figure_mode := false
# подсветка участков при перетаскивании фигуры: участок загорается светом вверх (серебро — можно, золото — под
# фигурой, тёмно-красный — нельзя); меняются — карта сама перекрашивает участки (_apply_highlight)
var drag_targets: Array = []:     # куда фигуру можно поставить
	set(v):
		drag_targets = v
		_apply_highlight()
var drag_blocked := {}:           # соседние участки, куда нельзя: место -> причина
	set(v):
		drag_blocked = v
		_apply_highlight()
var drag_hover := "":             # участок под фигурой
	set(v):
		if v != drag_hover:
			drag_hover = v
			_apply_highlight()
var _glow: Control               # столбы света и искры над подсвеченными участками (сложение цветов)
var _mats := {}                  # silver | gold | block -> ShaderMaterial


static func make(config: Dictionary, area: Rect2) -> SleeperMap:
	var m := SleeperMap.new()
	m.cfg = config
	m.view = area
	return m


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_rng.seed = 17
	_clip = _layer(self)
	_clip.position = view.position
	_clip.size = view.size
	_clip.clip_contents = true
	var base := _load("base")
	var aspect := float(base.get_width()) / float(base.get_height()) if base != null else 2.0
	_aspect = aspect
	_world = _layer(_clip)
	_bg = TextureRect.new()
	var bg := _bg
	bg.texture = base
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(bg)
	_water = ColorRect.new()
	_water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(_water)
	if cfg.has("height"):
		_build_water(aspect)
	else:
		_water.visible = false   # карта без воды (Академия)
	_ink = _layer(_world)
	_ink.draw.connect(_draw_paths)
	_sprites_layer = _layer(_world)
	_glow = _layer(_world)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	_threat = _layer(_world)
	_threat.draw.connect(_draw_threat)
	_shade = _layer(_world)
	_shade.draw.connect(_draw_shade)
	_fog = ColorRect.new()
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	fm.shader = FOG_SHADER
	fm.set_shader_parameter("fog_tex", _load(str(cfg.get("fog", "fog_tile.webp")).get_basename()))
	fm.set_shader_parameter("aspect", aspect)
	_fog.material = fm
	_world.add_child(_fog)
	_fit()
	set_pan(Vector2((view.size.x - rect.size.x) / 2.0, -float(cfg.get("view_top", 0.08)) * rect.size.y))
	_over = _layer(_world)
	_over.draw.connect(_draw_over)
	_weather = _layer(_clip)
	_weather.draw.connect(_draw_weather)
	var names := ["clouds/cloud_01", "clouds/cloud_02", "clouds/cloud_03", "clouds/cloud_04"]
	for i in 5:
		_clouds.append({"tex": Vfx.tex(names[i % names.size()]), "pos": Vector2(_rng.randf() * rect.size.x, _rng.randf() * rect.size.y),
			"scale": _rng.randf_range(1.4, 2.4), "speed": _rng.randf_range(5.0, 11.0)})


## Вода прилива: шейдер по карте высот.
func _build_water(aspect: float) -> void:
	var wm := ShaderMaterial.new()
	wm.shader = WATER_SHADER
	wm.set_shader_parameter("height_tex", _load(str(cfg.get("height", "height.png")).get_basename(), str(cfg.get("height", "height.png")).get_extension()))
	wm.set_shader_parameter("water_tex", _load(str(cfg.get("water", "water_tile.webp")).get_basename()))
	wm.set_shader_parameter("aspect", aspect)
	_level = _levels("normal")
	_level_to = _level
	wm.set_shader_parameter("normal_level", _level)
	wm.set_shader_parameter("level", _level)
	_water.material = wm


## Основа покрывает окно целиком и чуть больше — запас для сдвига мышью.
func _fit() -> void:
	_clip.position = view.position
	_clip.size = view.size
	var w := maxf(view.size.x, view.size.y * _aspect) * float(cfg.get("zoom", 1.15))
	rect.size = Vector2(w, w / _aspect)
	rect.position = Vector2.ZERO
	for layer: Control in [_bg, _water, _fog]:
		layer.position = rect.position
		layer.size = rect.size


## Окно сменило размер: основа, места и сдвиг — под новую область. Сдвиг сохраняет середину окна.
func relayout(area: Rect2) -> void:
	if area == view or _clip == null:
		return
	var mid := (view.size / 2.0 - pan) / rect.size
	view = area
	_fit()
	for lid: String in _sprites:
		var tr: TextureRect = _sprites[lid]
		if _content == null or not is_instance_valid(tr):
			continue
		var sz := _sprite_size(_content, _state, lid)
		tr.size = Vector2(sz, sz)
		tr.position = center(_content, _state, lid) - view.position - tr.size / 2.0
		tr.pivot_offset = tr.size / 2.0
	if _content != null:
		sync(_content, _state, sky)
	set_pan(view.size / 2.0 - mid * rect.size)
	panned.emit(pan)


func _layer(parent: Control) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(c)
	return c


func _load(name: String, ext: String = "webp") -> Texture2D:
	var path := "%s%s.%s" % [cfg.get("art", ""), name, ext]
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


func _levels(key: String) -> float:
	return float(cfg.get("levels", {}).get(key, 55))


# --- координаты -----------------------------------------------------------------------

## Сдвинуть карту (в пределах запаса основы). Метки над картой двигает владелец по сигналу `panned`.
func set_pan(offset: Vector2) -> void:
	var lo := view.size - rect.size
	var next := Vector2(clampf(offset.x, minf(lo.x, 0.0), 0.0), clampf(offset.y, minf(lo.y, 0.0), 0.0))
	if next == pan and _world.position == pan:
		return
	pan = next
	_world.position = pan
	panned.emit(pan)


## Поставить точку карты (координаты без сдвига) в заданное место окна — например, лагерь в центр.
func focus(p: Vector2, at: Vector2) -> void:
	set_pan(at - (p - view.position))


## Точка основы (доли) → экран без сдвига (метки лежат в слое, который сдвигается вместе с картой).
func to_screen(p: Vector2) -> Vector2:
	return view.position + rect.position + p * rect.size


## Центр виньетки места на экране.
func center(content: Content, state: RunState, lid: String) -> Vector2:
	return to_screen(MapRules.anchor(content, state, lid))


## «Посадочное пятно» места: сюда встаёт метка миссии.
func foot(content: Content, state: RunState, lid: String) -> Vector2:
	var a := MapRules.anchor(content, state, lid)
	var s := MapRules.size_of(content, state, lid)
	return to_screen(a) + Vector2(0.0, s * rect.size.x * float(cfg.get("foot", 0.28)))


func _sprite_size(content: Content, state: RunState, lid: String) -> float:
	return MapRules.size_of(content, state, lid) * rect.size.x


# --- состояние ------------------------------------------------------------------------

## Привести карту к состоянию прохождения: облики мест, вода, туман, небо.
func sync(content: Content, state: RunState, sky_now: String) -> void:
	_content = content
	_state = state
	if sky_now != sky:
		_set_sky(sky_now, sky != "")
	var revealed: Array = []
	var flooded: Array = []
	var warn: Array = []
	var kn := MapRules.known(content, state)
	for lid: String in cfg.get("places", {}):
		var here := MapRules.present(content, state, lid)
		var st := MapRules.place_state(content, state, lid, sky_now) if here and not MapRules.states(content, state, lid).is_empty() else ""
		if str(_shown.get(lid, "-")) != st:
			_show_place(content, state, lid, st)
		if not here:
			_reveal.erase(lid)
			continue
		if content.shops.has(lid) or kn.has(lid):
			revealed.append(lid)
			if not _reveal.has(lid):
				_reveal[lid] = 0.0 if not _info.is_empty() else 1.0
		if TideRules.flooded(state, lid):
			flooded.append(lid)
		elif TideRules.threatened(state, lid):
			warn.append(lid)
	match TideRules.phase(state):
		"flood":
			_level_to = _levels("storm" if sky_now == "storm" else "flood")
		"warn":
			_level_to = _levels("warn")
		_:
			_level_to = _levels("normal")
	var feet := {}
	var centers := {}
	var sizes := {}
	var names := {}
	for lid: String in revealed:
		feet[lid] = foot(content, state, lid) - view.position
		if content.shops.has(lid):
			feet.erase(lid)   # у лавки своя подпись (ShopIcon)
		centers[lid] = center(content, state, lid) - view.position
		sizes[lid] = _sprite_size(content, state, lid)
		names[lid] = str(content.locations.get(lid, content.shops.get(lid, {})).get("name", lid))
	var paths: Array = []
	var water: Array = []
	# тропы сейчас (MapRules.links): постоянные, сеть бури, водные (TerrainRules); заваленные — не рисуются
	for pair: Array in MapRules.links(content, state):
		if MapRules.is_emerging(content, str(pair[0])) or MapRules.is_emerging(content, str(pair[1])):
			continue
		if revealed.has(pair[0]) and revealed.has(pair[1]):
			paths.append(pair)
			if TerrainRules._is_water(content, state, str(pair[0]), str(pair[1])):
				water.append(pair)
	# появившиеся места связаны тропой с ближайшим открытым
	for lid: String in MapRules.emerged(state):
		if not revealed.has(lid):
			continue
		var best := ""
		var bd := INF
		for other: String in revealed:
			if other == lid or MapRules.is_emerging(content, other):
				continue
			var d: float = (centers[other] as Vector2).distance_to(centers[lid])
			if d < bd:
				bd = d
				best = other
		if best != "":
			paths.append([lid, best])
	# лагерь-стоянка и соседние места (DayRules): куда можно пойти сегодня
	var near: Array = []
	if DayRules.restricted(content, state):
		for n: String in MapRules.neighbors(content, state, state.party_at):
			if revealed.has(n) and content.locations.has(n) and not flooded.has(n):
				near.append(n)
	_info = {"revealed": revealed, "flooded": flooded, "warn": warn, "feet": feet, "centers": centers,
		"sizes": sizes, "names": names, "paths": paths, "near": near,
		"camp": state.party_at if revealed.has(state.party_at) and not figure_mode else "",
		"figure": state.party_at if figure_mode else "",
		"threat": _threat_info(content, state, revealed), "alarm": GateRules.alarm(state), "water": water,
		"boat": bool(state.flags.get("boat", false)), "terrain": _terrain_info(content, state, revealed)}
	_ink.queue_redraw()


## Что рисовать от угроз: проломы по стадии, метки мест по облику, рой (откуда → где).
func _threat_info(content: Content, state: RunState, revealed: Array) -> Dictionary:
	if not GateRules.active(content, state):
		return {}
	var dec: Dictionary = cfg.get("decals", {})
	var ptex: Dictionary = cfg.get("point_tex", {})
	var pts: Array = []
	for pid: String in GateRules.points(state):
		var d := GateRules.point_def(content, state, pid)
		if not bool(d.get("sprite", true)):
			continue
		var e: Dictionary = GateRules.points(state)[pid]
		var st0 := GateRules.stage(state, pid)
		# Врата: в первый день открытия — «открываются», в день закрытия — «схлопываются»
		var look := st0
		if st0 == "open" and int(e.get("open_day", -1)) == state.day and ptex.has("opening"):
			look = "opening"
		elif st0 == "scar" and int(e.get("closed_day", -1)) == state.day and ptex.has("closing"):
			look = "closing"
		var at: Array = d.get("at", [0.5, 0.5])
		pts.append({"at": to_screen(Vector2(float(at[0]), float(at[1]))) - view.position, "size": float(d.get("size", 0.11)) * rect.size.x,
			"tex": str(ptex.get(look, "%s_%s" % [str(dec.get("point", "breach")), look])), "stage": st0,
			"glow": str(dec.get("glow", "")) if st0 in ["open", "signal"] else "", "scar_fade": float(e.get("left", 7)) / 7.0 if st0 == "scar" else 1.0})
	var marks: Array = []
	for lid: String in GateRules.sites(state):
		if not revealed.has(lid):
			continue
		var st := GateRules.site_state(state, lid)
		marks.append({"at": center(content, state, lid) - view.position, "size": _sprite_size(content, state, lid), "state": st,
			"decals": Array(dec.get(st, []))})
	# эвакуированные кварталы — автобусы; в Тревогу — армейские блокпосты у мест с людьми
	for lid: String in Dictionary(state.flags.get("evac", {})):
		if GateRules.evacuated(state, lid) and revealed.has(lid) and str(dec.get("evac", "")) != "":
			marks.append({"at": center(content, state, lid) - view.position, "size": _sprite_size(content, state, lid), "state": "evac",
				"decals": [str(dec["evac"])]})
	if GateRules.big_alarm(content, state) and str(dec.get("ally", "")) != "":
		for lid: String in ["gov_quarter", "hospital", "bunker"]:
			if revealed.has(lid):
				marks.append({"at": center(content, state, lid) - view.position, "size": _sprite_size(content, state, lid), "state": "ally",
					"decals": [str(dec["ally"])]})
	# дороги у разбитых кварталов и у обрушенного моста — полосы повреждений
	var roads: Array = []
	var rd: Dictionary = dec.get("roads", {})
	if not rd.is_empty():
		for pair: Array in cfg.get("paths", []):
			var worst := ""
			for k in 2:
				var st2 := GateRules.site_state(state, str(pair[k]))
				if rd.has(st2) and (worst == "" or ["repair", "damaged", "ruined", "collapsed"].find(st2) > ["repair", "damaged", "ruined", "collapsed"].find(worst)):
					worst = st2
			if worst != "" and revealed.has(pair[0]) and revealed.has(pair[1]):
				roads.append({"a": center(content, state, str(pair[0])) - view.position, "b": center(content, state, str(pair[1])) - view.position,
					"tex": str(rd[worst])})
	var sw: Array = []
	for e: Dictionary in GateRules.swarms(state):
		var to := center(content, state, str(e.get("at", ""))) - view.position
		var from := to
		if str(e.get("from", "")) != "":
			from = center(content, state, str(e["from"])) - view.position
		else:
			var at2: Array = GateRules.point_def(content, state, str(e.get("point", ""))).get("at", [])
			if at2.size() == 2:
				from = to_screen(Vector2(float(at2[0]), float(at2[1]))) - view.position
		sw.append({"from": from, "to": to, "size": _sprite_size(content, state, str(e.get("at", "")))})
	return {"points": pts, "marks": marks, "swarms": sw, "strip": str(dec.get("swarm", "")), "roads": roads,
		"label": "волна" if GateRules.kind(content, state) == "gate" else "рой"}


## Глава 4: зоны (свечение по местам), подвижные угрозы (фишка и след), завалы на тропах.
func _terrain_info(content: Content, state: RunState, revealed: Array) -> Dictionary:
	var zones: Array = []
	var zc := ZoneRules.cfg(content, state)
	for zid: String in zc:
		var z: Dictionary = zc[zid]
		var col: Array = z.get("color", [1.0, 0.5, 0.3])
		var at: Array = []
		for lid: String in ZoneRules.places(content, state, zid):
			if revealed.has(lid):
				at.append({"at": center(content, state, lid) - view.position, "size": _sprite_size(content, state, lid),
					"center": lid == str(z.get("center", ""))})
		if not at.is_empty():
			zones.append({"places": at, "color": Color(float(col[0]), float(col[1]), float(col[2])), "name": str(z.get("name", zid)).to_lower()})
	var movers: Array = []
	var stack := {}   # сколько угроз уже стоит в месте — следующую рисуем ниже
	for mid: String in MoverRules.movers(state):
		if not MoverRules.active(state, mid):
			continue
		var m: Dictionary = MoverRules.movers(state)[mid]
		var lid := str(m.get("at", ""))
		var from := str(m.get("from", ""))
		if not revealed.has(lid) and not revealed.has(from):
			continue
		movers.append({"at": center(content, state, lid) - view.position if revealed.has(lid) else Vector2.INF,
			"from": center(content, state, from) - view.position if revealed.has(from) and from != lid else Vector2.INF,
			"size": _sprite_size(content, state, lid) if revealed.has(lid) else 100.0,
			"name": MoverRules.name_of(content, state, mid), "wounded": bool(m.get("wounded", false)), "slot": int(stack.get(lid, 0))})
		stack[lid] = int(stack.get(lid, 0)) + 1
	var rubble: Array = []
	var rb: Dictionary = cfg.get("rubble", {})
	var st: Dictionary = state.flags.get("rubble", {})
	for rid: String in rb:
		var pr: Array = rb[rid].get("pair", [])
		if str(st.get(rid, "")) == "blocked" and pr.size() == 2 and revealed.has(pr[0]) and revealed.has(pr[1]):
			var at2: Array = rb[rid].get("at", [0.5, 0.5])
			rubble.append(to_screen(Vector2(float(at2[0]), float(at2[1]))) - view.position)
	if zones.is_empty() and movers.is_empty() and rubble.is_empty():
		return {}
	return {"zones": zones, "movers": movers, "rubble": rubble}


## Сменить облик места наплывом ("" — место уходит с карты).
func _show_place(content: Content, state: RunState, lid: String, st: String) -> void:
	var old: TextureRect = _sprites.get(lid)
	_shown[lid] = st
	var first := old == null
	if st != "":
		var tr := TextureRect.new()
		tr.texture = _load("%s_%s" % [lid, st])
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sz := _sprite_size(content, state, lid)
		var c := center(content, state, lid) - view.position
		tr.size = Vector2(sz, sz)
		tr.position = c - tr.size / 2.0
		tr.pivot_offset = tr.size / 2.0
		_sprites_layer.add_child(tr)
		_sprites[lid] = tr
		if drag_targets.has(lid) or drag_blocked.has(lid):
			_apply_highlight.call_deferred()
		if not first and not Vfx.reduced():
			tr.modulate.a = 0.0
			create_tween().tween_property(tr, "modulate:a", 1.0, FADE)
		elif first and MapRules.is_emerging(content, lid) and not _info.is_empty() and not Vfx.reduced():
			# место поднимается из ила
			tr.modulate.a = 0.0
			tr.scale = Vector2(0.85, 0.85)
			var tw := create_tween().set_parallel(true)
			tw.tween_property(tr, "modulate:a", 1.0, FADE * 1.6)
			tw.tween_property(tr, "scale", Vector2.ONE, FADE * 1.6).set_trans(Tween.TRANS_SINE)
	else:
		_sprites.erase(lid)
	if old != null:
		if Vfx.reduced():
			old.queue_free()
		else:
			var tw2 := create_tween()
			tw2.tween_interval(FADE * 0.5)
			tw2.tween_property(old, "modulate:a", 0.0, FADE * 0.8)
			tw2.tween_callback(old.queue_free)


func _set_sky(next: String, animate: bool) -> void:
	sky = next
	var tint: Color = SKY_TINT.get(next, Color.WHITE)
	if animate and not Vfx.reduced():
		create_tween().tween_property(_world, "modulate", tint, MapBackdrop.FADE_SEC)
	else:
		_world.modulate = tint


# --- жизнь карты ----------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if not is_equal_approx(_level, _level_to) and _water.material != null:
		_level = move_toward(_level, _level_to, LEVEL_SPEED * delta)
		(_water.material as ShaderMaterial).set_shader_parameter("level", _level)
	var holes := PackedVector4Array()
	var revealed: Array = _info.get("revealed", [])
	for lid: String in revealed:
		_reveal[lid] = minf(1.0, float(_reveal.get(lid, 1.0)) + delta / 1.8)
		var a := ((_info["centers"][lid] as Vector2) - rect.position) / rect.size
		holes.append(Vector4(a.x, a.y, REVEAL_R, ease(float(_reveal[lid]), 0.5)))
		if holes.size() >= 40:
			break
	var fm := _fog.material as ShaderMaterial
	fm.set_shader_parameter("holes", holes)
	fm.set_shader_parameter("hole_count", holes.size())
	if not Vfx.reduced():
		for cl: Dictionary in _clouds:
			cl["pos"] += Vector2(cl["speed"] * delta, cl["speed"] * 0.25 * delta)
			if cl["pos"].x > rect.size.x + 400.0:
				cl["pos"] = Vector2(-500.0, _rng.randf() * rect.size.y)
		if sky == "storm":
			_next_flash -= delta
			if _next_flash <= 0.0:
				_flash = 1.0
				_next_flash = _rng.randf_range(4.0, 11.0)
		_flash = maxf(0.0, _flash - delta * 2.6)
	_shade.queue_redraw()
	_over.queue_redraw()
	if not drag_targets.is_empty() or not drag_blocked.is_empty():
		_glow.queue_redraw()
	_weather.queue_redraw()
	if not Dictionary(_info.get("threat", {})).is_empty() or not Dictionary(_info.get("terrain", {})).is_empty():
		_threat.queue_redraw()


## Угрозы: пролом на стене, метки мест, рой и его след.
func _draw_threat() -> void:
	_draw_terrain()
	var th: Dictionary = _info.get("threat", {})
	if th.is_empty():
		return
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	# дороги: трещины, брошенные машины, завалы — вдоль троп (между центрами мест, без краёв у самих мест)
	for rd: Dictionary in th.get("roads", []):
		var rt := _load(str(rd["tex"]))
		if rt == null:
			continue
		var a0 := Vector2(rd["a"])
		var b0 := Vector2(rd["b"])
		var ln0 := a0.distance_to(b0) * 0.6
		_threat.draw_set_transform((a0 + b0) / 2.0, (b0 - a0).angle(), Vector2.ONE)
		_threat.draw_texture_rect(rt, Rect2(-ln0 / 2.0, -ln0 * 0.1, ln0, ln0 * 0.2), false, Color(1, 1, 1, 0.9))
		_threat.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for p: Dictionary in th.get("points", []):
		var tex := _load(str(p["tex"]))
		var sz := float(p["size"])
		var r := Rect2(Vector2(p["at"]) - Vector2(sz, sz) / 2.0, Vector2(sz, sz))
		var glow := _load(str(p.get("glow", "")))
		if glow != null:
			var gs := sz * (1.6 + 0.15 * pulse)
			_threat.draw_texture_rect(glow, Rect2(Vector2(p["at"]) - Vector2(gs, gs) / 2.0, Vector2(gs, gs)), false,
				Color(1, 1, 1, (0.35 if str(p["stage"]) == "signal" else 0.7) * (0.7 + 0.3 * pulse)))
		if tex != null:
			var alpha := float(p.get("scar_fade", 1.0)) * 0.6 + 0.4 if str(p["stage"]) == "scar" else 1.0
			_threat.draw_texture_rect(tex, r, false, Color(1, 1, 1, 0.75 + 0.25 * pulse) if str(p["stage"]) == "signal" else Color(1, 1, 1, alpha))
		if str(p["stage"]) in ["signal", "open"]:
			var c := Vector2(p["at"])
			for k in 2:
				_threat.draw_arc(c, sz * (0.3 + 0.06 * k + 0.04 * pulse), 0.0, TAU, 40, Color(1.0, 0.2, 0.15, (0.5 - 0.2 * k) * (0.5 + 0.5 * pulse)), 3.0, true)
	for m: Dictionary in th.get("marks", []):
		var c2 := Vector2(m["at"])
		var s2 := float(m["size"])
		var offs := [Vector2(0.24, -0.2), Vector2(-0.3, 0.22), Vector2(0.18, 0.26)]
		var i := 0
		for dn: String in m.get("decals", []):
			var t2 := _load(dn)
			if t2 == null:
				continue
			var ds := s2 * 0.3
			_threat.draw_texture_rect(t2, Rect2(c2 + offs[i % offs.size()] * s2 - Vector2(ds, ds) / 2.0, Vector2(ds, ds)), false)
			i += 1
		if str(m["state"]) in ["alarm", "fight", "lockdown", "leak", "breached"]:
			_threat.draw_arc(c2, s2 * 0.44, 0.0, TAU, 48, Color(1.0, 0.18, 0.12, 0.25 + 0.3 * pulse), 2.5, true)
		elif str(m["state"]) == "burning":
			_threat.draw_circle(c2, s2 * 0.3, Color(1.0, 0.45, 0.1, 0.10 + 0.08 * pulse))
	var strip := _load(str(th.get("strip", "")))
	var f := UITheme.font("sans_bold")
	for sw: Dictionary in th.get("swarms", []):
		var a := Vector2(sw["from"])
		var b := Vector2(sw["to"])
		var s3 := float(sw["size"])
		if strip != null and a.distance_to(b) > 4.0:
			var mid := (a + b) / 2.0
			var ln := a.distance_to(b)
			_threat.draw_set_transform(mid, (b - a).angle(), Vector2.ONE)
			_threat.draw_texture_rect(strip, Rect2(-ln / 2.0, -ln * 0.12, ln, ln * 0.24), false, Color(1, 1, 1, 0.85))
			_threat.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var r3 := s3 * (0.2 + 0.03 * pulse)
		_threat.draw_circle(b, r3, Color(0.02, 0.0, 0.03, 0.55))
		_threat.draw_arc(b, r3, 0.0, TAU, 40, Color(0.75, 0.1, 0.12, 0.8), 3.0, true)
		var t := str(th.get("label", "рой"))
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		_threat.draw_string_outline(f, b + Vector2(-w / 2.0, 6.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.9))
		_threat.draw_string(f, b + Vector2(-w / 2.0, 6.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.45, 0.4))


## Глава 4: свечение зон под местами, завалы на тропах, фишки угроз со следом (TerrainRules, ZoneRules, MoverRules).
func _draw_terrain() -> void:
	var tr: Dictionary = _info.get("terrain", {})
	if tr.is_empty():
		return
	var pulse := 0.5 + 0.5 * sin(_t * 2.2)
	var f := UITheme.font("sans_bold")
	for z: Dictionary in tr.get("zones", []):
		var col: Color = z["color"]
		for p: Dictionary in z["places"]:
			var c := Vector2(p["at"])
			var r := float(p["size"]) * 0.5
			for k in 5:
				var rr := r * (1.0 - k * 0.16) * (1.0 + 0.04 * pulse)
				_threat.draw_circle(c, rr, Color(col.r, col.g, col.b, 0.05 + 0.02 * pulse))
			_threat.draw_arc(c, r * (1.0 + 0.04 * pulse), 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.35 + 0.2 * pulse), 2.0, true)
			if bool(p["center"]):
				var t := str(z["name"])
				var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
				var at := c + Vector2(-w / 2.0, -r - 6.0)
				_threat.draw_string_outline(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color(0, 0, 0, 0.9))
				_threat.draw_string(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col.lightened(0.3))
	for rp: Vector2 in tr.get("rubble", []):
		for k in 5:
			var off := Vector2(cos(k * 2.1) * 11.0, sin(k * 1.7) * 6.0)
			_threat.draw_circle(rp + off, 9.0 - k, Color(0.25, 0.23, 0.22, 0.95))
			_threat.draw_arc(rp + off, 9.0 - k, 0.0, TAU, 16, Color(0, 0, 0, 0.8), 1.5, true)
		_threat.draw_line(rp + Vector2(-14, -14), rp + Vector2(14, 14), Color(1.0, 0.35, 0.25, 0.9), 3.0, true)
		_threat.draw_line(rp + Vector2(-14, 14), rp + Vector2(14, -14), Color(1.0, 0.35, 0.25, 0.9), 3.0, true)
	for m: Dictionary in tr.get("movers", []):
		var at2 := Vector2(m["at"])
		var fr := Vector2(m["from"])
		var col2 := Color(1.0, 0.6, 0.2) if bool(m["wounded"]) else Color(0.95, 0.15, 0.12)
		# след: пунктир от прошлого места
		if fr != Vector2.INF and at2 != Vector2.INF:
			for i in 12:
				if i % 2 == 0:
					_threat.draw_line(fr.lerp(at2, i / 12.0), fr.lerp(at2, (i + 1) / 12.0), Color(col2.r, col2.g, col2.b, 0.55), 4.0, true)
		elif fr != Vector2.INF:
			_threat.draw_circle(fr, 10.0, Color(col2.r, col2.g, col2.b, 0.35))   # место не видно — только следы
		if at2 == Vector2.INF:
			continue
		var c2 := at2 + Vector2(float(m["size"]) * 0.3, -float(m["size"]) * 0.22 + 52.0 * int(m.get("slot", 0)))
		var r2 := 15.0 + 2.0 * pulse
		_threat.draw_circle(c2, r2 + 6.0, Color(col2.r, col2.g, col2.b, 0.18 + 0.15 * pulse))
		_threat.draw_circle(c2, r2, Color(0.04, 0.02, 0.03, 0.92))
		_threat.draw_arc(c2, r2, 0.0, TAU, 32, col2, 3.0, true)
		_threat.draw_circle(c2 + Vector2(-5, -2), 2.6, col2)
		_threat.draw_circle(c2 + Vector2(5, -2), 2.6, col2)
		var t2 := str(m["name"]) + (" (ранен)" if bool(m["wounded"]) else "")
		var w2 := f.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_threat.draw_string_outline(f, c2 + Vector2(-w2 / 2.0, r2 + 16.0), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color(0, 0, 0, 0.9))
		_threat.draw_string(f, c2 + Vector2(-w2 / 2.0, r2 + 16.0), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col2.lightened(0.35))


func _draw_shade() -> void:
	# тени облаков скользят по земле
	for cl: Dictionary in _clouds:
		var tex: Texture2D = cl["tex"]
		if tex == null:
			continue
		var sz := tex.get_size() * float(cl["scale"])
		_shade.draw_texture_rect(tex, Rect2(cl["pos"], sz), false, Color(0, 0, 0, 0.2 if sky != "day" else 0.14))


func _draw_paths() -> void:
	var centers: Dictionary = _info.get("centers", {})
	var sizes: Dictionary = _info.get("sizes", {})
	var flooded: Array = _info.get("flooded", [])
	for pair: Array in _info.get("paths", []):
		var a: Vector2 = centers[pair[0]]
		var b: Vector2 = centers[pair[1]]
		var dir := (b - a).normalized()
		a += dir * float(sizes[pair[0]]) * 0.3
		b -= dir * float(sizes[pair[1]]) * 0.3
		var wet: bool = flooded.has(pair[0]) or flooded.has(pair[1])
		var ink := Color(0.62, 0.78, 0.92, 0.45) if wet else Color(0.86, 0.84, 0.78, 0.55)
		if Array(_info.get("water", [])).has(pair):
			ink = Color(0.45, 0.7, 1.0, 0.75 if bool(_info.get("boat", false)) else 0.3)   # Чёрная вода: только на лодке
		var mid := (a + b) / 2.0 + Vector2(-dir.y, dir.x) * a.distance_to(b) * 0.08
		var pts: Array = []
		for i in 25:
			var t := i / 24.0
			pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
		for i in 24:
			if i % 2 == 1:
				continue
			_ink.draw_line(pts[i], pts[i + 1], Color(0, 0, 0, 0.45), 6.0, true)
			_ink.draw_line(pts[i], pts[i + 1], ink, 3.0, true)


func _draw_over() -> void:
	var centers: Dictionary = _info.get("centers", {})
	var sizes: Dictionary = _info.get("sizes", {})
	# вода идёт: кольца под местами, которые уйдут
	for lid: String in _info.get("warn", []):
		var c: Vector2 = centers.get(lid, Vector2.ZERO)
		var r := float(sizes.get(lid, 100.0)) * 0.42
		var pulse := 0.5 + 0.5 * sin(_t * 3.0)
		for k in 2:
			var rr := r * (1.0 + 0.12 * k + 0.05 * pulse)
			var pts := PackedVector2Array()
			for i in 49:
				var ang := TAU * i / 48.0
				pts.append(c + Vector2(cos(ang) * rr, sin(ang) * rr * 0.62))
			_over.draw_polyline(pts, Color(0.55, 0.8, 1.0, (0.55 - 0.25 * k) * (0.6 + 0.4 * pulse)), 3.0, true)
	_draw_figure_marks(centers, sizes)
	# соседние места — сюда можно пойти сегодня
	for lid: String in ([] if figure_mode else _info.get("near", [])):
		var nc: Vector2 = centers.get(lid, Vector2.ZERO)
		var nr := float(sizes.get(lid, 100.0)) * 0.46
		for i in 24:
			if i % 2 == 1:
				continue
			var a0 := TAU * i / 24.0
			var a1 := TAU * (i + 1) / 24.0
			_over.draw_line(nc + Vector2(cos(a0) * nr, sin(a0) * nr * 0.6), nc + Vector2(cos(a1) * nr, sin(a1) * nr * 0.6),
				Color(0.89, 0.79, 0.56, 0.35), 2.0, true)
	# лагерь: костёр у места стоянки
	var camp := str(_info.get("camp", ""))
	if camp != "" and centers.has(camp):
		var cc: Vector2 = centers[camp] + Vector2(-float(sizes[camp]) * 0.3, float(sizes[camp]) * 0.18)
		var fl := 0.8 + 0.2 * sin(_t * 9.0) * sin(_t * 5.3)
		_over.draw_circle(cc, 26.0 * fl, Color(1.0, 0.55, 0.2, 0.16))
		_over.draw_circle(cc, 14.0 * fl, Color(1.0, 0.62, 0.25, 0.35))
		_over.draw_circle(cc, 6.0, Color(1.0, 0.85, 0.5, 0.95))
		var cf := UITheme.font("sans_bold")
		var ct := "лагерь"
		var cw := cf.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_over.draw_string_outline(cf, cc + Vector2(-cw / 2.0, -22.0), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color(0, 0, 0, 0.9))
		_over.draw_string(cf, cc + Vector2(-cw / 2.0, -22.0), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.8, 0.5))
	# подписи открытых мест — светятся серебром (просьба владельца 03.10): мягкий ореол, тёмная кромка, светлый текст
	var f := UITheme.font("title")
	var feet: Dictionary = _info.get("feet", {})
	var names: Dictionary = _info.get("names", {})
	var breath := 0.85 + 0.15 * sin(_t * 1.4)
	for lid: String in feet:
		var fp: Vector2 = feet[lid]
		var text: String = names[lid]
		var fs := 21
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := fp + Vector2(-tw / 2.0, 24.0)
		var wet: bool = _info["flooded"].has(lid)
		var glow := Color(0.55, 0.78, 1.0) if wet else Color(0.82, 0.86, 0.95)
		var col := Color(0.72, 0.88, 1.0) if wet else Color(0.93, 0.95, 1.0)
		for k in 5:   # ореол: от широкого и бледного к узкому и яркому
			_over.draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 26 - k * 5,
				Color(glow.r, glow.g, glow.b, (0.07 + 0.07 * k) * breath))
		_over.draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.02, 0.02, 0.04, 0.9))
		_over.draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Фигура: причина «нельзя» над участком при перетаскивании.
func _draw_figure_marks(centers: Dictionary, sizes: Dictionary) -> void:
	for lid: String in drag_blocked:
		if not centers.has(lid):
			continue
		var c2: Vector2 = centers[lid]
		var r2 := float(sizes.get(lid, 100.0)) * 0.46
		if lid == drag_hover:
			var f := UITheme.font("sans_bold")
			var t := str(drag_blocked[lid])
			var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			_over.draw_string_outline(f, c2 + Vector2(-w / 2.0, -r2 * 0.6 - 10.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 6, Color(0, 0, 0, 0.9))
			_over.draw_string(f, c2 + Vector2(-w / 2.0, -r2 * 0.6 - 10.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.55, 0.5))


func _ellipse_ring(c: Vector2, r: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		var ang := TAU * i / 48.0
		pts.append(c + Vector2(cos(ang) * r, sin(ang) * r * 0.6))
	_over.draw_polyline(pts, col, width, true)


func _ellipse_fill(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 48:
		var ang := TAU * i / 48.0
		pts.append(c + Vector2(cos(ang) * r, sin(ang) * r * 0.6))
	_over.draw_colored_polygon(pts, col)


## Участки при перетаскивании фигуры: картинке участка — шейдер света (sleeper_glow), остальным — без него.
func _apply_highlight() -> void:
	if _mats.is_empty():
		for key: String in ["silver", "gold", "block"]:
			var m := ShaderMaterial.new()
			m.shader = GLOW_SHADER
			m.set_shader_parameter("glow", {"silver": SILVER, "gold": GOLDEN, "block": Color(0.9, 0.25, 0.2)}[key])
			m.set_shader_parameter("amount", {"silver": 0.6, "gold": 1.0, "block": 0.35}[key])
			m.set_shader_parameter("dim", 0.45 if key == "block" else 0.0)
			_mats[key] = m
	for lid: String in _sprites:
		var tr: TextureRect = _sprites[lid]
		if not is_instance_valid(tr):
			continue
		var key2 := ""
		if drag_targets.has(lid):
			key2 = "gold" if lid == drag_hover else "silver"
		elif drag_blocked.has(lid):
			key2 = "block"
		tr.material = _mats[key2] if key2 != "" else null
	if _glow != null:
		_glow.queue_redraw()


## Свет вверх над участками, куда можно поставить фигуру: мягкое пятно, столбы света и поднимающиеся искры.
func _draw_glow() -> void:
	if drag_targets.is_empty() or _content == null:
		return
	for lid: String in drag_targets:
		if not _sprites.has(lid):
			continue
		var hot := lid == drag_hover
		var col := GOLDEN if hot else SILVER
		var k := 1.0 if hot else 0.55
		var c := center(_content, _state, lid) - view.position
		var sz := _sprite_size(_content, _state, lid)
		var ground := c + Vector2(0.0, sz * 0.12)
		# пятно света на земле
		for i in 6:
			var rr := sz * (0.42 - i * 0.06)
			var pts := PackedVector2Array()
			for j in 32:
				var a := TAU * j / 32.0
				pts.append(ground + Vector2(cos(a) * rr, sin(a) * rr * 0.5))
			_glow.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.05 * k))
		# общее сияние над участком: широкий мягкий столб
		var aw := sz * 0.36
		var ah := sz * (0.95 if hot else 0.75)
		var aa := 0.1 * k
		_glow.draw_polygon(PackedVector2Array([ground + Vector2(-aw, 0), ground + Vector2(aw, 0), ground + Vector2(aw * 0.55, -ah), ground + Vector2(-aw * 0.55, -ah)]),
			PackedColorArray([Color(col.r, col.g, col.b, aa), Color(col.r, col.g, col.b, aa), Color(col.r, col.g, col.b, 0.0), Color(col.r, col.g, col.b, 0.0)]))
		# тонкие лучи вверх: ядро и мягкий край
		for i in 12:
			var fx := (float(i) / 11.0 - 0.5) * sz * 0.6 + sin(i * 2.3) * sz * 0.025
			var w := sz * (0.012 + 0.012 * (0.5 + 0.5 * sin(i * 1.7)))
			var h := sz * (0.45 + 0.4 * (0.5 + 0.5 * sin(i * 3.1))) * (1.15 if hot else 1.0)
			var fl := 0.55 + 0.45 * sin(_t * (1.6 + i * 0.31) + i)
			var base := ground + Vector2(fx, -absf(fx) * 0.15)
			for layer in 2:
				var ww := w * (3.0 if layer == 0 else 1.0)
				var a0 := (0.08 if layer == 0 else 0.3) * k * fl
				_glow.draw_polygon(PackedVector2Array([base + Vector2(-ww, 0), base + Vector2(ww, 0), base + Vector2(ww * 0.2, -h), base + Vector2(-ww * 0.2, -h)]),
					PackedColorArray([Color(col.r, col.g, col.b, a0), Color(col.r, col.g, col.b, a0), Color(col.r, col.g, col.b, 0.0), Color(col.r, col.g, col.b, 0.0)]))
		# искры поднимаются
		for i in 14:
			var span := sz * 0.9
			var y := fmod(_t * (28.0 + i * 3.0) + i * 47.0, span)
			var x := sin(i * 1.9 + _t * 0.8) * sz * 0.3
			var p := ground + Vector2(x, -y)
			_glow.draw_circle(p, 2.2 + (i % 3) * 0.8, Color(col.r, col.g, col.b, (1.0 - y / span) * k))


## Участок под точкой окна (только открытые места и лавки; "" — нет).
func pick(content: Content, state: RunState, at: Vector2) -> String:
	var best := ""
	var bd := INF
	var kn := MapRules.known(content, state)
	for lid: String in cfg.get("places", {}):
		if not MapRules.present(content, state, lid) or not (kn.has(lid) or content.shops.has(lid)):
			continue
		var p := center(content, state, lid) + pan
		var r := MapRules.size_of(content, state, lid) * rect.size.x * 0.4
		var d := p.distance_to(at - global_position)
		if d < r and d < bd:
			bd = d
			best = lid
	return best


## Небо поверх окна (не сдвигается с картой): кровавая луна пульсирует, шторм — дождь и молнии.
func _draw_weather() -> void:
	var full := Rect2(Vector2.ZERO, view.size)
	if sky == "blood_moon":
		var beat := 0.5 + 0.5 * sin(_t * 1.6)
		_weather.draw_rect(full, Color(0.5, 0.04, 0.06, 0.06 + 0.05 * beat))
	elif sky == "storm" and not Vfx.reduced():
		for i in 90:
			var x := fmod(i * 97.3 + _t * 520.0, view.size.x + 200.0) - 100.0
			var y := fmod(i * 53.1 + _t * 900.0, view.size.y + 60.0) - 30.0
			_weather.draw_line(Vector2(x, y), Vector2(x - 7.0, y + 22.0), Color(0.75, 0.82, 0.92, 0.22), 1.2)
	if _flash > 0.0:
		_weather.draw_rect(full, Color(0.85, 0.9, 1.0, 0.22 * _flash))
	# Тревога (GateRules): красные отблески мигалок по краям
	if bool(_info.get("alarm", false)) and not Vfx.reduced():
		var beat := maxf(0.0, sin(_t * 5.0))
		var edge := 140.0
		for k in 6:
			var a := 0.05 * beat * (1.0 - k / 6.0)
			var e := edge * k / 6.0
			_weather.draw_rect(Rect2(e, e, full.size.x - 2.0 * e, full.size.y - 2.0 * e), Color(0.9, 0.05, 0.05, a), false, edge / 6.0)
