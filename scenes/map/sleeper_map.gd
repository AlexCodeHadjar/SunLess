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
const FOG_MASK_SHADER := preload("res://scenes/map/sleeper_fog_mask.gdshader")
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
var _fog_vp: SubViewport       # маска тумана: своя текстура в половину основы, пересчёт только при изменениях
var _fog_mask: ColorRect
var _fog_last: Array = []      # прошлые круги и коридоры: не изменились — маску не трогать
var _over: Control
var _labels: Control         # подписи мест — свой слой: перерисовка только при смене карты (sync), не каждый кадр
var _wander_layer: Control   # бродячие боссы (docs/22): фишки на местах, где стоят
var _wanderers := {}         # босс -> {token, at}
var _threat: Control
var _weather: Control
var _sprites := {}        # место -> TextureRect
var _shown := {}          # место -> облик на экране ("" — место скрыто)
var _tex := {}            # путь -> Texture2D
var _level := 55.0
var _level_to := 55.0
var _reveal := {}         # место -> 0..1 (проявление тушью)
var _fog_pairs: Array = []  # открытые соседи [a, b] — туман между ними рассеян (коридор)
var _fog_tris: Array = []   # тройки открытых соседей — туман из середины треугольника тоже уходит
var _info := {}           # что рисовать поверх: {revealed, flooded, warn, names}
var _t := 0.0
var _flash := 0.0
var _next_flash := 5.0
var _clouds: Array = []
var _rng := RandomNumberGenerator.new()
# фигура (docs/18): лагерь рисует не костёр-точка, а сцена у фигуры; при перетаскивании — подсветка участков
var label_style := "white":     # подписи мест: silver | white | ice | shadow | gold | caps | frost
	set(v):
		label_style = v
		if _labels != null:
			_labels.queue_redraw()
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
var quest_target := "":          # задание (docs/20): участок цели горит золотом, пока идёт показ
	set(v):
		if v != quest_target:
			quest_target = v
			_apply_highlight()
var _quest_path: Array = []      # путь от фигуры к цели (места по порядку)
var _quest_t := 0.0              # сколько ещё показывать
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
	_wander_layer = _layer(_world)
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
	_fog_vp = SubViewport.new()
	_fog_vp.disable_3d = true
	_fog_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_fog_vp)
	_fog_mask = ColorRect.new()
	var mm := ShaderMaterial.new()
	mm.shader = FOG_MASK_SHADER
	mm.set_shader_parameter("aspect", aspect)
	_fog_mask.material = mm
	_fog_vp.add_child(_fog_mask)
	fm.set_shader_parameter("mask", _fog_vp.get_texture())
	_fit()
	set_pan(Vector2((view.size.x - rect.size.x) / 2.0, -float(cfg.get("view_top", 0.08)) * rect.size.y))
	_over = _layer(_world)
	_over.draw.connect(_draw_over)
	_labels = _layer(_world)
	_labels.draw.connect(_draw_labels)
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
	if _fog_vp != null:
		_fog_vp.size = Vector2i(maxi(1, int(rect.size.x / 2.0)), maxi(1, int(rect.size.y / 2.0)))
		_fog_mask.size = Vector2(_fog_vp.size)
		_fog_last = []


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
	_fog_links(content, state, revealed, centers)
	_info = {"revealed": revealed, "flooded": flooded, "warn": warn, "feet": feet, "centers": centers,
		"sizes": sizes, "names": names, "paths": paths, "near": near,
		"camp": state.party_at if revealed.has(state.party_at) and not figure_mode else "",
		"figure": state.party_at if figure_mode else "",
		"threat": _threat_info(content, state, revealed), "alarm": GateRules.alarm(state), "water": water,
		"boat": bool(state.flags.get("boat", false)), "terrain": _terrain_info(content, state, revealed),
		"decals": _decal_info(content, state, revealed), "air": _air_info(content, state)}
	_ink.queue_redraw()
	_labels.queue_redraw()
	_sync_wanderers(content, state, revealed)


