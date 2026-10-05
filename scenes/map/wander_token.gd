class_name WanderToken
extends Control
## Бродячий босс на карте-плане (WanderRules, docs/22): фишка-диорама на месте, где он стоит.
## Кадры — 4 ракурса (просьба владельца 03.10): art/map/wanderers/<босс>_1…_4 (.webp/.png) — босс смотрит
## 1 — вниз-влево, 2 — вниз-вправо, 3 — вверх-вправо, 4 — вверх-влево (камера та же, тварь повёрнута на своей
## подставке). Ракурс меняется только при переходе на другое место (уточнение владельца 04.10): фишка поворачивается
## по направлению пути (новый кадр проступает через прозрачность, FADE) и плавно идёт, покачиваясь; стоя — не
## поворачивается. Картинок нет — тёмный силуэт с глазами.

const FADE := 0.8
const EYES := {"W1": Color(1.0, 0.35, 0.25), "W2": Color(1.0, 0.6, 0.2), "W3": Color(0.7, 0.85, 1.0), "W4": Color(0.6, 1.0, 0.95)}

var wid := ""
var frames: Array = []      # ракурсы 1–4 (может быть меньше — тогда что есть)
var _a: TextureRect         # текущий ракурс
var _b: TextureRect         # следующий — проступает поверх
var _face := 0              # индекс текущего ракурса
var _t := 0.0
var _walk := 0.0            # 0..1 — идёт к новому месту (покачивание)


static func make(boss: String, side: float) -> WanderToken:
	var t := WanderToken.new()
	t.wid = boss
	t.size = Vector2(side, side)
	t.pivot_offset = t.size / 2.0
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for n in range(1, 5):
		var tex := _art("%s_%d" % [boss, n])
		if tex != null:
			t.frames.append(tex)
	return t


static func _art(key: String) -> Texture2D:
	for ext: String in ["webp", "png"]:
		var p := "res://art/map/wanderers/%s.%s" % [key, ext]
		if ResourceLoader.exists(p):
			return load(p)
	return null


func _ready() -> void:
	if frames.is_empty():
		return
	for k in 2:
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.texture = frames[0]
		tr.modulate = Color(1.18, 1.14, 1.2)   # на ночной карте тварь чуть светлее — не сливается
		add_child(tr)
		if k == 0:
			_a = tr
		else:
			_b = tr
			_b.modulate.a = 0.0


## Ракурс по направлению на экране: вниз-влево 0, вниз-вправо 1, вверх-вправо 2, вверх-влево 3.
static func face_for(dir: Vector2) -> int:
	if dir.y >= 0.0:
		return 0 if dir.x < 0.0 else 1
	return 2 if dir.x >= 0.0 else 3


## Повернуться к ракурсу i — новый кадр проступает через прозрачность.
func turn_to(i: int) -> void:
	if frames.is_empty():
		return
	i = clampi(i, 0, frames.size() - 1)
	if i == _face:
		return
	_face = i
	_b.texture = frames[i]
	_b.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_b, "modulate:a", 1.0, 0.0 if Vfx.reduced() else FADE)
	tw.tween_callback(func() -> void:
		_a.texture = frames[i]
		_b.modulate.a = 0.0)


## Перейти на новое место: повернуться по пути и идти по прямой, покачиваясь (в мировых координатах слоя).
func walk_to(p: Vector2) -> void:
	turn_to(face_for(p - position))
	var tw := create_tween()
	_walk = 1.0
	set_meta("walking", true)
	tw.tween_property(self, "position", p, 0.0 if Vfx.reduced() else 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		_walk = 0.0
		rotation = 0.0
		remove_meta("walking"))


func _process(delta: float) -> void:
	_t += delta
	if _walk > 0.0:
		rotation = sin(_t * 9.0) * 0.06
	queue_redraw()   # ореол дышит; без картинок — силуэт


func _draw() -> void:
	if not frames.is_empty():
		# под фишкой — тень у ног (картинки без подставки, линия земли — 92% высоты, tools/import_wanderers.py) и мягкий фиолетовый
		# ореол (цвет бродячих боссов): видно на любой карте
		var g := 0.75 + 0.25 * sin(_t * 1.7)
		draw_set_transform(size / 2.0 + Vector2(0, size.y * 0.38), 0.0, Vector2(1.0, 0.36))
		for k in 4:
			draw_circle(Vector2.ZERO, size.x * (0.4 - k * 0.07), Color(0.0, 0.0, 0.02, 0.12))
		for k2 in 3:
			draw_circle(Vector2.ZERO, size.x * (0.48 - k2 * 0.06), Color(0.62, 0.42, 1.0, 0.05 * g))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var c := size / 2.0
	var r := size.x * 0.3
	var breath := 1.0 + 0.04 * sin(_t * 1.6)
	# тень на земле и тёмный силуэт
	draw_set_transform(c + Vector2(0, r * 0.75), 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, r * 1.25, Color(0, 0, 0, 0.5))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(c, r * breath, Color(0.06, 0.04, 0.06, 0.92))
	draw_circle(c + Vector2(0, -r * 0.45), r * 0.62 * breath, Color(0.08, 0.05, 0.07, 0.95))
	var eye: Color = EYES.get(wid, Color(1, 0.3, 0.3))
	var glow := 0.6 + 0.4 * sin(_t * 2.3)
	for sx: float in [-1.0, 1.0]:
		var p := c + Vector2(sx * r * 0.22, -r * 0.5)
		draw_circle(p, r * 0.16, Color(eye.r, eye.g, eye.b, 0.25 * glow))
		draw_circle(p, r * 0.07, Color(eye.r, eye.g, eye.b, glow))
