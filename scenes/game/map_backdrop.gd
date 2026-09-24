class_name MapBackdrop
extends Control
## Фон региона. Если есть art/regions/<регион>.png — показывает его;
## иначе рисует гравюрный горный перевал (небо, луна или солнце, звёзды, хребты, туман, снег).
## Время суток tod: 0 ночь, 0.25 рассвет, 0.5 день, 0.75 сумерки — меняется по неделям.

const TOD_NAMES := ["ночь", "рассвет", "день", "сумерки"]
# ключевые цвета неба и оттенок гор для [ночь, рассвет, день, сумерки]
const SKY_TOP := [Color("#07080C"), Color("#1C1B2E"), Color("#4E5A70"), Color("#150E1C")]
const SKY_BOT := [Color("#4A5264"), Color("#B8826E"), Color("#AEB6C2"), Color("#9A5540")]
const LAND_TINT := [Color(1, 1, 1), Color(1.22, 1.08, 1.08), Color(1.5, 1.5, 1.55), Color(1.18, 0.98, 0.95)]

var region := "mountain_pass"
var snow := true
var tod := 0.0
var _stars: Array = []      # [Vector3(x, y, фаза)]
var _t := 0.0
var _tex: Texture2D
var _layers: Array = []     # [{poly: PackedVector2Array, color: Color}]
var _flakes: Array = []     # [Vector3(x, y, speed)]
var _built_for := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := "res://art/regions/%s.png" % region
	if ResourceLoader.exists(p):
		_tex = load(p)
	resized.connect(_rebuild)
	_rebuild()
	set_process(not SettingsService.get_value("reduce_motion"))


## Время суток по номеру недели: 1 — ночь, 2 — рассвет, 3 — день, 4 — сумерки, 5 — снова ночь.
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


func _rebuild() -> void:
	if size == _built_for or size.x < 2:
		return
	_built_for = size
	_layers.clear()
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
	if _tex:
		_draw_cover()
	else:
		_draw_procedural()
	if snow:
		for f: Vector3 in _flakes:
			draw_circle(Vector2(f.x, f.y), 1.0 + f.z / 40.0, Color(0.85, 0.87, 0.92, 0.35))
	# виньетка
	var v := 10
	for i in v:
		var a := 0.06 * (1.0 - float(i) / v)
		draw_rect(Rect2(Vector2(i * 14, i * 10), size - Vector2(i * 28, i * 20)), Color(0, 0, 0, a), false, 16.0)


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
	for L: Dictionary in _layers:
		var poly: PackedVector2Array = L["poly"]
		draw_colored_polygon(poly, (L["color"] as Color) * tint)
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