## Бродячие боссы: фишка на месте босса — левее и ниже середины (над серединой висит ромб события); ушёл — фишка
## идёт к новому месту; побеждён или ушёл из главы — гаснет.
func _sync_wanderers(content: Content, state: RunState, revealed: Array) -> void:
	var now := {}
	for w: Dictionary in WanderRules.active(content, state):
		if revealed.has(str(w["at"])):
			now[str(w["id"])] = str(w["at"])
	for wid: String in _wanderers.keys():
		if not now.has(wid):
			var old: Control = _wanderers[wid]["token"]
			_wanderers.erase(wid)
			if is_instance_valid(old):
				var tw := old.create_tween()
				tw.tween_property(old, "modulate:a", 0.0, 0.6)
				tw.tween_callback(old.queue_free)
	for wid2: String in now:
		var lid: String = now[wid2]
		var side := _sprite_size(content, state, lid) * 0.62
		var p := center(content, state, lid) - view.position + Vector2(-side * 1.15, -side * 0.5)   # левее ромба события
		if not _wanderers.has(wid2):
			var tk := WanderToken.make(wid2, side)
			tk.position = p
			tk.modulate.a = 0.0
			_wander_layer.add_child(tk)
			tk.create_tween().tween_property(tk, "modulate:a", 1.0, 0.8)
			_wanderers[wid2] = {"token": tk, "at": lid}
		elif str(_wanderers[wid2]["at"]) != lid:
			_wanderers[wid2]["at"] = lid
			(_wanderers[wid2]["token"] as WanderToken).walk_to(p)
		else:
			var t2: Control = _wanderers[wid2]["token"]
			t2.size = Vector2(side, side)
			if t2.get_tree() != null and not t2.has_meta("walking"):
				t2.position = p


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
		var lids := ZoneRules.places(content, state, zid)
		var at: Array = []
		for lid: String in lids:
			if revealed.has(lid):
				at.append({"at": center(content, state, lid) - view.position, "size": _sprite_size(content, state, lid),
					"center": lid == str(z.get("center", ""))})
		var spread: Array = []   # паутина по тропам внутри территории
		if str(z.get("spread", "")) != "":
			for pair: Array in MapRules.links(content, state):
				if lids.has(pair[0]) and lids.has(pair[1]) and revealed.has(pair[0]) and revealed.has(pair[1]):
					spread.append([center(content, state, str(pair[0])) - view.position, center(content, state, str(pair[1])) - view.position])
		if not at.is_empty():
			zones.append({"places": at, "color": Color(float(col[0]), float(col[1]), float(col[2])), "name": str(z.get("name", zid)).to_lower(),
				"decal": str(z.get("decal", "")), "mark": str(z.get("mark", "")), "spread_tex": str(z.get("spread", "")), "spread": spread})
	var movers: Array = []
	var stack := {}   # сколько угроз уже стоит в месте — следующую рисуем ниже
	var mc := MoverRules.cfg(content, state)
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
			"name": MoverRules.name_of(content, state, mid), "wounded": bool(m.get("wounded", false)), "slot": int(stack.get(lid, 0)),
			"token": str(mc.get(mid, {}).get("token", "")), "tracks": str(mc.get(mid, {}).get("tracks", ""))})
		stack[lid] = int(stack.get(lid, 0)) + 1
	# логова великих охотников: живо логово, пока охотник жив
	var nests: Array = []
	for mid2: String in mc:
		var d: Dictionary = mc[mid2]
		if not d.has("nest") or not revealed.has(str(d.get("start", ""))):
			continue
		var na: Array = d["nest"]
		var alive := MoverRules.active(state, mid2) or not MoverRules.movers(state).has(mid2)
		nests.append({"at": to_screen(Vector2(float(na[0]), float(na[1]))) - view.position,
			"tex": str(d.get("nest_tex", ["", ""])[0 if alive else 1])})
	var rubble: Array = []
	var rb: Dictionary = cfg.get("rubble", {})
	var rtex: Dictionary = cfg.get("rubble_tex", {})
	var st: Dictionary = state.flags.get("rubble", {})
	for rid: String in rb:
		var pr: Array = rb[rid].get("pair", [])
		var rs := str(st.get(rid, ""))
		if rs != "" and pr.size() == 2 and revealed.has(pr[0]) and revealed.has(pr[1]):
			var at2: Array = rb[rid].get("at", [0.5, 0.5])
			rubble.append({"at": to_screen(Vector2(float(at2[0]), float(at2[1]))) - view.position, "state": rs, "tex": str(rtex.get(rs, ""))})
	if zones.is_empty() and movers.is_empty() and rubble.is_empty() and nests.is_empty():
		return {}
	return {"zones": zones, "movers": movers, "rubble": rubble, "nests": nests}


