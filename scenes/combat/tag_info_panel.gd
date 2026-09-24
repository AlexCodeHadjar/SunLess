class_name TagInfoPanel
extends PanelContainer
## Карточка тега при наведении на гиперссылку: категория, описание, вклад, известные связи.

var _label: RichTextLabel


func _ready() -> void:
	top_level = true
	z_index = 60
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := UITheme.box(Color(0.06, 0.06, 0.08, 0.96), Palette.SILVER.darkened(0.3), 1, 6, 16)
	st.shadow_color = Color(0, 0, 0, 0.6)
	st.shadow_size = 16
	add_theme_stylebox_override("panel", st)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.custom_minimum_size = Vector2(460, 0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("normal_font_size", 19)
	add_child(_label)
	visible = false


## contribution — текст «вклад в этом бою», может быть пустым.
func show_tag(tag: String, at: Vector2, contribution: String = "") -> void:
	var d: Dictionary = ContentDB.data.combat_tags.get(tag, {})
	var cat := str(d.get("category", ""))
	var lines: Array[String] = []
	lines.append("[img=22x22]%s[/img] [font_size=22][b]%s[/b][/font_size]   [color=#9A9CA6]%s[/color]" % [TagText.icon_path(cat), tag, TagText.CATEGORY_NAMES.get(cat, cat)])
	lines.append(str(d.get("text", "")))
	var v := float(d.get("value", 0.0))
	if absf(v) > 0.001:
		lines.append("[color=#9A9CA6]Базовый вклад: %+d%%[/color]" % int(round(v * 100)))
	if contribution != "":
		lines.append("[color=#C9CED6]%s[/color]" % contribution)
	var known: Array = []
	var hidden := 0
	for l: Dictionary in TagText.links_of(tag):
		if ProfileService.is_known(l["id"]):
			var sign := "✦" if l["type"] == "synergy" else "✖"
			var col := "#C9CED6" if l["type"] == "synergy" else "#B65F63"
			known.append("[color=%s]%s %s[/color] — %s" % [col, sign, l["other"], l["name"]])
		else:
			hidden += 1
	if not known.is_empty() or hidden > 0:
		lines.append("")
		lines.append("[b]Связи[/b]  [color=#9A9CA6](Shift — сетка)[/color]")
		for k: String in known.slice(0, 8):
			lines.append(k)
		if hidden > 0:
			lines.append("[color=#6A6C76]??? ×%d — откроются в бою[/color]" % hidden)
	_label.text = "\n".join(lines)
	visible = true
	await get_tree().process_frame
	size = get_combined_minimum_size()
	var vp := get_viewport_rect().size
	global_position = Vector2(clampf(at.x + 18, 8, vp.x - size.x - 8), clampf(at.y + 18, 8, vp.y - size.y - 8))
