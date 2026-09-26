class_name MapBackdrop
extends Control
## Фон региона. Если есть рисунки неба art/regions/<регион>_<небо>.webp (ночь, день, затмение, кровавая луна) —
## показывает их и плавно перетекает между ними (set_sky), с медленным «дыханием» кадра и живыми накладками:
## ореол луны, кровавый пульс, корона затмения, снег в цвет неба. Иначе рисует гравюрный перевал или город.
## Время суток tod: 0 ночь, 0.25 рассвет, 0.5 день, 0.75 сумерки — для процедурного фона.

const TOD_NAMES := ["ночь", "рассвет", "день", "сумерки"]
# ключевые цвета неба и оттенок гор для [ночь, рассвет, день, сумерки]
const SKY_TOP := [Color("#07080C"), Color("#1C1B2E"), Color("#4E5A70"), Color("#150E1C")]
const SKY_BOT := [Color("#4A5264"), Color("#B8826E"), Color("#AEB6C2"), Color("#9A5540")]
const LAND_TINT := [Color(1, 1, 1), Color(1.22, 1.08, 1.08), Color(1.5, 1.5, 1.55), Color(1.18, 0.98, 0.95)]
const SKIES := ["night", "day", "eclipse", "blood_moon"]
# где на рисунке луна (солнце) — доли кадра; одинаковая композиция у всех четырёх
const MOON_AT := Vector2(0.227, 0.105)
const SNOW_COLORS := {"night": Color(0.85, 0.87, 0.92, 0.35), "day": Color(0.97, 0.98, 1.0, 0.55),
	"eclipse": Color(0.7, 0.72, 0.8, 0.3), "blood_moon": Color(1.0, 0.72, 0.72, 0.38)}
const FADE_SEC := 4.0

var region := "mountain_pass"
var snow := true
var tod := 0.0
var _stars: Array = []      # [Vector3(x, y, фаза)]
var _windows: Array = []    # (устар.) окна теперь хранятся в слоях: L["windows"]
var _t := 0.0
var _tex: Texture2D
var _layers: Array = []     # [{poly: PackedVector2Array, color: Color}]
var _flakes: Array = []     # [Vector3(x, y, speed)]
var _built_for := Vector2.ZERO
var _sky_tex := {}           # небо -> Texture2D (рисунки региона)
var sky := ""                # текущее небо (куда перетекаем)
var _sky_from := ""
var _mix := 1.0              # 0 — ещё прежнее небо, 1 — уже новое


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_region_art()
	resized.connect(_rebuild)
	_rebuild()
	set_process(not SettingsService.get_value("reduce_motion"))


## Время суток по номеру недели: 1 — ночь, 2 — рассвет, 3 — день, 4 — сумерки, 5 — снова ночь.
## Академия: силуэт стерильного города — ярусы корпусов, мачты прожекторов, башня в центре.
func _build_city() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var colors: Array[Color] = [Color("#3A4352"), Color("#2A313D"), Color("#1C212A"), Color("#12151C")]
	var bases: Array[float] = [0.50, 0.62, 0.76, 0.90]
	var tall: Array[float] = [0.20, 0.16, 0.12, 0.08]
	for li in 4:
		var poly := PackedVector2Array([Vector2(0, size.y)])
		var wins: Array = []
		var x := 0.0
		while x < size.x:
			var w := rng.randf_range(50, 160) * (1.0 - li * 0.12)
			var h := size.y * (bases[li] - rng.randf_range(0.02, tall[li]))
			if li == 1 and absf(x - size.x * 0.55) < 90:
				h = size.y * 0.18   # центральная башня Академии
			poly.append(Vector2(x, h))
			poly.append(Vector2(x + w, h))
			if li < 3:
				for wy in range(int(h) + 14, int(size.y * bases[li]), 22):
					for wx in range(int(x) + 10, int(x + w) - 10, 26):
						if rng.randf() < 0.28:
							wins.append(Vector3(wx, wy, rng.randf() * TAU))
			x += w
		poly.append(Vector2(size.x, size.y))
		_layers.append({"poly": poly, "color": colors[li], "snow": false, "depth": li, "windows": wins})
	# мачты прожекторов
	for i in 6:
		var mx := size.x * (0.1 + i * 0.16)
		_layers.append({"poly": PackedVector2Array([Vector2(mx - 3, size.y * 0.66), Vector2(mx - 1, size.y * 0.30), Vector2(mx + 1, size.y * 0.30), Vector2(mx + 3, size.y * 0.66)]),
			"color": Color("#232A34"), "snow": false, "depth": 4})
	_flakes.clear()
	_stars.clear()
	for i in 150:
		_stars.append(Vector3(rng.randf() * size.x, rng.randf() * size.y * 0.4, rng.randf() * TAU))
	queue_redraw()