## Туман между открытыми местами (просьба владельца 03.10): соседи по тропе или места рядом (зазор меньше полутора
## кругов) — коридор без тумана; три открытых соседа — и середина треугольника открыта. Открытое сливается в одну область.
func _fog_links(content: Content, state: RunState, revealed: Array, centers: Dictionary) -> void:
	var pairs := {}
	for pr: Array in MapRules.links(content, state):
		if revealed.has(pr[0]) and revealed.has(pr[1]):
			pairs[_pair_key(str(pr[0]), str(pr[1]))] = [str(pr[0]), str(pr[1])]
	var uv := {}
	for lid: String in revealed:
		uv[lid] = ((centers[lid] as Vector2) + view.position - rect.position) / rect.size
	for i in revealed.size():
		for j in range(i + 1, revealed.size()):
			var a: String = revealed[i]
			var b: String = revealed[j]
			var pa: Vector2 = uv[a]
			var pb: Vector2 = uv[b]
			if Vector2((pa.x - pb.x) * _aspect, pa.y - pb.y).length() < REVEAL_R * 3.0:
				pairs[_pair_key(a, b)] = [a, b]
	_fog_pairs = pairs.values()
	var nb := {}
	for pr2: Array in _fog_pairs:
		for k in 2:
			if not nb.has(pr2[k]):
				nb[pr2[k]] = []
			(nb[pr2[k]] as Array).append(pr2[1 - k])
	var tris: Array = []
	for pr3: Array in _fog_pairs:
		var x: String = pr3[0] if str(pr3[0]) < str(pr3[1]) else pr3[1]
		var y: String = pr3[1] if str(pr3[0]) < str(pr3[1]) else pr3[0]
		for z: String in nb.get(x, []):
			if z > y and (nb.get(y, []) as Array).has(z):
				tris.append([x, y, z])
	_fog_tris = tris


static func _pair_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


## Атмосфера карты: дымка (Кровавая луна на Берегу), отсвет Шпиля с северо-запада, полосы пепельной бури.
func _air_info(content: Content, state: RunState) -> Dictionary:
	var out := {}
	for key: String in ["haze", "edge_glow", "storm_band"]:
		var d: Dictionary = cfg.get(key, {})
		if not d.is_empty() and MapEventRules._when(content, state, d):
			out[key] = str(d.get("tex", d.get("decal", "")))
	return out


