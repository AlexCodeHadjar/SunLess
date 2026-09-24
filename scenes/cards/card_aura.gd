class_name CardAura
extends Control
## Живой облик карты: слой поверх CardView, рисующий особенности по тегам, травмам и ранам —
## лёд, огонь, кислота, кровь, шипы, камень, металл, тьма, свет, буря, вода, гниль, чары,
## паразит, паутина, рой, ярость, трещины, истощение, страх, оглушение.
## Не больше MAX мотивов на карту; при «меньше движения» — только статичные элементы.

const MAX := 3

## Тег → мотив.
const TAG_MOTIFS := {
	"Лёд": "ice", "Холод": "ice", "Переохлаждение": "ice",
	"Огонь": "fire", "Белое пламя": "fire", "Лава": "fire", "Горит": "fire", "Пепел": "fire",
	"Кислота": "acid", "Яд": "acid", "Отравлен": "acid",
	"Гниль": "rot", "Нежить": "rot", "Порча": "rot",
	"Кровь": "blood", "Кровотечение": "blood", "Жажда крови": "blood", "Запах крови": "blood",
	"Плетение крови": "blood", "Ранен": "blood",
	"Ярость": "rage", "Гордыня": "rage",
	"Шипы": "spikes", "Жало": "spikes", "Когти": "spikes", "Клыки": "spikes",
	"Камень": "stone", "Земля": "stone", "Коралл": "stone", "Конструкт": "stone",
	"Железо": "metal", "Сталь": "metal", "Броня": "metal", "Цепь": "metal", "Панцирь": "metal",
	"Хитин": "metal", "Чешуя": "metal", "Серебро": "metal",
	"Тьма": "shadow", "Тень": "shadow", "Контроль теней": "shadow", "Благословение теней": "shadow",
	"Пустота": "shadow", "Кошмарное существо": "shadow", "Бесплотный": "shadow",
	"Свет": "light", "Звёздный свет": "light", "Лунный свет": "light", "Золото": "light",
	"Молния": "storm", "Буря": "storm", "Ветер": "storm",
	"Вода": "water", "Глубина": "water", "Глубинный": "water", "Промок": "water", "Соль моря": "water",
	"Очарование": "mind", "Ментальное давление": "mind", "Очарован": "mind", "Одержимость": "mind",
	"Проклятие": "mind", "Марионетка": "mind", "Кукловод": "mind", "Пожирание душ": "mind", "Зачарование": "mind",
	"Паразит": "parasite",
	"Паутина": "web", "Сети": "web",
	"Рой": "swarm",
}
## Травма → мотив.
const TRAUMA_MOTIFS := {
	"T01": "ice", "T02": "blood", "T03": "cracks", "T04": "exhaust", "T05": "dread",
	"T06": "daze", "T07": "mind", "T08": "blood", "T09": "pain", "T10": "blood",
}

var motifs: Array = []
var tint := Color.WHITE        # оттенок камня (коралл — розоватый)
var _seed := 0
var _t := 0.0
var _static := false
var _shapes := {}              # заранее посчитанные фигуры: трещины, вены, шипы, кристаллы
var _back: Control             # слой за картой: ореол света, круг рун, жар огня


## Мотивы по тегам, травмам и числу ран; травмы и раны — первыми.
static func motifs_for(tags: Array, traumas: Array = [], wounds: int = 0) -> Array:
	var out: Array = []
	for t: Variant in traumas:
		var m: String = TRAUMA_MOTIFS.get(str(t), "")
		if m != "" and not out.has(m):
			out.append(m)
	if wounds > 0 and not out.has("blood"):
		out.append("blood")
	if wounds > 1 and not out.has("cracks"):
		out.append("cracks")
	for t: Variant in tags:
		var m2: String = TAG_MOTIFS.get(str(t), "")
		if m2 != "" and not out.has(m2):
			out.append(m2)
	return out.slice(0, MAX)