static func tod_for_week(week: int) -> float:
	return float((maxi(week, 1) - 1) % 4) * 0.25


static func tod_name(week: int) -> String:
	return TOD_NAMES[(maxi(week, 1) - 1) % 4]


## Веса фаз [ночь, рассвет, день, сумерки]: соседние фазы плавно перетекают.
static func phase_weights(t: float) -> Array:
	var w := [0.0, 0.0, 0.0, 0.0]
	var x := fposmod(t, 1.0) * 4.0
	var i := int(floorf(x)) % 4
	var f := x - floorf(x)
	w[i] = 1.0 - f
	w[(i + 1) % 4] += f
	return w


func set_tod(v: float, animate: bool) -> void:
	if not animate or SettingsService.get_value("reduce_motion"):
		tod = fposmod(v, 1.0)
		queue_redraw()
		return
	var target := v if v >= tod else v + 1.0
	var tw := create_tween()
	tw.tween_method(_set_tod, tod, target, 3.0).set_trans(Tween.TRANS_SINE)


func _set_tod(v: float) -> void:
	tod = fposmod(v, 1.0)
	queue_redraw()


func _blend(keys: Array, w: Array) -> Color:
	var c := Color(0, 0, 0, 0)
	for i in 4:
		c += (keys[i] as Color) * float(w[i])
	return c


## Смена региона (новая глава): другой силуэт, без снега вне гор.
func set_region(r: String) -> void:
	region = r
	snow = r == "mountain_pass"
	_load_region_art()
	_built_for = Vector2.ZERO
	_rebuild()


func _load_region_art() -> void:
	_tex = null
	_sky_tex.clear()
	var p := "res://art/regions/%s.png" % region
	if ResourceLoader.exists(p):
		_tex = load(p)
	for sk: String in SKIES:
		var sp := "res://art/regions/%s_%s.webp" % [region, sk]
		if ResourceLoader.exists(sp):
			_sky_tex[sk] = load(sp)
	if not _sky_tex.is_empty() and not _sky_tex.has(sky):
		sky = "night" if _sky_tex.has("night") else _sky_tex.keys()[0]
		_sky_from = sky
		_mix = 1.0


func has_sky_art() -> bool:
	return not _sky_tex.is_empty()