## Следы событий (MapEventRules): метки у открытых мест, полосы на тропах; «дым вдалеке» виден и сквозь туман.
func _decal_info(content: Content, state: RunState, revealed: Array) -> Array:
	var out: Array = []
	var slots := {}
	for d: Dictionary in MapEventRules.decals(content, state):
		var tex := str(d["decal"])
		if d.has("path"):
			var pr: Array = d["path"]
			if revealed.has(pr[0]) and revealed.has(pr[1]):
				out.append({"tex": tex, "a": center(content, state, str(pr[0])) - view.position, "b": center(content, state, str(pr[1])) - view.position})
			continue
		var lid := str(d.get("place", ""))
		if not revealed.has(lid) and not bool(d.get("fog", false)):
			continue
		out.append({"tex": tex, "at": center(content, state, lid) - view.position, "size": _sprite_size(content, state, lid),
			"slot": int(slots.get(lid, 0))})
		slots[lid] = int(slots.get(lid, 0)) + 1
	return out


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
	var uv := {}
	for lid: String in revealed:
		_reveal[lid] = minf(1.0, float(_reveal.get(lid, 1.0)) + delta / 1.8)
		var a := ((_info["centers"][lid] as Vector2) - rect.position) / rect.size
		uv[lid] = a
		if holes.size() < 40:
			holes.append(Vector4(a.x, a.y, REVEAL_R, ease(float(_reveal[lid]), 0.5)))
	# середины треугольников из открытых соседей — туда тоже свет
	for tri: Array in _fog_tris:
		if holes.size() >= 48 or not (uv.has(tri[0]) and uv.has(tri[1]) and uv.has(tri[2])):
			continue
		var c: Vector2 = (uv[tri[0]] + uv[tri[1]] + uv[tri[2]]) / 3.0
		var rr := 0.0
		var rv := 1.0
		for v: String in tri:
			var pv: Vector2 = uv[v]
			rr = maxf(rr, Vector2((pv.x - c.x) * _aspect, pv.y - c.y).length())
			rv = minf(rv, float(_reveal.get(v, 1.0)))
		holes.append(Vector4(c.x, c.y, minf(rr * 0.85, REVEAL_R * 2.5), ease(rv, 0.5)))
	# коридоры между открытыми соседями
	var segs := PackedVector4Array()
	var sw := PackedVector2Array()
	for pr: Array in _fog_pairs:
		if segs.size() >= 64 or not (uv.has(pr[0]) and uv.has(pr[1])):
			continue
		var p0: Vector2 = uv[pr[0]]
		var p1: Vector2 = uv[pr[1]]
		segs.append(Vector4(p0.x, p0.y, p1.x, p1.y))
		sw.append(Vector2(REVEAL_R * 0.75, ease(minf(float(_reveal.get(pr[0], 1.0)), float(_reveal.get(pr[1], 1.0))), 0.5)))
	# маска пересчитывается только когда открытое изменилось (проявление, новые места) — не каждый кадр
	if _fog_last.size() != 3 or _fog_last[0] != holes or _fog_last[1] != segs or _fog_last[2] != sw:
		_fog_last = [holes, segs, sw]
		var fm := _fog_mask.material as ShaderMaterial
		fm.set_shader_parameter("holes", holes)
		fm.set_shader_parameter("hole_count", holes.size())
		fm.set_shader_parameter("segs", segs)
		fm.set_shader_parameter("seg_w", sw)
		fm.set_shader_parameter("seg_count", segs.size())
		_fog_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
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
	if label_style == "silver":   # серебро «дышит» — живая подпись; остальные стили неподвижны
		_labels.queue_redraw()
	if _quest_t > 0.0:
		_quest_t -= delta
		if _quest_t <= 0.0:
			_quest_path = []
			quest_target = ""
	if not drag_targets.is_empty() or not drag_blocked.is_empty() or quest_target != "":
		_glow.queue_redraw()
	_weather.queue_redraw()
	if not Dictionary(_info.get("threat", {})).is_empty() or not Dictionary(_info.get("terrain", {})).is_empty() \
			or not (_info.get("decals", []) as Array).is_empty():
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
	_draw_decals()
	var tr: Dictionary = _info.get("terrain", {})
	if tr.is_empty():
		return
	var pulse := 0.5 + 0.5 * sin(_t * 2.2)
	var f := UITheme.font("sans_bold")
	for z: Dictionary in tr.get("zones", []):
		var col: Color = z["color"]
		var zt := _load(str(z.get("decal", "")))
		var st := _load(str(z.get("spread_tex", "")))
		for sp: Array in z.get("spread", []):
			if st != null:
				_strip(st, Vector2(sp[0]), Vector2(sp[1]), Color(1, 1, 1, 0.9))
		for p: Dictionary in z["places"]:
			var c := Vector2(p["at"])
			var r := float(p["size"]) * 0.5
			if zt != null:   # свечение зоны картинкой: кольцо гнева, сияние Очарования
				var zs := float(p["size"]) * (1.1 + 0.04 * pulse)
				_threat.draw_texture_rect(zt, Rect2(c - Vector2(zs, zs * 0.62) / 2.0, Vector2(zs, zs * 0.62)), false, Color(1, 1, 1, 0.7 + 0.25 * pulse))
			elif str(z.get("mark", "")) != "":   # территория хозяина: тонкая граница, остальное скажет метка
				_threat.draw_arc(c, r * 0.95, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.22 + 0.1 * pulse), 1.5, true)
			else:
				for k in 5:
					var rr := r * (1.0 - k * 0.16) * (1.0 + 0.04 * pulse)
					_threat.draw_circle(c, rr, Color(col.r, col.g, col.b, 0.05 + 0.02 * pulse))
				_threat.draw_arc(c, r * (1.0 + 0.04 * pulse), 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.35 + 0.2 * pulse), 2.0, true)
			var mt := _load(str(z.get("mark", "")))
			if mt != null:   # метка хозяина района: голова статуи, паутина, кости, цветы
				var ms := float(p["size"]) * (0.34 if bool(p["center"]) else 0.22)
				_threat.draw_texture_rect(mt, Rect2(c + Vector2(-float(p["size"]) * 0.3, float(p["size"]) * 0.02) - Vector2(ms, ms) / 2.0, Vector2(ms, ms)), false)
			if bool(p["center"]):
				var t := str(z["name"])
				var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
				var at := c + Vector2(-w / 2.0, -r - 6.0)
				_threat.draw_string_outline(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color(0, 0, 0, 0.9))
				_threat.draw_string(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col.lightened(0.3))
	for n: Dictionary in tr.get("nests", []):
		var nt := _load(str(n["tex"]))
		if nt != null:
			var ns := rect.size.x * 0.075
			_threat.draw_texture_rect(nt, Rect2(Vector2(n["at"]) - Vector2(ns, ns) / 2.0, Vector2(ns, ns)), false)
	for rb: Dictionary in tr.get("rubble", []):
		var rp := Vector2(rb["at"])
		var rt := _load(str(rb.get("tex", "")))
		if rt != null:   # завал — куча обломков; пробитый — лаз в обломках
			var rs := rect.size.x * 0.065
			_threat.draw_texture_rect(rt, Rect2(rp - Vector2(rs, rs) / 2.0, Vector2(rs, rs)), false)
		elif str(rb["state"]) == "blocked":
			for k in 5:
				var off := Vector2(cos(k * 2.1) * 11.0, sin(k * 1.7) * 6.0)
				_threat.draw_circle(rp + off, 9.0 - k, Color(0.25, 0.23, 0.22, 0.95))
			_threat.draw_line(rp + Vector2(-14, -14), rp + Vector2(14, 14), Color(1.0, 0.35, 0.25, 0.9), 3.0, true)
			_threat.draw_line(rp + Vector2(-14, 14), rp + Vector2(14, -14), Color(1.0, 0.35, 0.25, 0.9), 3.0, true)
	for m: Dictionary in tr.get("movers", []):
		var at2 := Vector2(m["at"])
		var fr := Vector2(m["from"])
		var col2 := Color(1.0, 0.6, 0.2) if bool(m["wounded"]) else Color(0.95, 0.15, 0.12)
		var trk := _load(str(m.get("tracks", "")))
		# след от прошлого места: картинкой следов или пунктиром
		if fr != Vector2.INF and at2 != Vector2.INF:
			if trk != null:
				_strip(trk, fr, at2, Color(1, 1, 1, 0.9))
			else:
				for i in 12:
					if i % 2 == 0:
						_threat.draw_line(fr.lerp(at2, i / 12.0), fr.lerp(at2, (i + 1) / 12.0), Color(col2.r, col2.g, col2.b, 0.55), 4.0, true)
		elif fr != Vector2.INF:
			_threat.draw_circle(fr, 10.0, Color(col2.r, col2.g, col2.b, 0.35))   # место не видно — только следы
		if at2 == Vector2.INF:
			continue
		var c2 := at2 + Vector2(float(m["size"]) * 0.3, -float(m["size"]) * 0.22 + 60.0 * int(m.get("slot", 0)))
		var tok := _load(str(m.get("token", "")))
		var r2 := 15.0 + 2.0 * pulse
		if tok != null:   # фишка угрозы картинкой: Демон, охотник, статуя, тень под водой
			var ts := maxf(64.0, float(m["size"]) * 0.3)
			_threat.draw_circle(c2 + Vector2(0, ts * 0.3), ts * 0.42, Color(col2.r, col2.g, col2.b, 0.12 + 0.12 * pulse))
			_threat.draw_texture_rect(tok, Rect2(c2 - Vector2(ts, ts) / 2.0, Vector2(ts, ts)), false,
				Color(1.0, 0.75, 0.65) if bool(m["wounded"]) else Color.WHITE)
			r2 = ts * 0.42
		else:
			_threat.draw_circle(c2, r2 + 6.0, Color(col2.r, col2.g, col2.b, 0.18 + 0.15 * pulse))
			_threat.draw_circle(c2, r2, Color(0.04, 0.02, 0.03, 0.92))
			_threat.draw_arc(c2, r2, 0.0, TAU, 32, col2, 3.0, true)
			_threat.draw_circle(c2 + Vector2(-5, -2), 2.6, col2)
			_threat.draw_circle(c2 + Vector2(5, -2), 2.6, col2)
		var t2 := str(m["name"]) + (" (ранен)" if bool(m["wounded"]) else "")
		var w2 := f.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_threat.draw_string_outline(f, c2 + Vector2(-w2 / 2.0, r2 + 16.0), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color(0, 0, 0, 0.9))
		_threat.draw_string(f, c2 + Vector2(-w2 / 2.0, r2 + 16.0), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col2.lightened(0.35))


