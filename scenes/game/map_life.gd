class_name MapLife
extends Control
## Мелкая жизнь над картой региона: плывущие облака, падающие звёзды и звездопад, стаи птиц днём
## и летучих мышей ночью, далёкие огни на склонах, светлячки у земли, лучи солнца.
## Всё зависит от времени суток tod (0 ночь, 0.25 рассвет, 0.5 день, 0.75 сумерки).
## При «меньше движения» — только облака и огни, без полёта.

var tod := 0.0
var _t := 0.0
var _static := false
var _clouds: Array = []     # [{tex, pos, scale, speed, alpha}]
var _meteors: Array = []    # [{from, dir, len, t, dur}]
var _flocks: Array = []     # [{pos, vel, n, bats, t}]
var _lights: Array = []     # [Vector3(x, y, phase)]
var _flies: Array = []      # [{p, ph}]
var _next_meteor := 3.0
var _next_flock := 6.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_static = Vfx.reduced()
	_rng.seed = 91
	var names := ["clouds/cloud_01", "clouds/cloud_02", "clouds/cloud_03", "clouds/cloud_04", "clouds/cloud_06"]
	for i in 6:
		_clouds.append({"tex": Vfx.tex(names[i % names.size()]), "pos": Vector2(_rng.randf() * size.x, size.y * _rng.randf_range(0.02, 0.32)),
			"scale": _rng.randf_range(0.55, 1.0), "speed": _rng.randf_range(4.0, 11.0), "alpha": _rng.randf_range(0.45, 0.8)})
	for i in 7:
		_lights.append(Vector3(_rng.randf_range(0.08, 0.92) * size.x, size.y * _rng.randf_range(0.42, 0.62), _rng.randf() * TAU))
	for i in 18:
		_flies.append({"p": Vector2(_rng.randf() * size.x, size.y * _rng.randf_range(0.7, 0.98)), "ph": _rng.randf() * TAU})
	set_process(true)


func set_tod(v: float, animate: bool) -> void:
	if not animate or _static:
		tod = fmod(v, 1.0)
		return
	var target := v if v >= tod else v + 1.0
	var tw := create_tween()
	tw.tween_method(func(x: float) -> void: tod = fmod(x, 1.0), tod, target, 3.0)


## Веса фаз [ночь, рассвет, день, сумерки] для текущего tod.
func weights() -> Array:
	return MapBackdrop.phase_weights(tod)


func _process(delta: float) -> void:
	_t += delta
	var w := weights()
	var night: float = w[0] + 0.5 * (w[1] + w[3])
	for c: Dictionary in _clouds:
		var cp: Vector2 = c["pos"]
		if not _static:
			cp.x += float(c["speed"]) * delta
		var cw := 768.0 * float(c["scale"])
		if cp.x > size.x + cw * 0.3:
			cp.x = -cw
		c["pos"] = cp
	if not _static:
		# падающие звёзды — ночью и в сумерках
		_next_meteor -= delta
		if _next_meteor <= 0.0:
			var burst := 1 if _rng.randf() < 0.8 else _rng.randi_range(3, 5)
			if night > 0.4:
				for i in burst:
					_spawn_meteor(i * 0.25)
			_next_meteor = _rng.randf_range(4.0, 9.0)
		for m: Dictionary in _meteors:
			m["t"] = float(m["t"]) + delta
		_meteors = _meteors.filter(func(m: Dictionary) -> bool: return float(m["t"]) < float(m["dur"]))
		# стаи
		_next_flock -= delta
		if _next_flock <= 0.0:
			_spawn_flock(night > 0.5)
			_next_flock = _rng.randf_range(14.0, 28.0)
		for f: Dictionary in _flocks:
			f["pos"] += f["vel"] * delta
			f["t"] = float(f["t"]) + delta
		_flocks = _flocks.filter(func(f: Dictionary) -> bool: return f["pos"].x > -200 and f["pos"].x < size.x + 200)
		for fl: Dictionary in _flies:
			var ph: float = fl["ph"]
			fl["p"] += Vector2(sin(_t * 0.7 + ph), cos(_t * 0.9 + ph * 1.3)) * 10.0 * delta
	queue_redraw()


func _spawn_meteor(delay: float) -> void:
	var from := Vector2(_rng.randf_range(0.1, 0.95) * size.x, size.y * _rng.randf_range(0.0, 0.22))
	var ang := deg_to_rad(_rng.randf_range(140, 160))
	_meteors.append({"from": from, "dir": Vector2(cos(ang), sin(ang)), "len": _rng.randf_range(160, 320), "t": -delay, "dur": _rng.randf_range(0.7, 1.1)})


func _spawn_flock(bats: bool) -> void:
	var left := _rng.randf() < 0.5
	var y := size.y * _rng.randf_range(0.1, 0.35)
	var speed := _rng.randf_range(60, 110) * (1.0 if left else -1.0)
	_flocks.append({"pos": Vector2(-150.0 if left else size.x + 150.0, y), "vel": Vector2(speed, _rng.randf_range(-6, 6)),
		"n": _rng.randi_range(3, 7), "bats": bats, "t": 0.0, "seed": _rng.randi()})