## Сменить небо (night | day | eclipse | blood_moon): старое плавно растворяется в новом.
func set_sky(name: String, animate: bool = true) -> void:
	if name == sky or not _sky_tex.has(name):
		return
	_sky_from = sky if _mix >= 0.5 else _sky_from
	sky = name
	if not animate or SettingsService.get_value("reduce_motion") or _sky_from == "":
		_mix = 1.0
		_sky_from = name
		queue_redraw()
		return
	_mix = 0.0
	var tw := create_tween()
	tw.tween_property(self, "_mix", 1.0, FADE_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Вес неба в текущем кадре (для накладок и цветов).
func sky_weight(name: String) -> float:
	var w := 0.0
	if sky == name:
		w += _mix
	if _sky_from == name:
		w += 1.0 - _mix
	return w


func _rebuild() -> void:
	if size == _built_for or size.x < 2:
		return
	_built_for = size
	_layers.clear()
	_windows.clear()
	if region == "academy":
		_build_city()
		return
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.0035
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise.fractal_octaves = 5
	var colors: Array[Color] = [Color("#3A4152"), Color("#2A303E"), Color("#1D212C"), Color("#12141B")]
	var bases: Array[float] = [0.46, 0.60, 0.74, 0.90]
	var amps: Array[float] = [0.36, 0.30, 0.22, 0.14]
	for li in 4:
		var poly := PackedVector2Array()
		poly.append(Vector2(0, size.y))
		var steps := 160
		for i in steps + 1:
			var x := size.x * i / steps
			var n := noise.get_noise_2d(x + li * 1300.0, li * 400.0) * 0.5 + 0.5
			var y := size.y * (bases[li] - n * amps[li])
			poly.append(Vector2(x, y))
		poly.append(Vector2(size.x, size.y))
		_layers.append({"poly": poly, "color": colors[li], "snow": li < 3, "depth": li})
	# тёмные скалы по краям, обрамляющие долину
	var cliff_l := PackedVector2Array([Vector2(0, size.y * 0.25), Vector2(size.x * 0.06, size.y * 0.33),
		Vector2(size.x * 0.10, size.y * 0.52), Vector2(size.x * 0.16, size.y * 0.64), Vector2(size.x * 0.13, size.y * 0.80),
		Vector2(size.x * 0.20, size.y), Vector2(0, size.y)])
	var cliff_r := PackedVector2Array([Vector2(size.x, size.y * 0.20), Vector2(size.x * 0.95, size.y * 0.30),
		Vector2(size.x * 0.92, size.y * 0.47), Vector2(size.x * 0.86, size.y * 0.58), Vector2(size.x * 0.89, size.y * 0.75),
		Vector2(size.x * 0.82, size.y), Vector2(size.x, size.y)])
	_layers.append({"poly": cliff_l, "color": Color("#0C0D12"), "snow": false, "depth": 4})
	_layers.append({"poly": cliff_r, "color": Color("#0C0D12"), "snow": false, "depth": 4})
	_flakes.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 160:
		_flakes.append(Vector3(rng.randf() * size.x, rng.randf() * size.y, rng.randf_range(12, 40)))
	_stars.clear()
	for i in 150:
		_stars.append(Vector3(rng.randf() * size.x, rng.randf() * size.y * 0.42, rng.randf() * TAU))
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if not snow:
		queue_redraw()
		return
	for i in _flakes.size():
		var f: Vector3 = _flakes[i]
		f.y += f.z * delta
		f.x += sin(f.y * 0.01 + i) * 6.0 * delta
		if f.y > size.y:
			f.y = -4
		_flakes[i] = f
	queue_redraw()


func _draw() -> void:
	var blood := 0.0
	if not _sky_tex.is_empty():
		_draw_sky()
		blood = sky_weight("blood_moon")
	elif _tex:
		_draw_cover()
	else:
		_draw_procedural()
	if snow:
		var sc := Color(0.85, 0.87, 0.92, 0.35)
		if not _sky_tex.is_empty():
			sc = Color(0, 0, 0, 0)
			for sk: String in SNOW_COLORS:
				sc += (SNOW_COLORS[sk] as Color) * sky_weight(sk)
		for f: Vector3 in _flakes:
			draw_circle(Vector2(f.x, f.y), 1.0 + f.z / 40.0, sc)
	# виньетка; под кровавой луной — багровая
	var vc := Color(0, 0, 0).lerp(Color(0.3, 0.0, 0.02), blood)
	var v := 10
	for i in v:
		var a := (0.06 + 0.03 * blood) * (1.0 - float(i) / v)
		draw_rect(Rect2(Vector2(i * 14, i * 10), size - Vector2(i * 28, i * 20)), Color(vc, a), false, 16.0)


## Рисунки неба: прежнее и новое крест-накрест, кадр медленно «дышит» (едва заметный наезд и сдвиг).
func _draw_sky() -> void:
	var rect := _cover_rect(_sky_tex[sky].get_size())
	if _mix < 1.0 and _sky_tex.has(_sky_from) and _sky_from != sky:
		draw_texture_rect(_sky_tex[_sky_from], rect, false)
		draw_texture_rect(_sky_tex[sky], rect, false, Color(1, 1, 1, _mix))
	else:
		draw_texture_rect(_sky_tex[sky], rect, false)
	var moon := rect.position + rect.size * MOON_AT
	var night := sky_weight("night")
	var day := sky_weight("day")
	var blood := sky_weight("blood_moon")
	var eclipse := sky_weight("eclipse")
	# ночь: мягкий дышащий ореол луны
	if night > 0.01:
		var p := 0.8 + 0.2 * sin(_t * 0.6)
		for i in 10:
			draw_circle(moon, 36.0 + i * 12.0, Color(0.8, 0.85, 0.95, 0.012 * night * p))
	# день: светлая дымка сверху
	if day > 0.01:
		for i in 12:
			draw_rect(Rect2(0, i * size.y * 0.03, size.x, size.y * 0.03), Color(1, 1, 1, 0.02 * day * (1.0 - i / 12.0)))
	# кровавая луна: медленный пульс, как сердце, и багровая пелена
	if blood > 0.01:
		var beat := pow(0.5 + 0.5 * sin(_t * 1.3), 3.0)
		for i in 16:
			draw_circle(moon, 30.0 + i * 16.0, Color(0.85, 0.08, 0.06, (0.02 + 0.02 * beat) * blood))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.0, 0.02, (0.06 + 0.05 * beat) * blood))
	# затмение: мерцающая корона и тьма, сгущающаяся к краям
	if eclipse > 0.01:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0.02, 0.14 * eclipse))
		for i in 3:
			var r := 34.0 + i * 7.0 + 3.0 * sin(_t * (1.1 + i * 0.4) + i)
			draw_arc(moon, r, 0.0, TAU, 64, Color(0.95, 0.95, 1.0, (0.22 - i * 0.06) * eclipse), 3.0 - i, true)
		for i in 12:
			draw_circle(moon, 44.0 + i * 14.0, Color(0.9, 0.92, 1.0, 0.01 * eclipse))