## Полоса-картинка вдоль тропы между точками (без краёв у самих мест).
func _strip(tex: Texture2D, a: Vector2, b: Vector2, col: Color) -> void:
	var ln := a.distance_to(b) * 0.62
	_threat.draw_set_transform((a + b) / 2.0, (b - a).angle(), Vector2.ONE)
	_threat.draw_texture_rect(tex, Rect2(-ln / 2.0, -ln * 0.125, ln, ln * 0.25), false, col)
	_threat.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Метки событий у мест (по кругу вокруг места, чтобы не легли друг на друга) и полосы на тропах.
func _draw_decals() -> void:
	var offs := [Vector2(0.24, -0.2), Vector2(-0.27, 0.16), Vector2(0.2, 0.22), Vector2(-0.22, -0.22), Vector2(0.0, 0.3)]
	for d: Dictionary in _info.get("decals", []):
		var tex := _load(str(d["tex"]))
		if tex == null:
			continue
		if d.has("a"):
			_strip(tex, Vector2(d["a"]), Vector2(d["b"]), Color.WHITE)
			continue
		var c := Vector2(d["at"])
		var sz := float(d["size"])
		if tex.get_width() >= 3 * tex.get_height():   # полоса у места: туман, след — поперёк верха места (подпись внизу видна)
			var w := sz * 0.7
			_threat.draw_texture_rect(tex, Rect2(c + Vector2(-w / 2.0, -sz * 0.22), Vector2(w, w * 0.25)), false, Color(1, 1, 1, 0.8))
			continue
		var o: Vector2 = offs[int(d.get("slot", 0)) % offs.size()]
		var ds := sz * 0.3
		_threat.draw_texture_rect(tex, Rect2(c + o * sz - Vector2(ds, ds) / 2.0, Vector2(ds, ds)), false)


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
	_draw_quest_path(centers)
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


