class_name MissionMarker
extends Control
## Миссия на карте главы — карта (docs/15 §15). Пока отряда нет — просто карта: щелчок открывает брифинг,
## героя можно бросить прямо на неё. Отряд отправлен — над картой кольцо таймера с секундами;
## отряд прибыл — кольцо горит и пульсирует «!». Кольцо появляется с отскоком, последние секунды
## отстукивают тихим тиком, прибытие — вспышка искр.

signal pressed(mission_id: String)
signal hero_dropped(mission_id: String, card_id: String)

const RING_R := 30.0

var mission_id := ""
var progress := -1.0      # 0..1 — отряд в пути; -1 — отряда нет
var remaining := 0.0      # секунд до прибытия
var arrived := false
var card: CardView
var _ring: Control
var _t := 0.0


static func make(mid: String, card_size: Vector2) -> MissionMarker:
	var m := MissionMarker.new()
	m.mission_id = mid
	m.custom_minimum_size = card_size
	m.size = card_size
	return m


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	card = CardView.make(mission_id, size, false)
	card.sway = true
	card.highlight = str(ContentDB.data.missions.get(mission_id, {}).get("type", "")) == "story"
	card.clicked.connect(func(_id: String) -> void:
		AudioManager.play("open", -6.0)
		pressed.emit(mission_id))
	# правый щелчок по миссии — тоже брифинг (планшета у миссий нет)
	card.inspect_requested.connect(func(_id: String) -> void: pressed.emit(mission_id))
	card.set_drag_forwarding(Callable(), _can_drop, _drop)
	add_child(card)
	_ring = Control.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ring.draw.connect(_draw_ring)
	add_child(_ring)


func set_state(p: float, rem: float, arr: bool) -> void:
	var changed := arr != arrived or not is_equal_approx(p, progress) or int(ceil(rem)) != int(ceil(remaining))
	var was_busy := busy()
	var was_arrived := arrived
	var sec_before := int(ceil(remaining))
	progress = p
	remaining = rem
	arrived = arr
	if not was_busy and busy() and not arrived:
		_appear()
	elif busy() and not arrived and int(ceil(rem)) != sec_before and int(ceil(rem)) in [1, 2, 3]:
		AudioManager.play("tick", -14.0, 1.0 + 0.1 * (3 - int(ceil(rem))))
	if arrived and not was_arrived:
		_flash()
	if changed:
		card.dimmed = progress >= 0.0 and not arrived
		card.queue_redraw()
		_ring.queue_redraw()


## Кольцо таймера появляется над картой с отскоком.
func _appear() -> void:
	_ring.pivot_offset = Vector2(size.x / 2.0, size.y * 0.36)
	if Vfx.reduced():
		return
	_ring.scale = Vector2(0.2, 0.2)
	create_tween().tween_property(_ring, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Отряд прибыл: вспышка искр над картой и толчок кольца.
func _flash() -> void:
	_ring.pivot_offset = Vector2(size.x / 2.0, size.y * 0.36)
	if Vfx.reduced() or not is_inside_tree():
		return
	var fx := Vfx.burst(position + Vector2(size.x / 2.0, size.y * 0.36), true)
	get_parent().add_child(fx)
	Vfx.autofree(fx)
	_ring.scale = Vector2(1.35, 1.35)
	create_tween().tween_property(_ring, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func busy() -> bool:
	return arrived or progress >= 0.0


func _process(delta: float) -> void:
	_t += delta
	if arrived:
		_ring.queue_redraw()


func _can_drop(_at: Vector2, data: Variant) -> bool:
	return not busy() and data is Dictionary and data.get("kind", "") == "character"


func _drop(_at: Vector2, data: Variant) -> void:
	hero_dropped.emit(mission_id, str(data["card"]))


func _draw_ring() -> void:
	if not busy():
		return
	var c := Vector2(size.x / 2.0, size.y * 0.36)
	if arrived:
		var pulse := 0.5 + 0.5 * sin(_t * 4.0)
		_ring.draw_circle(c, RING_R + 12.0 + 4.0 * pulse, Color(Palette.GOLD, 0.2 + 0.14 * pulse))
	_ring.draw_circle(c, RING_R, Color(0.05, 0.055, 0.075, 0.92))
	_ring.draw_arc(c, RING_R, 0.0, TAU, 56, Color(1, 1, 1, 0.12), 6.0, true)
	var gold := Color("#E3C98E")
	var p := 1.0 if arrived else clampf(progress, 0.0, 1.0)
	_ring.draw_arc(c, RING_R, -PI / 2.0, -PI / 2.0 + TAU * p, 56, gold, 6.0, true)
	var center := "!" if arrived else "%dс" % int(ceil(remaining))
	var f := UITheme.font("title_bold")
	var fs := 32 if center.length() <= 2 else 24
	var tw := f.get_string_size(center, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_ring.draw_string(f, c + Vector2(-tw / 2.0, fs * 0.34), center, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, gold if arrived else Palette.TEXT)
	var cap := "отряд прибыл" if arrived else "отряд в пути"
	var sf := UITheme.font("sans_bold")
	var cw := sf.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var cp := c + Vector2(-cw / 2.0, RING_R + 22.0)
	_ring.draw_string_outline(sf, cp, cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color(0, 0, 0, 0.9))
	_ring.draw_string(sf, cp, cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, gold if arrived else Palette.SILVER)
