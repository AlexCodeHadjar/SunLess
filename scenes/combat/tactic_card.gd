class_name TacticCard
extends Control
## Карта приёма в руке (бой). Клик — выбрать; повторный клик — снять выбор.

signal picked(tactic_id: String)

const SIZE := Vector2(240, 250)

var tactic_id := ""
var selected := false
var _hover := false


static func make(id: String) -> TacticCard:
	var c := TacticCard.new()
	c.tactic_id = id
	c.custom_minimum_size = SIZE
	c.size = SIZE
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.mouse_entered.connect(c._set_hover.bind(true))
	c.mouse_exited.connect(c._set_hover.bind(false))
	return c


func _set_hover(on: bool) -> void:
	_hover = on
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		AudioManager.play("pick")
		picked.emit(tactic_id)
		accept_event()


func _draw() -> void:
	var t: Dictionary = ContentDB.data.tactics.get(tactic_id, {})
	var lift := -14.0 if (selected or _hover) else 0.0
	var r := Rect2(Vector2(0, lift), size)
	draw_rect(Rect2(r.position + Vector2(0, 8), r.size), Color(0, 0, 0, 0.4))
	draw_rect(r, Color("#1C1B24"))
	var inner := r.grow(-7)
	draw_rect(inner, Color("#2A2436") if selected else Color("#22222C"))
	var border := Palette.GOLD if selected else (Palette.SILVER if _hover else Palette.LINE)
	draw_rect(r, border, false, 3.0 if selected else 1.5)
	draw_rect(inner, border.darkened(0.4), false, 1.0)
	var fb := UITheme.font("title")
	var f := UITheme.font("sans")
	draw_string(UITheme.font("caps"), inner.position + Vector2(0, 26), "ПРИЁМ", HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 15, Palette.TEXT_DIM)
	draw_multiline_string(fb, inner.position + Vector2(6, 60), str(t.get("name", tactic_id)), HORIZONTAL_ALIGNMENT_CENTER, inner.size.x - 12, 26, 2, Palette.TEXT)
	draw_line(inner.position + Vector2(20, 100), inner.position + Vector2(inner.size.x - 20, 100), Palette.LINE, 1.0)
	draw_multiline_string(f, inner.position + Vector2(10, 126), str(t.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, inner.size.x - 20, 17, 5, Palette.TEXT_DIM)
	var cost := int(t.get("mana", 0))
	if cost > 0:
		draw_string(UITheme.font("sans_bold"), inner.position + Vector2(10, inner.size.y - 12), "◈ %d" % cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Palette.MANA)
	var bonus := float(t.get("bonus", 0.0))
	if bonus > 0:
		draw_string(UITheme.font("title_bold"), inner.position + Vector2(0, inner.size.y - 10), "+%d%%" % int(bonus * 100), HORIZONTAL_ALIGNMENT_RIGHT, inner.size.x - 10, 27, Palette.STAT_UP)