## Задание (docs/20): показать цель — участок горит золотом, от фигуры к нему бежит золотой пунктир. path — места
## от лагеря до цели по порядку; sec — сколько показывать.
func show_quest(path: Array, target: String, sec: float = 4.5) -> void:
	_quest_path = path
	_quest_t = sec
	quest_target = target
	_glow.queue_redraw()


func _draw_quest_path(centers: Dictionary) -> void:
	if _quest_path.size() < 2 or _quest_t <= 0.0:
		return
	var fade := clampf(_quest_t / 0.8, 0.0, 1.0)
	var phase := fmod(_t * 60.0, 28.0)
	for i in _quest_path.size() - 1:
		if not centers.has(_quest_path[i]) or not centers.has(_quest_path[i + 1]):
			continue
		var a: Vector2 = centers[_quest_path[i]]
		var b: Vector2 = centers[_quest_path[i + 1]]
		var len := a.distance_to(b)
		var dir := (b - a) / maxf(len, 1.0)
		var d := -phase
		while d < len:
			var p0 := a + dir * maxf(d, 0.0)
			var p1 := a + dir * minf(d + 14.0, len)
			if d + 14.0 > 0.0:
				_over.draw_line(p0, p1, Color(0, 0, 0, 0.5 * fade), 7.0, true)
				_over.draw_line(p0, p1, Color(GOLDEN, 0.95 * fade), 3.5, true)
			d += 28.0
	var tc: Vector2 = centers.get(_quest_path[-1], Vector2.ZERO)
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	_over.draw_arc(tc, 40.0 + 10.0 * pulse, 0.0, TAU, 48, Color(GOLDEN, 0.8 * fade), 3.0, true)