func setup(p_motifs: Array, seed_key: String) -> void:
	motifs = p_motifs
	_seed = hash(seed_key)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_static = Vfx.reduced()
	_build_shapes()
	if not _static:
		_add_particles()
	if motifs.has("light") or motifs.has("mind") or motifs.has("fire"):
		_back = Control.new()
		_back.show_behind_parent = true
		_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_back.size = size
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_back.material = m
		_back.draw.connect(_draw_back)
		get_parent().add_child.call_deferred(_back)
		tree_exiting.connect(_drop_back)
	set_process(not _static)


func _drop_back() -> void:
	if is_instance_valid(_back):
		_back.queue_free()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _back:
		_back.queue_redraw()


static func _tx(name: String) -> Texture2D:
	return Vfx.tex(name)


func _k() -> float:
	return size.x / 140.0


func _lift() -> float:
	var p := get_parent()
	return float(p.get("_lift")) if p and p.get("_lift") != null else 0.0


# --- заготовки -----------------------------------------------------------------

func _build_shapes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var k := _k()
	var w := size.x
	var h := size.y
	if motifs.has("stone") or motifs.has("cracks"):
		var cracks: Array = []
		var n := 3 if motifs.has("stone") else 2
		for i in n:
			var start := _edge_point(rng, w, h)
			cracks.append_array(_crack(rng, start, Vector2(w / 2, h / 2), 5, 26.0 * k))
		_shapes["cracks"] = cracks
	if motifs.has("parasite"):
		var veins: Array = []
		for corner: Vector2 in [Vector2(0, h), Vector2(w, 0)]:
			veins.append_array(_crack(rng, corner, Vector2(w / 2, h / 2), 7, 22.0 * k))
		_shapes["veins"] = veins
	if motifs.has("spikes"):
		var spikes: Array = []
		var count := 16
		k = minf(k, 1.4)   # на крупных картах шипы не растут бесконечно
		for i in count:
			var p := _edge_point(rng, w, h)
			var out := _outward(p, w, h).rotated(rng.randf_range(-0.35, 0.35))
			# по бокам короче — рядом столбец тегов
			var side_k := 0.5 if absf(out.x) > 0.5 else 1.0
			spikes.append({"p": p, "n": out, "len": rng.randf_range(16, 32) * k * side_k, "wid": rng.randf_range(6, 11) * k,
				"ph": rng.randf() * TAU})
		_shapes["spikes"] = spikes
	if motifs.has("ice"):
		var shards: Array = []
		for i in 22:
			var p := _edge_point(rng, w, h)
			var inward := -_outward(p, w, h)
			var dir := inward.rotated(rng.randf_range(-0.7, 0.7))
			shards.append({"p": p, "d": dir, "len": rng.randf_range(8, 22) * k, "wid": rng.randf_range(2.5, 5) * k})
		_shapes["shards"] = shards
	for key: String in ["blood", "acid", "water"]:
		if motifs.has(key):
			var drips: Array = []
			for i in (6 if key == "blood" else 5):
				drips.append({"x": rng.randf_range(0.08, 0.92) * w, "len": rng.randf_range(0.18, 0.5) * h,
					"w": rng.randf_range(1.8, 3.6) * k, "ph": rng.randf(), "sp": rng.randf_range(0.08, 0.16)})
			_shapes["drips_" + key] = drips
	if motifs.has("blood"):
		var spots: Array = []
		for i in 5:
			var c := Vector2(rng.randf_range(0.1, 0.9) * w, rng.randf_range(0.1, 0.9) * h)
			for j in 4:
				spots.append({"c": c + Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10)) * k, "r": rng.randf_range(1.2, 4.0) * k})
		_shapes["spots"] = spots
	if motifs.has("web"):
		_shapes["web_corners"] = [Vector2(0, 0), Vector2(w, h)] if rng.randf() < 0.5 else [Vector2(w, 0), Vector2(0, h)]


