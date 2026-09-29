class_name SleeperMap
extends Control
## «Карта Спящего» (docs/16 §11.6) — карта главы планом сверху. Только отрисовка: что где и в каком облике,
## решают MapRules и TideRules. Слои снизу вверх:
##   основа → вода прилива (шейдер по карте высот) → тропы между открытыми местами → виньетки мест
##   (облик — MapRules.place_state, смена — наплывом) → тени облаков → туман неизвестного (шейдер)
##   → кольца «вода идёт», подписи мест, дождь и молнии.
## Небо не рисуется: день, ночь, кровавая луна, шторм и затмение — цветом всей карты и эффектами.

const WATER_SHADER := preload("res://scenes/map/sleeper_water.gdshader")
const FOG_SHADER := preload("res://scenes/map/sleeper_fog.gdshader")
const FADE := 0.9
const REVEAL_R := 0.17           # радиус открытого круга — доля высоты основы
const LEVEL_SPEED := 18.0        # сколько единиц высоты вода проходит за секунду
const SKY_TINT := {"night": Color(0.8, 0.84, 0.97), "day": Color(1.05, 1.03, 0.99), "eclipse": Color(0.5, 0.5, 0.64),
	"blood_moon": Color(1.06, 0.62, 0.6), "storm": Color(0.62, 0.68, 0.8)}

var cfg: Dictionary = {}
var view := Rect2(0, 72, 1920, 708)     # область экрана под карту
var rect := Rect2()                      # где лежит основа (в координатах _clip)
var sky := ""

var _clip: Control
var _world: Control
var _water: ColorRect
var _ink: Control
var _sprites_layer: Control
var _shade: Control
var _fog: ColorRect
var _over: Control
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
	rect.size = Vector2(view.size.x, view.size.x / aspect)
	rect.position = Vector2(0.0, -float(cfg.get("view_top", 0.08)) * rect.size.y)
	_world = _layer(_clip)
	var bg := TextureRect.new()
	bg.texture = base
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.position = rect.position
	bg.size = rect.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(bg)
	_water = ColorRect.new()
	_water.position = rect.position
	_water.size = rect.size
	_water.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_world.add_child(_water)
	_ink = _layer(_world)
	_ink.draw.connect(_draw_paths)
	_sprites_layer = _layer(_world)
	_shade = _layer(_world)
	_shade.draw.connect(_draw_shade)
	_fog = ColorRect.new()
	_fog.position = rect.position
	_fog.size = rect.size
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	fm.shader = FOG_SHADER
	fm.set_shader_parameter("fog_tex", _load(str(cfg.get("fog", "fog_tile.webp")).get_basename()))
	fm.set_shader_parameter("aspect", aspect)
	_fog.material = fm
	_world.add_child(_fog)
	_over = _layer(_clip)
	_over.draw.connect(_draw_over)
	var names := ["clouds/cloud_01", "clouds/cloud_02", "clouds/cloud_03", "clouds/cloud_04"]
	for i in 5:
		_clouds.append({"tex": Vfx.tex(names[i % names.size()]), "pos": Vector2(_rng.randf() * view.size.x, _rng.randf() * view.size.y),
			"scale": _rng.randf_range(1.4, 2.4), "speed": _rng.randf_range(5.0, 11.0)})


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

## Точка основы (доли) → экран.
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
	if sky_now != sky:
		_set_sky(sky_now, sky != "")
	var revealed: Array = []
	var flooded: Array = []
	var warn: Array = []
	for lid: String in cfg.get("places", {}):
		var here := MapRules.present(content, state, lid)
		var st := MapRules.place_state(content, state, lid, sky_now) if here else ""
		if str(_shown.get(lid, "-")) != st:
			_show_place(content, state, lid, st)
		if not here:
			_reveal.erase(lid)
			continue
		if MapRules.revealed(content, state, lid):
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
	for pair: Array in cfg.get("paths", []):
		if revealed.has(pair[0]) and revealed.has(pair[1]):
			paths.append(pair)
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
	_info = {"revealed": revealed, "flooded": flooded, "warn": warn, "feet": feet, "centers": centers,
		"sizes": sizes, "names": names, "paths": paths}
	_ink.queue_redraw()


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
	if not is_equal_approx(_level, _level_to):
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
			if cl["pos"].x > view.size.x + 400.0:
				cl["pos"] = Vector2(-500.0, _rng.randf() * view.size.y)
		if sky == "storm":
			_next_flash -= delta
			if _next_flash <= 0.0:
				_flash = 1.0
				_next_flash = _rng.randf_range(4.0, 11.0)
		_flash = maxf(0.0, _flash - delta * 2.6)
	_shade.queue_redraw()
	_over.queue_redraw()


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
	# подписи открытых мест
	var f := UITheme.font("title")
	var feet: Dictionary = _info.get("feet", {})
	var names: Dictionary = _info.get("names", {})
	for lid: String in feet:
		var fp: Vector2 = feet[lid]
		var text: String = names[lid]
		var fs := 17
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := fp + Vector2(-tw / 2.0, 22.0)
		var col := Color(0.6, 0.8, 1.0) if _info["flooded"].has(lid) else Palette.SILVER
		_over.draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.85))
		_over.draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	# небо: кровавая луна пульсирует по краям, шторм — дождь и молнии
	var full := Rect2(Vector2.ZERO, view.size)
	if sky == "blood_moon":
		var beat := 0.5 + 0.5 * sin(_t * 1.6)
		_over.draw_rect(full, Color(0.5, 0.04, 0.06, 0.06 + 0.05 * beat))
	elif sky == "storm" and not Vfx.reduced():
		for i in 90:
			var x := fmod(i * 97.3 + _t * 520.0, view.size.x + 200.0) - 100.0
			var y := fmod(i * 53.1 + _t * 900.0, view.size.y + 60.0) - 30.0
			_over.draw_line(Vector2(x, y), Vector2(x - 7.0, y + 22.0), Color(0.75, 0.82, 0.92, 0.22), 1.2)
	if _flash > 0.0:
		_over.draw_rect(full, Color(0.85, 0.9, 1.0, 0.22 * _flash))