## Подписи открытых мест: стиль — label_style (варианты для выбора владельцем, docs/коллажи карт/5 …).
func _draw_labels() -> void:
	var feet: Dictionary = _info.get("feet", {})
	var names: Dictionary = _info.get("names", {})
	var flooded: Array = _info.get("flooded", [])
	for lid: String in feet:
		_draw_label(Vector2(feet[lid]) + Vector2(0.0, 24.0), str(names[lid]), flooded.has(lid))


## Подпись места по стилю label_style. at — середина подписи по ширине, высота — базовая линия.
## Только текст, без плашек (решение владельца): silver — серебро с ореолом; white — ярко-белый, плотная чёрная обводка,
## рубленый шрифт; ice — бело-голубой рубленый, тёмно-синяя обводка с голубой кромкой; shadow — белый с тенью и тонкой
## обводкой; gold — тёплое светлое золото; caps — белая капитель с чёрной обводкой; frost — белый книжный с чёрной
## обводкой и лёгким холодным ореолом.
func _draw_label(at: Vector2, text: String, wet: bool) -> void:
	var style := label_style
	var font_key: String = {"white": "sans_bold", "ice": "sans_bold", "shadow": "sans_bold", "caps": "caps"}.get(style, "title")
	var f := UITheme.font(font_key)
	var fs: int = {"white": 19, "ice": 19, "shadow": 19, "caps": 20, "gold": 22, "frost": 22}.get(style, 21)
	var shown := text
	var tw := f.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := at + Vector2(-tw / 2.0, 0.0)
	var white := Color(0.78, 0.9, 1.0) if wet else Color(1.0, 1.0, 1.0)
	match style:
		"white":
			_labels.draw_string_outline(f, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(0, 0, 0, 0.95))
			_labels.draw_string(f, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, white)
		"ice":
			var ice := Color(0.86, 0.94, 1.0)
			_labels.draw_string_outline(f, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0.02, 0.04, 0.1, 0.95))
			_labels.draw_string_outline(f, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 2, Color(0.55, 0.75, 1.0, 0.9))
			_labels.draw_string(f, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ice)
		"shadow":
			_labels.draw_string(f, p + Vector2(2, 2), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.9))
			_labels.draw_string_outline(f, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.85))
			_labels.draw_string(f, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, white)
		"gold":
			var gold := Color(0.75, 0.88, 1.0) if wet else Color(1.0, 0.9, 0.62)
			for k in 3:
				_labels.draw_string_outline(f, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 16 - k * 4, Color(gold.r, gold.g, gold.b, 0.08 + 0.06 * k))
			_labels.draw_string_outline(f, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.05, 0.03, 0.0, 0.95))
			_labels.draw_string(f, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, gold)
		"caps":
			_labels.draw_string_outline(f, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(0, 0, 0, 0.95))
			_labels.draw_string(f, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, white)
		"frost":
			for k in 3:
				_labels.draw_string_outline(f, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 18 - k * 4, Color(0.7, 0.85, 1.0, 0.06 + 0.04 * k))
			_labels.draw_string_outline(f, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(0, 0, 0, 0.95))
			_labels.draw_string(f, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, white)
		_:   # silver — серебро с ореолом
			var breath := 0.85 + 0.15 * sin(_t * 1.4)
			var glow := Color(0.55, 0.78, 1.0) if wet else Color(0.82, 0.86, 0.95)
			var col := Color(0.72, 0.88, 1.0) if wet else Color(0.93, 0.95, 1.0)
			for k in 5:
				_labels.draw_string_outline(f, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 26 - k * 5, Color(glow.r, glow.g, glow.b, (0.07 + 0.07 * k) * breath))
			_labels.draw_string_outline(f, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.02, 0.02, 0.04, 0.9))
			_labels.draw_string(f, p, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


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
		elif lid == quest_target:
			key2 = "gold"
		tr.material = _mats[key2] if key2 != "" else null
	if _glow != null:
		_glow.queue_redraw()


## Свет вверх над участками, куда можно поставить фигуру: мягкое пятно, столбы света и поднимающиеся искры.
func _draw_glow() -> void:
	if (drag_targets.is_empty() and quest_target == "") or _content == null:
		return
	var lit: Array = drag_targets.duplicate()
	if quest_target != "" and not lit.has(quest_target):
		lit.append(quest_target)
	for lid: String in lit:
		if not _sprites.has(lid):
			continue
		var hot := lid == drag_hover or lid == quest_target
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
	var air: Dictionary = _info.get("air", {})
	var haze := _load(str(air.get("haze", "")))
	if haze != null:   # багровая дымка в Кровавую луну — медленно плывёт
		var hs := view.size.x * 0.5
		var ox := fmod(_t * 6.0, hs)
		for ix in range(-1, int(view.size.x / hs) + 2):
			for iy in range(0, int(view.size.y / hs) + 2):
				_weather.draw_texture_rect(haze, Rect2(Vector2(ix * hs + ox, iy * hs - fmod(_t * 2.0, hs)), Vector2(hs, hs)), false, Color(1, 1, 1, 0.1))
	var glow := _load(str(air.get("edge_glow", "")))
	if glow != null:   # отсвет Шпиля с северо-запада
		var gs := view.size.x * 0.5
		_weather.draw_texture_rect(glow, Rect2(Vector2.ZERO, Vector2(gs, gs)), false, Color(1, 1, 1, 0.65 + 0.15 * sin(_t * 0.8)))
	var band := _load(str(air.get("storm_band", "")))
	if band != null:   # пепельная буря: полосы пепла несёт по карте
		for k in 3:
			var bw := view.size.x * 0.5
			var bx := fmod(_t * (55.0 + k * 17.0) + k * 611.0, view.size.x + bw) - bw
			var by := view.size.y * (0.18 + 0.27 * k)
			_weather.draw_texture_rect(band, Rect2(Vector2(bx, by), Vector2(bw, bw * 0.22)), false, Color(1, 1, 1, 0.32))
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
