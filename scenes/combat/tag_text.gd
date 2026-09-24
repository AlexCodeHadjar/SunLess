class_name TagText
extends RefCounted
## Теги как гиперссылки в RichTextLabel: иконка категории + подчёркнутое имя, meta «tag:Имя».

const CATEGORY_NAMES := {
	"element": "Стихия", "material": "Материал", "anatomy": "Анатомия", "tactic": "Тактика",
	"mystic": "Мистика", "mind": "Разум", "state": "Состояние", "origin": "Происхождение",
	"sense": "Чувства", "field": "Местность", "time": "Время и погода",
}
const CATEGORY_COLORS := {
	"element": "#D9975A", "material": "#B8B2A6", "anatomy": "#C98F8F", "tactic": "#C9CED6",
	"mystic": "#A99BE0", "mind": "#8FB6C9", "state": "#B65F63", "origin": "#B89A5E",
	"sense": "#9AC7A8", "field": "#8DA6BF", "time": "#C7C39A",
}


static func category(tag: String) -> String:
	return str(ContentDB.data.combat_tags.get(tag, {}).get("category", "state"))


static func icon_path(cat: String) -> String:
	return "res://art/ui/tags/%s.png" % cat


## BBCode одного тега-ссылки.
static func link(tag: String, size: int = 18) -> String:
	var cat := category(tag)
	var col: String = CATEGORY_COLORS.get(cat, "#C9CED6")
	return "[img=%dx%d]%s[/img][url=tag:%s][color=%s][u]%s[/u][/color][/url]" % [size, size, icon_path(cat), tag, col, tag]


static func links(tags: Array, sep: String = "  ", size: int = 18) -> String:
	var parts: Array = []
	for t: String in tags:
		parts.append(link(t, size))
	return sep.join(parts)


## Готовый RichTextLabel для строки тегов.
static func label(tags: Array, width: float, size: int = 17) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.custom_minimum_size = Vector2(width, 0)
	l.add_theme_font_size_override("normal_font_size", size)
	l.meta_underlined = false
	l.text = links(tags, "   ", size)
	return l


## Все связи тега: [{id, type, name, other, value, text}].
static func links_of(tag: String) -> Array:
	var c := ContentDB.data
	var out: Array = []
	for sid: String in c.synergies:
		var s: Dictionary = c.synergies[sid]
		if Array(s.get("tags", [])).has(tag):
			var others: Array = Array(s["tags"]).duplicate()
			others.erase(tag)
			out.append({"id": sid, "type": "synergy", "name": s.get("name", ""), "other": " + ".join(others),
				"value": float(s.get("value", 0.0)), "text": s.get("text", "")})
	for cid: String in c.conflicts:
		var k: Dictionary = c.conflicts[cid]
		if k.get("a", "") == tag or k.get("b", "") == tag:
			var other: String = k["b"] if k["a"] == tag else k["a"]
			var loser: String = k["a"] if k.get("loser", "b") == "a" else k["b"]
			out.append({"id": cid, "type": "conflict", "name": k.get("name", ""), "other": other,
				"value": float(k.get("value", 0.0)), "text": k.get("text", ""), "tag_loses": loser == tag})
	return out
