class_name SkirmishRules
extends RefCounted
## «Схватка» в мире игры (docs/24 §8, Ф5): переключатель режима боя, свет от неба и поля, засада, состав боя
## для этапа события, бой ИИ за обе стороны (бот, тесты), итог этапа (исход, грань, добыча, осколки), ночное
## лечение ран. Резолвер (MissionResolver) с включённой «Схваткой» на боевом этапе встаёт на паузу — игрок играет
## бой на экране (SkirmishScreen), итог возвращается через MissionResolver.resume_combat.
##
## Режим: state.flags.combat ("skirmish" | "clash"), иначе data/days.json → combat; по умолчанию — «Столкновение»
## (автобой), пока «Схватка» не готова целиком (решение владельца: заменить после готовности).

const NIGHT_HEAL := 0.5       # ночь в лагере: +половина здоровья
const LIGHTS := ["bright", "dim", "dusk", "dark"]
const DARK_FIELD := ["Тьма", "Эхо звука"]          # пещеры, тоннели, соборы — на ступень темнее
const BRIGHT_FIELD := ["Свет", "Святость"]
const AMBUSH_TAGS := ["Засада", "Скрытность", "Подземный"]
const ALERT_TAGS := ["Чутьё", "Многоглазый"]


static func enabled(content: Content, state: RunState) -> bool:
	var m := str(state.flags.get("combat", content.days.get("combat", "clash")))
	return m == "skirmish"


## Свет боя (docs/24 §4.10): небо и половина дня, поле сдвигает на ступень.
static func light(content: Content, state: RunState, field: String) -> String:
	var i := 0
	match Atmosphere.sky(content, state):
		"day":
			var ph := str(DayRules.phase(content, state).get("id", "day"))
			i = 1 if ph == "dawn" or FigureRules.half(state) == 1 else 0
		"night", "storm":
			i = 2
		"eclipse", "blood_moon":
			i = 3
		_:
			i = 1
	var tags: Array = content.fields.get(field, {}).get("tags", [])
	if tags.any(func(t: String) -> bool: return DARK_FIELD.has(t)):
		i += 1
	if tags.any(func(t: String) -> bool: return BRIGHT_FIELD.has(t)):
		i -= 1
	return LIGHTS[clampi(i, 0, 3)]


## Засада (docs/24 §4.11): "" | heroes (отряд застигнут) | enemies (враги застигнуты).
static func ambush(content: Content, state: RunState, heroes: Array, enemies: Array, lt: String, st: Dictionary,
		rng: RandomNumberGenerator) -> String:
	var forced := str(st.get("combat", {}).get("ambush", ""))
	if forced == "enemy" or forced == "enemies":
		return "enemies"
	if forced == "heroes":
		return "heroes"
	var htags := MissionFlow.squad_tags(content, state, heroes)
	var etags: Array = []
	for eid: String in enemies:
		etags.append_array(content.enemies.get(eid, {}).get("tags", []))
	var on_heroes: int = 10 + {"bright": 0, "dim": 0, "dusk": 10, "dark": 20}[lt]
	if etags.any(func(t: String) -> bool: return AMBUSH_TAGS.has(t)):
		on_heroes += 15
	if htags.any(func(t: String) -> bool: return ALERT_TAGS.has(t)):
		on_heroes -= 15
	var on_enemies := 10 + (15 if lt == "bright" else 0)
	if heroes.size() > 0 and MissionFlow.hero_tags(content, state, str(heroes[0])).any(func(t: String) -> bool: return t in ["Скрытность", "Тень"]):
		on_enemies += 15
	var r := rng.randi_range(1, 100)
	if r <= on_heroes:
		return "heroes"
	if r <= on_heroes + on_enemies:
		return "enemies"
	return ""


## Состав боя этапа: строй — порядок героев отряда; враги — этапа или миссии, строй добирается (SkPack).
static func stage_spec(content: Content, state: RunState, m: Dictionary, st: Dictionary, heroes: Array,
		rng: RandomNumberGenerator) -> Dictionary:
	var c: Dictionary = st.get("combat", {})
	var enemies: Array = c.get("enemies", m.get("enemies", []))
	var field := str(c.get("field", m.get("field", "")))
	var lt := light(content, state, field)
	var boss := enemies.any(func(e: String) -> bool: return str(content.enemies.get(e, {}).get("kind", "")) == "boss")
	return {"heroes": heroes.duplicate(), "enemies": enemies.duplicate(), "field": field, "light": lt, "pack": true,
		"power": float(c.get("power", 1.0)), "spar": bool(c.get("spar", false)),
		"ambush": ambush(content, state, heroes, enemies, lt, st, rng),
		"no_retreat": boss and bool(m.get("story", false)) or bool(c.get("no_retreat", false)),
		"mirror": str(m.get("trial", "")), "key": str(m.get("id", ""))}


## Бой ИИ за обе стороны (бот, тесты, не-интерактивный резолвер). Итог — как у экрана: summary(sk, sk.finish()).
static func auto(content: Content, state: RunState, spec: Dictionary) -> Dictionary:
	var sk := Skirmish.create(content, state, spec)
	sk.auto(900)
	return summary(sk, sk.finish())


## Сводка боя для резолвера: {outcome, state, rounds, entries, edge: [герои, упавшие на грань], dead: [...], enemies}.
static func summary(sk: Skirmish, fin: Dictionary) -> Dictionary:
	var edge: Array = []
	var dead: Array = []
	for e: Dictionary in sk.log:
		var f := sk.by_uid(str(e.get("who", "")))
		if f == null or not f.is_hero():
			continue
		if str(e.get("kind", "")) == "edge" and not edge.has(f.card):
			edge.append(f.card)
		elif str(e.get("kind", "")) == "death" and not dead.has(f.card):
			dead.append(f.card)
	var foes: Array = sk.fighters.filter(func(f: SkFighter) -> bool: return f.side == "enemy").map(func(f: SkFighter) -> String: return f.card)
	return {"outcome": str(fin["outcome"]), "state": fin["state"], "rounds": int(fin["rounds"]), "entries": fin["entries"],
		"edge": edge, "dead": dead, "enemies": foes}


## Ночь в лагере: раны затягиваются — +половина здоровья (у кого записано неполное).
static func night_heal(content: Content, state: RunState) -> void:
	for cid: String in MissionFlow.heroes(content, state):
		var ch := state.character(cid)
		if not ch.has("hp"):
			continue
		var mx := SkBuild.hero(content, state, cid).hp_max
		var hp := int(ch["hp"]) + int(ceil(mx * NIGHT_HEAL))
		if hp >= mx:
			ch.erase("hp")
		else:
			ch["hp"] = hp
	state.flags.erase("echo_hp")   # Эхо тоже восстанавливается в лагере