func _cover_rect(ts: Vector2) -> Rect2:
	var k := maxf(size.x / ts.x, size.y / ts.y) * 1.04
	var ds := ts * k
	var drift := Vector2.ZERO
	if not SettingsService.get_value("reduce_motion"):
		drift = Vector2(sin(_t * 0.017), cos(_t * 0.013)) * size * 0.012
	return Rect2((size - ds) / 2 + drift, ds)


func _draw_cover() -> void:
	var ts := _tex.get_size()
	var k := maxf(size.x / ts.x, size.y / ts.y)
	var ds := ts * k
	draw_texture_rect(_tex, Rect2((size - ds) / 2, ds), false)


func _draw_procedural() -> void:
	var w := phase_weights(tod)
	var night: float = w[0]
	var day: float = w[2]
	var twilight: float = w[1] + w[3]
	var sky_top := _blend(SKY_TOP, w)
	var sky_bot := _blend(SKY_BOT, w)
	var tint := _blend(LAND_TINT, w)
	var bands := 48
	for i in bands:
		var t := float(i) / bands
		draw_rect(Rect2(0, size.y * t * 0.75, size.x, size.y * 0.75 / bands + 1), sky_top.lerp(sky_bot, pow(t, 1.6)))
	# звёзды: ночью ярко, в сумерках и на рассвете — слабее, мерцают
	var star_a := night + 0.45 * twilight
	if star_a > 0.02:
		for st: Vector3 in _stars:
			var tw := 0.55 + 0.45 * sin(_t * 1.8 + st.z * 3.0)
			draw_circle(Vector2(st.x, st.y), 0.8 + fmod(st.z, 1.0), Color(0.88, 0.9, 1.0, 0.75 * star_a * tw))
	# луна с ореолом — ночью и в сумерках
	var moon_a := clampf(night + 0.6 * twilight, 0.0, 1.0)
	if moon_a > 0.02:
		var moon := Vector2(size.x * 0.70, size.y * 0.15)
		for i in 14:
			draw_circle(moon, 40.0 + i * 9, Color(0.78, 0.82, 0.9, 0.018 * moon_a))
		draw_circle(moon, 36, Color(Color("#DADDE3"), moon_a))
		draw_circle(moon + Vector2(-9, 6), 8, Color(Color("#C3C6CD"), moon_a))
		draw_circle(moon + Vector2(11, -9), 5, Color(Color("#C8CBD2"), moon_a))
	# солнце — днём высоко и бледное, на рассвете слева у гор, в сумерках справа; тёплое у горизонта
	var sun_a := clampf(day + 0.8 * twilight, 0.0, 1.0)
	if sun_a > 0.02:
		var sun: Vector2 = Vector2(size.x * 0.30, size.y * 0.12) * day + Vector2(size.x * 0.16, size.y * 0.2) * w[1] \
			+ Vector2(size.x * 0.84, size.y * 0.2) * w[3] + Vector2(size.x * 0.5, size.y * 0.5) * night
		var warm := twilight / maxf(0.001, day + twilight)
		var sc := Color(0.97, 0.95, 0.86).lerp(Color(1.0, 0.62, 0.36), warm)
		for i in 18:
			draw_circle(sun, 44.0 + i * 12, Color(sc, 0.022 * sun_a))
		draw_circle(sun, 40, Color(sc, sun_a))
	var win_a := night + 0.6 * twilight
	for L: Dictionary in _layers:
		var poly: PackedVector2Array = L["poly"]
		draw_colored_polygon(poly, (L["color"] as Color) * tint)
		if win_a > 0.02:
			for wv: Vector3 in L.get("windows", []):
				var flick := 0.75 + 0.25 * sin(_t * 0.7 + wv.z)
				var wc := Color(0.55, 0.85, 0.85) if fmod(wv.z, 1.0) < 0.3 else Color(0.95, 0.8, 0.55)
				draw_rect(Rect2(wv.x, wv.y, 6, 9), Color(wc, 0.55 * win_a * flick))
		if int(L["depth"]) < 4:
			# псевдоградиент: сдвинутые вниз копии хребта темнеют к подножию
			var base_c: Color = (L["color"] as Color) * tint
			for k in range(1, 7):
				var shifted := PackedVector2Array()
				for q in poly:
					shifted.append(Vector2(q.x, minf(size.y, q.y + k * size.y * 0.035)))
				draw_colored_polygon(shifted, base_c.darkened(0.08 * k))
		if L["snow"]:
			# снежные гребни: светлая кромка и штрихи вниз по склонам (гравюра)
			var ridge := PackedVector2Array()
			for i in range(1, poly.size() - 1):
				ridge.append(poly[i])
			var depth: int = L["depth"]
			var alpha := 0.55 - depth * 0.15
			draw_polyline(ridge, Color(0.86, 0.88, 0.93, alpha), 2.0, true)
			for i in range(1, ridge.size() - 1, 2):
				var p := ridge[i]
				var is_peak := p.y < ridge[i - 1].y and p.y < ridge[i + 1].y
				if is_peak:
					var h := 14.0 + (3 - depth) * 10.0
					draw_line(p, p + Vector2(-h * 0.35, h), Color(0.86, 0.88, 0.93, alpha * 0.8), 1.5)
					draw_line(p, p + Vector2(h * 0.3, h * 0.9), Color(0.86, 0.88, 0.93, alpha * 0.6), 1.2)
		# туман над каждым слоем
		if int(L["depth"]) < 4:
			var y0 := size.y * (0.46 + int(L["depth"]) * 0.14)
			for j in 8:
				draw_rect(Rect2(0, y0 + j * 6, size.x, 6), Color(0.62, 0.66, 0.75, 0.018 * (8 - j) / 8.0))
