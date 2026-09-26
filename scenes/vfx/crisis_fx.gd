class_name CrisisFX
extends Control
## Момент кризиса психики (docs/16 §9г): всё внимание — на карте героя.
## Экран размывается и темнеет, карта героя вылетает крупно в центр в облике кризиса.
## ПАНИКА — дрожь и рывки, багровый пульс по краям, трещины, пепел; ПОДЪЁМ ДУХА — вращающиеся золотые лучи,
## мягкое свечение, искры вверх. Сверху — название состояния, снизу — имя и реплика героя.
## Несколько кризисов — по очереди. Щелчок — пропустить. По окончании — сигнал finished.

signal finished

const CARD := Vector2(300, 514)
const IN := 0.35
const HOLD := 1.9
const OUT := 0.35

var _queue: Array = []
var _blur: ColorRect
var _mat: ShaderMaterial
var _stage: Control
var _t := 0.0
var _state := ""
var _skip := false
var _k := 0.0          # сила фона 0..1

const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.02, 1.0);
void fragment() {
	vec4 c = textureLod(screen_tex, SCREEN_UV, amount * 3.2);
	float d = distance(SCREEN_UV, vec2(0.5));
	float vig = smoothstep(0.25, 0.85, d);
	COLOR = vec4(mix(c.rgb, tint.rgb, amount * (0.55 + 0.35 * vig)), 1.0);
}
"""


## Показать кризисы [{card, state, quote}] поверх всего. Ждать: await fx.finished.
static func play(parent: Node, crises: Array) -> CrisisFX:
	var fx := CrisisFX.new()
	fx._queue = crises.duplicate()
	parent.add_child(fx)
	return fx


func _ready() -> void:
	top_level = true
	z_as_relative = false
	z_index = 95
	position = Vector2.ZERO
	size = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_blur = ColorRect.new()
	_blur.size = size
	_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BLUR_SHADER
	_mat.shader = sh
	_blur.material = _mat
	add_child(_blur)
	_stage = Control.new()
	_stage.size = size
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.draw.connect(_draw_stage)
	add_child(_stage)
	_run()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_skip = true
		accept_event()


func _process(delta: float) -> void:
	_t += delta
	_mat.set_shader_parameter("amount", _k)
	_mat.set_shader_parameter("tint", Color(0.12, 0.0, 0.01) if _state == "panic" else Color(0.06, 0.04, 0.0))
	_stage.queue_redraw()


func _wait(sec: float) -> void:
	var left := sec
	while left > 0.0 and not _skip:
		await get_tree().process_frame
		left -= get_process_delta_time()


func _run() -> void:
	var c := ContentDB.data
	for e: Dictionary in _queue:
		_skip = false
		_state = str(e.get("state", "panic"))
		var cid := str(e.get("card", ""))
		var panic := _state == "panic"
		AudioManager.play("trauma" if panic else "success", -2.0, 0.7 if panic else 1.1)
		# фон: размытие и затемнение
		var tw := create_tween()
		tw.tween_property(self, "_k", 1.0, IN).set_trans(Tween.TRANS_SINE)
		# карта героя в облике кризиса
		var card := CardView.make(cid, CARD, false)
		card.psy_override = _state
		card.hover_lift = false
		card.smoke_on_hover = false
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.position = size / 2 - CARD / 2 + Vector2(0, 30)
		card.pivot_offset = CARD / 2
		card.scale = Vector2(0.45, 0.45)
		card.modulate.a = 0.0
		add_child(card)
		var tc := create_tween().set_parallel()
		tc.tween_property(card, "scale", Vector2(1.12, 1.12), IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tc.tween_property(card, "modulate:a", 1.0, IN * 0.6)
		tc.chain().tween_property(card, "scale", Vector2.ONE, 0.25)
		# частицы: пепел и дым (паника) или золотые искры (подъём)
		var rect := Rect2(card.position, CARD)
		var p := Vfx.ash_burst(rect) if panic else Vfx.embers_burst(rect.grow(40))
		if not panic:
			p.color_ramp = Vfx._ramp([[0.0, Color(1.0, 0.95, 0.7, 1.0)], [0.6, Color(1.0, 0.8, 0.35, 0.7)], [1.0, Color(1.0, 0.7, 0.2, 0.0)]])
			p.amount = 70
		add_child(p)
		p.emitting = true
		# надписи
		var title := UITheme.label("ПАНИКА" if panic else "ПОДЪЁМ ДУХА", "title_bold", 64,
			SquadLifeUI.PANIC_COLOR if panic else SquadLifeUI.UPLIFT_COLOR)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.size = Vector2(size.x, 80)
		title.position = Vector2(0, card.position.y - 120)
		title.add_theme_constant_override("outline_size", 12)
		title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		title.modulate.a = 0.0
		add_child(title)
		var sub := UITheme.label("%s\n%s" % [c.card_name(cid), str(e.get("quote", ""))], "serif_italic", 24, Palette.TEXT)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.size = Vector2(900, 90)
		sub.position = Vector2(size.x / 2 - 450, card.position.y + CARD.y + 34)
		sub.add_theme_constant_override("outline_size", 8)
		sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		sub.modulate.a = 0.0
		add_child(sub)
		var tt := create_tween().set_parallel()
		tt.tween_property(title, "modulate:a", 1.0, 0.25).set_delay(IN * 0.5)
		tt.tween_property(sub, "modulate:a", 1.0, 0.3).set_delay(IN)
		tt.tween_property(title, "scale", Vector2(1.0, 1.0), 0.25).from(Vector2(1.25, 1.25)).set_delay(IN * 0.5)
		title.pivot_offset = title.size / 2
		# паника: рывки карты
		var base := card.position
		var held := 0.0
		while held < HOLD + IN and not _skip:
			await get_tree().process_frame
			var dt := get_process_delta_time()
			held += dt
			if not is_instance_valid(card):
				break
			if panic and not Vfx.reduced():
				var shake := 6.0 * (1.0 if held < IN + 0.4 else 0.35)
				card.position = base + Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
				card.rotation = deg_to_rad(randf_range(-1.5, 1.5)) if held < IN + 0.4 else 0.0
			elif not panic:
				card.position = base + Vector2(0, -6.0 * sin(held * 2.2))
		# уход
		var to := create_tween().set_parallel()
		for n: CanvasItem in [card, title, sub]:
			to.tween_property(n, "modulate:a", 0.0, OUT)
		if e == _queue.back():
			to.tween_property(self, "_k", 0.0, OUT)
		await to.finished
		for n2: Node in [card, title, sub, p]:
			if is_instance_valid(n2):
				n2.queue_free()
	finished.emit()
	queue_free()


## Свет и тьма вокруг карты: паника — багровый пульс и трещины от краёв; подъём — лучи и ореол.
func _draw_stage() -> void:
	if _state == "" or _k <= 0.01:
		return
	var center := size / 2 + Vector2(0, 30)
	if _state == "panic":
		var beat := pow(0.5 + 0.5 * sin(_t * 7.0), 2.0)
		for i in 14:
			var r := 900.0 - i * 45.0
			_stage.draw_arc(center, r, 0, TAU, 64, Color(0.55, 0.02, 0.04, 0.035 * _k * (0.6 + 0.4 * beat)), 40.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for c in 7:
			var a := rng.randf() * TAU
			var p := center + Vector2.from_angle(a) * 900.0
			var pts := PackedVector2Array([p])
			for j in 6:
				p = p.lerp(center, 0.12) + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
				pts.append(p)
			_stage.draw_polyline(pts, Color(0.75, 0.08, 0.08, 0.35 * _k * beat), 2.0)
	else:
		for i in 16:
			var a := _t * 0.25 + i * TAU / 16.0
			var far := center + Vector2.from_angle(a) * 900.0
			var side := Vector2.from_angle(a + PI / 2) * 60.0
			_stage.draw_colored_polygon(PackedVector2Array([center, far + side, far - side]), Color(1.0, 0.85, 0.45, 0.05 * _k))
		for i2 in 10:
			_stage.draw_circle(center, 180.0 + i2 * 26.0, Color(1.0, 0.85, 0.5, 0.025 * _k))
