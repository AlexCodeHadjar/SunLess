class_name Vfx
extends RefCounted
## Фабрика частиц на текстурах Kenney (CC0): чёрный дым, пепел, искры, туман.
## Все эмиттеры — CPUParticles2D (работают в рендерере Compatibility).

const TEX := "res://art/vfx/%s.png"

static var _noise: NoiseTexture2D
static var _dissolve: Shader


static func tex(name: String) -> Texture2D:
	return load(TEX % name)


static func _ramp(stops: Array) -> Gradient:
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s: Array in stops:
		offs.append(float(s[0]))
		cols.append(s[1])
	var g := Gradient.new()
	g.offsets = offs
	g.colors = cols
	return g


static func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for p: Vector2 in points:
		c.add_point(p)
	return c


static func _material(additive: bool) -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD if additive else CanvasItemMaterial.BLEND_MODE_MIX
	return m


static func reduced() -> bool:
	return bool(SettingsService.get_value("reduce_motion"))


## Чёрный дым, поднимающийся от краёв карты при наведении.
static func card_smoke(card_size: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex(["black_smoke_a", "black_smoke_b", "black_smoke_c"].pick_random())
	p.amount = 44
	p.lifetime = 2.0
	p.preprocess = 0.0
	p.emitting = false
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	var pts := PackedVector2Array()
	var step := 10.0
	var x := 0.0
	while x <= card_size.x:
		pts.append(Vector2(x, 0))
		pts.append(Vector2(x, card_size.y))
		x += step
	var y := 0.0
	while y <= card_size.y:
		pts.append(Vector2(0, y))
		pts.append(Vector2(card_size.x, y))
		y += step
	p.emission_points = pts
	p.direction = Vector2(0, -1)
	p.spread = 35.0
	p.gravity = Vector2(0, -26)
	p.initial_velocity_min = 14.0
	p.initial_velocity_max = 42.0
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	var k := card_size.x / 140.0
	p.scale_amount_min = 0.22 * k
	p.scale_amount_max = 0.42 * k
	p.scale_amount_curve = _curve([Vector2(0, 0.4), Vector2(0.5, 1.0), Vector2(1, 1.5)])
	p.color_ramp = _ramp([[0.0, Color(0.0, 0.0, 0.0, 0.0)], [0.2, Color(0.01, 0.01, 0.015, 0.95)], [0.6, Color(0.02, 0.02, 0.03, 0.7)], [1.0, Color(0.04, 0.04, 0.05, 0.0)]])
	p.material = _material(false)
	return p


## Пепел и угли при распаде карты. rect — в координатах родителя.
static func ash_burst(rect: Rect2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex("soft_dot")
	p.amount = 90
	p.lifetime = 2.2
	p.one_shot = true
	p.explosiveness = 0.15
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.position = rect.get_center()
	p.emission_rect_extents = rect.size / 2
	p.direction = Vector2(0, -1)
	p.spread = 60.0
	p.gravity = Vector2(12, -45)
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 60.0
	p.scale_amount_min = 0.012
	p.scale_amount_max = 0.035
	p.color_ramp = _ramp([[0.0, Color(1.0, 0.55, 0.2, 1.0)], [0.25, Color(0.55, 0.5, 0.48, 0.9)], [1.0, Color(0.25, 0.24, 0.24, 0.0)]])
	p.material = _material(false)
	return p


## Горячие угли от кромки сгорания (аддитивные).
static func embers_burst(rect: Rect2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex("spark")
	p.amount = 40
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.2
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.position = rect.get_center()
	p.emission_rect_extents = rect.size / 2
	p.direction = Vector2(0, -1)
	p.spread = 40.0
	p.gravity = Vector2(0, -60)
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 90.0
	p.scale_amount_min = 0.02
	p.scale_amount_max = 0.06
	p.color_ramp = _ramp([[0.0, Color(1.0, 0.7, 0.3, 1.0)], [0.6, Color(1.0, 0.35, 0.1, 0.7)], [1.0, Color(0.6, 0.1, 0.05, 0.0)]])
	p.material = _material(true)
	return p


## Постоянные искры, поднимающиеся от земли (атмосфера карты).
static func ambient_embers(area: Rect2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex("spark")
	p.amount = 34
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.position = Vector2(area.get_center().x, area.end.y)
	p.emission_rect_extents = Vector2(area.size.x / 2, 10)
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.gravity = Vector2(6, -8)
	p.initial_velocity_min = 18.0
	p.initial_velocity_max = 45.0
	p.scale_amount_min = 0.015
	p.scale_amount_max = 0.04
	p.color_ramp = _ramp([[0.0, Color(1.0, 0.5, 0.2, 0.0)], [0.15, Color(1.0, 0.55, 0.22, 0.85)], [0.8, Color(0.9, 0.3, 0.1, 0.4)], [1.0, Color(0.5, 0.1, 0.05, 0.0)]])
	p.material = _material(true)
	return p


## Медленно плывущий туман: крупные полупрозрачные клубы.
static func fog(area: Rect2, alpha: float = 0.07) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex(["smoke_a", "smoke_b", "smoke_c", "smoke_d"].pick_random())
	p.amount = 18
	p.lifetime = 26.0
	p.preprocess = 26.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.position = area.get_center()
	p.emission_rect_extents = area.size / 2
	p.direction = Vector2(1, 0)
	p.spread = 12.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 16.0
	p.angular_velocity_min = -4.0
	p.angular_velocity_max = 4.0
	p.angle_max = 360.0
	p.scale_amount_min = 1.8
	p.scale_amount_max = 3.2
	p.color_ramp = _ramp([[0.0, Color(0.65, 0.7, 0.8, 0.0)], [0.3, Color(0.65, 0.7, 0.8, alpha)], [0.7, Color(0.6, 0.65, 0.75, alpha)], [1.0, Color(0.6, 0.65, 0.75, 0.0)]])
	p.material = _material(false)
	return p


## Разовый выброс: серебряные искры (успех) или тёмный дым (провал).
static func burst(pos: Vector2, success: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 0.85
	p.position = pos
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 30.0
	p.spread = 180.0
	if success:
		p.texture = tex("spark_star")
		p.amount = 36
		p.lifetime = 1.2
		p.initial_velocity_min = 120.0
		p.initial_velocity_max = 320.0
		p.gravity = Vector2(0, 60)
		p.scale_amount_min = 0.04
		p.scale_amount_max = 0.10
		p.color_ramp = _ramp([[0.0, Color(0.9, 0.93, 1.0, 1.0)], [1.0, Color(0.75, 0.8, 0.9, 0.0)]])
		p.material = _material(true)
	else:
		p.texture = tex("black_smoke_d")
		p.amount = 22
		p.lifetime = 1.8
		p.initial_velocity_min = 40.0
		p.initial_velocity_max = 140.0
		p.gravity = Vector2(0, -20)
		p.scale_amount_min = 0.3
		p.scale_amount_max = 0.7
		p.angle_max = 360.0
		p.color_ramp = _ramp([[0.0, Color(0.1, 0.02, 0.03, 0.8)], [1.0, Color(0.02, 0.02, 0.02, 0.0)]])
		p.material = _material(false)
	return p


## Материал распада карты (см. dissolve.gdshader).
static func dissolve_material(card_size: Vector2) -> ShaderMaterial:
	if _dissolve == null:
		_dissolve = load("res://scenes/vfx/dissolve.gdshader")
	if _noise == null:
		_noise = NoiseTexture2D.new()
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		var fn := FastNoiseLite.new()
		fn.frequency = 0.012
		fn.fractal_octaves = 4
		_noise.noise = fn
	var m := ShaderMaterial.new()
	m.shader = _dissolve
	m.set_shader_parameter("noise_tex", _noise)
	m.set_shader_parameter("card_size", card_size)
	m.set_shader_parameter("progress", 0.0)
	return m


## Удаляет разовый эмиттер после окончания.
static func autofree(p: CPUParticles2D) -> void:
	p.emitting = true
	p.finished.connect(p.queue_free)