func _edge_point(rng: RandomNumberGenerator, w: float, h: float) -> Vector2:
	var per := 2.0 * (w + h)
	var d := rng.randf() * per
	if d < w:
		return Vector2(d, 0)
	d -= w
	if d < h:
		return Vector2(w, d)
	d -= h
	if d < w:
		return Vector2(w - d, h)
	return Vector2(0, h - (d - w))


func _outward(p: Vector2, w: float, h: float) -> Vector2:
	var dl := p.x
	var dr := w - p.x
	var dt := p.y
	var db := h - p.y
	var m := minf(minf(dl, dr), minf(dt, db))
	if m == dt:
		return Vector2.UP
	if m == db:
		return Vector2.DOWN
	if m == dl:
		return Vector2.LEFT
	return Vector2.RIGHT


## Ветвящаяся ломаная от края к центру: [PackedVector2Array, …].
func _crack(rng: RandomNumberGenerator, from: Vector2, toward: Vector2, steps: int, seg: float) -> Array:
	var out: Array = []
	var pts := PackedVector2Array([from])
	var p := from
	var dir := (toward - from).normalized()
	for i in steps:
		dir = dir.rotated(rng.randf_range(-0.6, 0.6)).normalized()
		p += dir * seg * rng.randf_range(0.6, 1.2)
		pts.append(p)
		if i > 0 and rng.randf() < 0.35:
			var b := PackedVector2Array([p])
			var bd := dir.rotated(rng.randf_range(0.6, 1.2) * (1 if rng.randf() < 0.5 else -1))
			var bp := p
			for j in 2:
				bp += bd * seg * rng.randf_range(0.4, 0.8)
				b.append(bp)
			out.append(b)
	out.push_front(pts)
	return out


func _add_particles() -> void:
	var k := _k()
	var w := size.x
	var h := size.y
	for m: String in motifs:
		var p: CPUParticles2D = null
		match m:
			"fire":
				add_child(_emitter("kenney/flame_05", 10, 0.9, Rect2(w * 0.1, h - 4, w * 0.8, 4), Vector2(0, -1), 10.0, Vector2(0, -30), 20, 45,
					0.05 * k, 0.1 * k, [[0.0, Color(1, 0.55, 0.15, 0)], [0.2, Color(1, 0.5, 0.12, 0.8)], [1.0, Color(0.6, 0.1, 0.02, 0)]], true))
				p = _emitter("spark", 16, 1.6, Rect2(0, h - 6, w, 6), Vector2(0, -1), 20.0, Vector2(0, -40), 20, 55,
					0.02 * k, 0.05 * k, [[0.0, Color(1, 0.7, 0.3, 1)], [0.7, Color(1, 0.35, 0.1, 0.6)], [1.0, Color(0.5, 0.1, 0.05, 0)]], true)
			"ice":
				p = _emitter("soft_dot", 10, 3.0, Rect2(0, 0, w, 4), Vector2(0, 1), 30.0, Vector2(0, 14), 6, 16,
					0.012 * k, 0.025 * k, [[0.0, Color(0.9, 0.97, 1, 0)], [0.2, Color(0.9, 0.97, 1, 0.9)], [1.0, Color(0.9, 0.97, 1, 0)]], false)
			"acid":
				p = _emitter("soft_dot", 8, 2.2, Rect2(w * 0.1, h * 0.55, w * 0.8, h * 0.4), Vector2(0, -1), 15.0, Vector2(0, -6), 4, 14,
					0.012 * k, 0.03 * k, [[0.0, Color(0.6, 1, 0.3, 0)], [0.3, Color(0.6, 1, 0.3, 0.7)], [1.0, Color(0.6, 1, 0.3, 0)]], true)
			"light":
				p = _emitter("spark_star", 10, 2.6, Rect2(0, h * 0.3, w, h * 0.7), Vector2(0, -1), 25.0, Vector2(0, -10), 8, 22,
					0.02 * k, 0.045 * k, [[0.0, Color(1, 0.92, 0.6, 0)], [0.3, Color(1, 0.92, 0.6, 0.9)], [1.0, Color(1, 0.85, 0.5, 0)]], true)
			"rot":
				p = _emitter("kenney/smoke_07", 10, 4.0, Rect2(0, h * 0.6, w, h * 0.4), Vector2(1, -0.4), 40.0, Vector2(0, -6), 4, 12,
					0.12 * k, 0.24 * k, [[0.0, Color(0.55, 0.7, 0.3, 0)], [0.4, Color(0.55, 0.7, 0.3, 0.45)], [1.0, Color(0.4, 0.55, 0.25, 0)]], false)
				add_child(p)
				p = _emitter("soft_dot", 8, 3.0, Rect2(0, h * 0.4, w, h * 0.6), Vector2(0, -1), 30.0, Vector2(0, -8), 4, 10,
					0.01 * k, 0.022 * k, [[0.0, Color(0.7, 0.95, 0.4, 0)], [0.3, Color(0.7, 0.95, 0.4, 0.8)], [1.0, Color(0.7, 0.95, 0.4, 0)]], true)
			"shadow":
				p = Vfx.card_smoke(size)
				p.amount = 26
				p.emitting = true
				p.local_coords = true
				p.show_behind_parent = true
				p.scale_amount_min = 0.1 * k
				p.scale_amount_max = 0.2 * k
			"stone":
				p = _emitter("kenney/dirt_01", 5, 2.2, Rect2(w * 0.1, h - 6, w * 0.8, 6), Vector2(0, 1), 20.0, Vector2(0, 60), 4, 14,
					0.04 * k, 0.08 * k, [[0.0, Color(0.7, 0.66, 0.6, 0.9)], [1.0, Color(0.55, 0.52, 0.48, 0)]], false)
				p.angle_max = 360.0
		if p:
			add_child(p)


