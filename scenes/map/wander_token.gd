class_name WanderToken
extends Control
## Бродячий босс на карте-плане (WanderRules, docs/22): фишка-диорама на месте, где он стоит.
## Анимация — как просил владелец: кадры art/map/wanderers/<босс>_1…_4 (.webp/.png) сменяют друг друга через
## прозрачность (кадр держится HOLD секунд, следующий проступает за FADE). Ушёл на новое место — фишка плавно идёт
## туда (покачиваясь). Картинок нет — рисуется тёмный силуэт с горящими глазами и тенью.

const HOLD := 1.5
const FADE := 0.8
const EYES := {"W1": Color(1.0, 0.35, 0.25), "W2": Color(1.0, 0.6, 0.2), "W3": Color(0.7, 0.85, 1.0), "W4": Color(0.6, 1.0, 0.95)}

var wid := ""
var frames: Array = []
var _a: TextureRect
var _b: TextureRect
var _i := 0
var _t := 0.0
var _walk := 0.0      # 0..1 — идёт к новому месту (покачивание)


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
		add_child(tr)
		if k == 0:
			_a = tr
		else:
			_b = tr
			_b.modulate.a = 0.0


## Перейти на новое место: идёт по прямой, покачиваясь (в мировых координатах слоя).
func walk_to(p: Vector2) -> void:
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
	if frames.size() > 1 and not Vfx.reduced():
		var cycle := HOLD + FADE
		var ph := fmod(_t, cycle)
		var n := int(_t / cycle)
		if n != _i:   # новый цикл: верхний кадр стал нижним, следующий проступает сверху
			_i = n
			_a.texture = _b.texture if _b.modulate.a > 0.5 else _a.texture
			_b.texture = frames[(n + 1) % frames.size()]
			_b.modulate.a = 0.0
		if ph > HOLD:
			_b.modulate.a = (ph - HOLD) / FADE
	if frames.is_empty():
		queue_redraw()


func _draw() -> void:
	if not frames.is_empty():
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