func _draw() -> void:
	var w := weights()
	var night: float = w[0]
	var dawn: float = w[1]
	var day: float = w[2]
	var dusk: float = w[3]
	var dark: float = night + 0.5 * (dawn + dusk)
	# облака: ночью тёмно-синие, днём светлые, на рассвете и в сумерках — тёплые
	var ccol := Color(0.3, 0.34, 0.45) * night + Color(1.0, 0.72, 0.62) * dawn + Color(0.92, 0.93, 0.96) * day + Color(0.95, 0.55, 0.42) * dusk
	for c: Dictionary in _clouds:
		var cw := 768.0 * float(c["scale"])
		var a := float(c["alpha"]) * (0.35 + 0.35 * day + 0.2 * (dawn + dusk))
		draw_texture_rect(c["tex"], Rect2(c["pos"], Vector2(cw, cw * 0.55)), false, Color(ccol, a))
	# лучи солнца днём
	if day > 0.05:
		var sun := Vector2(size.x * 0.3, -40)
		for i in 5:
			var ang := deg_to_rad(62 + i * 11 + sin(_t * 0.2 + i) * 2.0)
			var d := Vector2(cos(ang), sin(ang))
			var L := size.y * 1.1
			var side := d.orthogonal() * (26.0 + i * 8.0)
			draw_colored_polygon(PackedVector2Array([sun, sun + d * L - side, sun + d * L + side]), Color(1.0, 0.97, 0.88, 0.035 * day))
	# падающие звёзды: голова — звезда Kenney, хвост — затухающая линия
	var head_tex := Vfx.tex("kenney/star_04")
	for m: Dictionary in _meteors:
		var t := float(m["t"])
		if t < 0.0:
			continue
		var k := t / float(m["dur"])
		var from: Vector2 = m["from"]
		var dir: Vector2 = m["dir"]
		var head := from + dir * float(m["len"]) * 1.6 * k
		var fade := minf(1.0, (1.0 - k) * 3.0) * dark
		for j in 8:
			var a0 := head - dir * float(m["len"]) * 0.12 * j
			var a1 := head - dir * float(m["len"]) * 0.12 * (j + 1)
			draw_line(a0, a1, Color(0.9, 0.93, 1.0, fade * (1.0 - j / 8.0) * 0.8), 2.2 - j * 0.2, true)
		var hs := 26.0
		draw_texture_rect(head_tex, Rect2(head - Vector2(hs, hs) / 2, Vector2(hs, hs)), false, Color(1, 1, 1, fade))
	# стаи: днём птицы (галочки), ночью летучие мыши (зубчатые крылья)
	for f: Dictionary in _flocks:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(f["seed"])
		for i in int(f["n"]):
			var off := Vector2(-i * 22.0 * signf(f["vel"].x), (i % 2) * 12.0 + rng.randf_range(-6, 6))
			var p: Vector2 = f["pos"] + off
			var flap := sin(float(f["t"]) * (14.0 if f["bats"] else 8.0) + i)
			var col := Color(0.04, 0.04, 0.06, 0.85) if dark > 0.5 else Color(0.18, 0.18, 0.22, 0.8)
			if f["bats"]:
				var wy := -4.0 * flap
				draw_polyline(PackedVector2Array([p + Vector2(-9, wy), p + Vector2(-6, wy + 3), p + Vector2(-3, wy + 1), p,
					p + Vector2(3, wy + 1), p + Vector2(6, wy + 3), p + Vector2(9, wy)]), col, 2.0, true)
			else:
				var wy2 := -5.0 * flap
				draw_polyline(PackedVector2Array([p + Vector2(-8, wy2), p, p + Vector2(8, wy2)]), col, 1.8, true)
	# далёкие огни на склонах — ночью, мерцают
	if dark > 0.1:
		for L: Vector3 in _lights:
			var fl := 0.6 + 0.4 * sin(_t * 3.0 + L.z) * sin(_t * 1.7 + L.z * 2.0)
			var lp := Vector2(L.x, L.y)
			draw_circle(lp, 7.0, Color(1.0, 0.6, 0.25, 0.08 * dark * fl))
			draw_circle(lp, 2.2, Color(1.0, 0.75, 0.4, 0.8 * dark * fl))
	# светлячки у земли — ночью
	if night > 0.2 and not _static:
		for fl2: Dictionary in _flies:
			var a2 := maxf(0.0, sin(_t * 1.6 + float(fl2["ph"]) * 3.0)) * night
			draw_circle(fl2["p"], 5.0, Color(0.8, 1.0, 0.45, 0.12 * a2))
			draw_circle(fl2["p"], 1.6, Color(0.9, 1.0, 0.6, 0.9 * a2))