func _emitter(texname: String, amount: int, life: float, area: Rect2, dir: Vector2, spread: float, grav: Vector2,
		vmin: float, vmax: float, smin: float, smax: float, ramp: Array, additive: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = Vfx.tex(texname)
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.local_coords = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.position = area.get_center()
	p.emission_rect_extents = area.size / 2
	p.direction = dir
	p.spread = spread
	p.gravity = grav
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.scale_amount_min = smin
	p.scale_amount_max = smax
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s: Array in ramp:
		offs.append(float(s[0]))
		cols.append(s[1])
	g.offsets = offs
	g.colors = cols
	p.color_ramp = g
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD if additive else CanvasItemMaterial.BLEND_MODE_MIX
	p.material = m
	return p


# --- отрисовка -----------------------------------------------------------------

func _draw() -> void:
	var lift := _lift()
	draw_set_transform(Vector2(0, -lift))
	var r := Rect2(Vector2.ZERO, size)
	var k := _k()
	for m: String in motifs:
		match m:
			"ice": _draw_ice(r, k)
			"fire": _draw_glow(r, k, Color(1.0, 0.5, 0.15), 0.35 + 0.15 * sin(_t * 9.0) * sin(_t * 5.3))
			"acid":
				_draw_splats(r, "acid", Color(0.75, 1.0, 0.55, 0.7))
				_draw_drips(r, k, "acid", Color(0.55, 0.95, 0.25, 0.85))
			"water": _draw_drips(r, k, "water", Color(0.45, 0.7, 1.0, 0.6))
			"blood": _draw_blood(r, k)
			"rage": _draw_glow(r, k, Color(0.9, 0.1, 0.1), 0.3 + 0.25 * (0.5 + 0.5 * sin(_t * 4.0)))
			"spikes": _draw_spikes(r, k)
			"stone": _draw_stone(r, k)
			"cracks": _draw_cracks(k, Color(0.02, 0.02, 0.03, 0.85), Color(0.85, 0.85, 0.9, 0.35))
			"metal": _draw_metal(r, k)
			"shadow": _draw_vignette(r, k, Color(0, 0, 0), 0.35)
			"light": _draw_glow(r, k, Color(1.0, 0.88, 0.55), 0.25 + 0.1 * sin(_t * 2.0))
			"storm": _draw_storm(r, k)
			"rot":
				draw_rect(r, Color(0.2, 0.28, 0.08, 0.16))
				_draw_vignette(r, k, Color(0.28, 0.4, 0.1), 0.55)
			"mind": _draw_wisps(r, k, Color(0.72, 0.5, 1.0))
			"parasite": _draw_veins(k)
			"web": _draw_web(r, k)
			"swarm": _draw_swarm(r, k)
			"exhaust": draw_rect(r, Color(0.35, 0.35, 0.38, 0.22 + 0.06 * sin(_t * 1.3)))
			"dread": _draw_vignette(r, k, Color(0.05, 0.0, 0.08), 0.35 + 0.2 * (0.5 + 0.5 * sin(_t * 2.6)))
			"pain": _draw_vignette(r, k, Color(0.7, 0.05, 0.08), 0.18 + 0.2 * maxf(0.0, sin(_t * 3.2)))
			"daze": _draw_daze(r, k)
	draw_set_transform(Vector2.ZERO)


## Слой за картой (аддитивный): ореол света, медленно вращающийся круг рун, жар огня.
func _draw_back() -> void:
	var lift := _lift()
	var c := Vector2(size.x / 2, size.y / 2 - lift)
	for m: String in motifs:
		match m:
			"light":
				var s := size.x * 2.2
				_back.draw_texture_rect(_tx("kenney/light_01"), Rect2(c - Vector2(s, s) / 2, Vector2(s, s)), false,
					Color(1.0, 0.85, 0.5, 0.55 + 0.15 * sin(_t * 1.8)))
			"mind":
				var s2 := size.x * 1.7
				_back.draw_set_transform(c, _t * 0.35)
				_back.draw_texture_rect(_tx("kenney/magic_01"), Rect2(-s2 / 2, -s2 / 2, s2, s2), false, Color(0.75, 0.5, 1.0, 0.95))
				_back.draw_set_transform(c, -_t * 0.22)
				_back.draw_texture_rect(_tx("kenney/magic_02"), Rect2(-s2 * 0.4, -s2 * 0.4, s2 * 0.8, s2 * 0.8), false, Color(0.65, 0.45, 1.0, 0.7))
				_back.draw_set_transform(Vector2.ZERO)
			"fire":
				var s3 := size.x * 1.8
				_back.draw_texture_rect(_tx("kenney/light_02"), Rect2(Vector2(c.x - s3 / 2, size.y - lift - s3 * 0.6), Vector2(s3, s3)), false,
					Color(1.0, 0.45, 0.1, 0.45 + 0.2 * sin(_t * 7.0) * sin(_t * 3.1)))


## Свечение за краем карты: несколько контуров с падающей прозрачностью.
func _draw_glow(r: Rect2, k: float, col: Color, a: float) -> void:
	for i in 6:
		draw_rect(r.grow((i + 1) * 2.5 * k), Color(col, a * (1.0 - i / 6.0) * 0.5), false, 2.5 * k)
	draw_rect(r, Color(col, a), false, 1.5 * k)


## Затемнение к краям внутри карты.
func _draw_vignette(r: Rect2, k: float, col: Color, a: float) -> void:
	for i in 7:
		draw_rect(r.grow(-i * 4.0 * k), Color(col, a * (1.0 - i / 7.0) * 0.6), false, 4.0 * k)


func _draw_ice(r: Rect2, k: float) -> void:
	var frost := Color(0.8, 0.93, 1.0)
	for i in 5:
		draw_rect(r.grow(-i * 3.0 * k), Color(frost, 0.32 * (1.0 - i / 5.0)), false, 3.0 * k)
	for s: Dictionary in _shapes.get("shards", []):
		var p: Vector2 = s["p"]
		var d: Vector2 = s["d"]
		var tip := p + d * float(s["len"])
		var side := d.orthogonal() * float(s["wid"])
		draw_colored_polygon(PackedVector2Array([p - side, tip, p + side]), Color(0.86, 0.95, 1.0, 0.75))
		draw_line(p, tip, Color(1, 1, 1, 0.9), 1.0)
	if not _static:
		var glint := _tx("kenney/star_07")
		for i in 5:
			var s2: Dictionary = _shapes["shards"][i * 4 % _shapes["shards"].size()]
			var a := maxf(0.0, sin(_t * 2.2 + i * 1.7))
			var c: Vector2 = s2["p"] + (s2["d"] as Vector2) * float(s2["len"])
			var gs := 26.0 * k * a
			draw_texture_rect(glint, Rect2(c - Vector2(gs, gs) / 2, Vector2(gs, gs)), false, Color(0.85, 0.95, 1.0, a))


## Потёки: растут вниз от края, на конце капля; по кругу.
func _draw_drips(r: Rect2, k: float, key: String, col: Color) -> void:
	var from_top := key == "blood"
	for d: Dictionary in _shapes.get("drips_" + key, []):
		var cyc := 1.0 if _static else fmod(float(d["ph"]) + _t * float(d["sp"]), 1.0)
		var grow := minf(1.0, cyc / 0.7)
		var fade := 1.0 if cyc < 0.85 else (1.0 - (cyc - 0.85) / 0.15)
		var ln := float(d["len"]) * grow
		var x := float(d["x"])
		var y0 := 0.0 if from_top else r.size.y * 0.82
		var y1 := y0 + ln if from_top else y0 + ln * 0.35
		var c := Color(col, col.a * fade)
		draw_line(Vector2(x, y0), Vector2(x, y1), c, float(d["w"]), true)
		draw_circle(Vector2(x, y1), float(d["w"]) * 1.1, c)
		if not from_top:
			# пятно у нижнего края
			draw_circle(Vector2(x, y0), float(d["w"]) * 2.2, Color(col, col.a * 0.35))
			# капля, отрывающаяся за край
			if cyc > 0.7 and not _static:
				var fall := (cyc - 0.7) / 0.3
				draw_circle(Vector2(x, r.size.y + fall * 30.0 * k), float(d["w"]), Color(col, col.a * (1.0 - fall)))


## Брызги с листа Sinestesia (4×2 кадра по 256×512; нижний ряд — брызги) в заданном цвете.
func _draw_splats(r: Rect2, key: String, col: Color) -> void:
	var tex := _tx("blood/splatter_red" if key == "blood" else "blood/splatter_green")
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + key.length()
	for i in 2:
		var frame := rng.randi_range(4, 7)
		var src := Rect2((frame % 4) * 256, 512 + 40, 256, 400)
		var w := r.size.x * rng.randf_range(0.5, 0.75)
		var dst := Rect2(Vector2(rng.randf_range(0.0, r.size.x - w), rng.randf_range(0.0, r.size.y * 0.55)), Vector2(w, w * 400.0 / 256.0))
		draw_texture_rect_region(tex, dst, src, col)


func _draw_blood(r: Rect2, k: float) -> void:
	var grime := _tx("blood/blood_grime")
	var gs := grime.get_size()
	var gw := gs.x * 0.55
	draw_texture_rect_region(grime, r, Rect2(Vector2(float(absi(_seed) % 200), float(absi(_seed) % 120)), Vector2(gw, gw * r.size.y / r.size.x)), Color(0.7, 0.12, 0.12, 0.35))
	_draw_splats(r, "blood", Color(0.5, 0.06, 0.06, 0.85))
	for s: Dictionary in _shapes.get("spots", []):
		draw_circle(s["c"], float(s["r"]), Color(0.45, 0.02, 0.04, 0.8))
	_draw_drips(r, k, "blood", Color(0.55, 0.02, 0.05, 0.9))
	_draw_vignette(r, k, Color(0.5, 0.0, 0.03), 0.25)


func _draw_spikes(_r: Rect2, k: float) -> void:
	for s: Dictionary in _shapes.get("spikes", []):
		var p: Vector2 = s["p"]
		var n: Vector2 = s["n"]
		var breathe := 1.0 if _static else 0.85 + 0.15 * sin(_t * 2.0 + float(s["ph"]))
		var tip := p + n * float(s["len"]) * breathe
		var side := n.orthogonal() * float(s["wid"])
		# костяной шип: светлая сторона, тёмная сторона, кровавое остриё
		draw_colored_polygon(PackedVector2Array([p - side, tip, p]), Color(0.62, 0.56, 0.5, 0.97))
		draw_colored_polygon(PackedVector2Array([p, tip, p + side]), Color(0.3, 0.26, 0.24, 0.97))
		draw_polyline(PackedVector2Array([p - side, tip, p + side]), Color(0.05, 0.04, 0.04, 0.9), 1.2)
		draw_circle(tip, 1.8 * k, Color(0.7, 0.08, 0.1, 0.95))


func _draw_cracks(k: float, dark: Color, light: Color) -> void:
	for pts: PackedVector2Array in _shapes.get("cracks", []):
		draw_polyline(pts, dark, 2.2 * k, true)
		var off := PackedVector2Array()
		for q in pts:
			off.append(q + Vector2(1, 1))
		draw_polyline(off, light, 0.8, true)


func _draw_stone(r: Rect2, k: float) -> void:
	var stone := Color(0.55, 0.53, 0.5) * tint
	draw_rect(r, Color(stone, 0.12))
	draw_rect(r.grow(-2 * k), Color(stone, 0.7), false, 4.0 * k)
	_draw_cracks(k, Color(0.03, 0.03, 0.03, 0.9), Color(stone.lightened(0.4), 0.5))


func _draw_metal(r: Rect2, k: float) -> void:
	var metal := Color(0.72, 0.74, 0.78)
	var L := 26.0 * k
	for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if c.x <= r.position.x + 1 else -1.0
		var sy := 1.0 if c.y <= r.position.y + 1 else -1.0
		var pts := PackedVector2Array([c + Vector2(0, L * sy), c, c + Vector2(L * sx, 0)])
		draw_polyline(pts, Color(0.12, 0.12, 0.14, 0.95), 7.0 * k)
		draw_polyline(pts, Color(metal, 0.9), 3.0 * k)
		draw_circle(c + Vector2(7 * sx, 7 * sy) * k, 2.2 * k, metal.lightened(0.3))
	if _static:
		return
	# блик, пробегающий по диагонали раз в несколько секунд
	var cyc := fmod(_t / 3.6, 1.0)
	if cyc < 0.35:
		var s := cyc / 0.35
		var c0 := -r.size.y + (r.size.x + r.size.y * 2.0) * s
		var seg := _diag_segment(r, c0)
		if seg.size() == 2:
			draw_line(seg[0], seg[1], Color(1, 1, 1, 0.08), 16.0 * k)
			draw_line(seg[0], seg[1], Color(1, 1, 1, 0.22), 3.0 * k)


## Отрезок прямой x - y*0.6 = c внутри прямоугольника.
func _diag_segment(r: Rect2, c: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for y: float in [r.position.y, r.end.y]:
		var x := c + y * 0.6
		if x >= r.position.x and x <= r.end.x:
			pts.append(Vector2(x, y))
	for x2: float in [r.position.x, r.end.x]:
		var y2 := (x2 - c) / 0.6
		if y2 > r.position.y and y2 < r.end.y:
			pts.append(Vector2(x2, y2))
	return pts.slice(0, 2)


func _draw_storm(r: Rect2, k: float) -> void:
	draw_rect(r, Color(0.6, 0.75, 1.0, 0.35), false, 1.5 * k)
	if _static:
		return
	var slot := int(_t * 2.2)
	var local := fmod(_t * 2.2, 1.0)
	if local > 0.3:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + slot
	# молния-текстура Kenney от случайного края внутрь карты
	var a := _edge_point(rng, r.size.x, r.size.y)
	var inward := -_outward(a, r.size.x, r.size.y)
	var alpha := 1.0 - local / 0.3
	var bolt := _tx("kenney/spark_05" if rng.randf() < 0.5 else "kenney/spark_06")
	var L := rng.randf_range(60, 110) * k
	draw_set_transform(Vector2(a.x, a.y - _lift()), inward.angle() - PI / 2.0 + rng.randf_range(-0.5, 0.5))
	draw_texture_rect(bolt, Rect2(-L * 0.25, 0, L * 0.5, L), false, Color(0.75, 0.85, 1.0, alpha))
	draw_set_transform(Vector2(0, -_lift()))


func _draw_wisps(r: Rect2, k: float, col: Color) -> void:
	var c := r.get_center()
	var rx := r.size.x * 0.62
	var ry := r.size.y * 0.55
	for i in 3:
		for j in 7:
			var ang := _t * 1.1 + i * TAU / 3.0 - j * 0.07
			var p := c + Vector2(cos(ang) * rx, sin(ang) * ry)
			draw_circle(p, (4.0 - j * 0.45) * k, Color(col, 0.55 * (1.0 - j / 7.0)))
	draw_rect(r, Color(col, 0.22), false, 1.5 * k)


func _draw_veins(k: float) -> void:
	var grow := 1.0 if _static else minf(1.0, _t / 2.5)
	var pulse := 0.6 + 0.4 * sin(_t * 3.0)
	for pts: PackedVector2Array in _shapes.get("veins", []):
		var n := maxi(2, int(ceil(pts.size() * grow)))
		var part := pts.slice(0, n)
		draw_polyline(part, Color(0.25, 0.02, 0.12, 0.9), 3.2 * k, true)
		draw_polyline(part, Color(0.75, 0.15, 0.4, 0.55 * pulse), 1.2 * k, true)


func _draw_web(r: Rect2, k: float) -> void:
	var col := Color(0.85, 0.87, 0.9, 0.55)
	for c: Vector2 in _shapes.get("web_corners", []):
		var sx := 1.0 if c.x <= 1 else -1.0
		var sy := 1.0 if c.y <= 1 else -1.0
		var R := 46.0 * k
		var rays: Array = []
		for i in 5:
			var ang := i * (PI / 2.0) / 4.0
			var d := Vector2(cos(ang) * sx, sin(ang) * sy)
			rays.append(d)
			draw_line(c, c + d * R, col, 1.0)
		for ring in range(1, 4):
			var pts := PackedVector2Array()
			for d: Vector2 in rays:
				pts.append(c + d * R * ring / 3.5)
			draw_polyline(pts, col, 1.0)


func _draw_swarm(r: Rect2, k: float) -> void:
	var c := r.get_center()
	for i in 20:
		var fi := float(i)
		var p := c + Vector2(sin(_t * (1.3 + fi * 0.17) + fi) * r.size.x * 0.64, cos(_t * (1.7 + fi * 0.11) + fi * 2.0) * r.size.y * 0.58)
		var wing := absf(sin(_t * 30.0 + fi))
		draw_circle(p, 2.6 * k, Color(0.03, 0.03, 0.03, 0.95))
		draw_line(p + Vector2(-4, -1.5) * k, p + Vector2(4, -1.5) * k, Color(0.75, 0.75, 0.8, 0.5 * wing), 1.2)


func _draw_daze(r: Rect2, k: float) -> void:
	var c := Vector2(r.get_center().x, r.position.y - 6 * k)
	for i in 3:
		var ang := _t * 2.4 + i * TAU / 3.0
		var p := c + Vector2(cos(ang) * 26.0 * k, sin(ang) * 7.0 * k)
		var s := 5.0 * k
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.3, -s * 0.3), p + Vector2(s, 0), p + Vector2(s * 0.3, s * 0.3),
			p + Vector2(0, s), p + Vector2(-s * 0.3, s * 0.3), p + Vector2(-s, 0), p + Vector2(-s * 0.3, -s * 0.3)]), Color(1, 0.9, 0.5, 0.9))
