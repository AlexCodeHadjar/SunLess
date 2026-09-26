class_name PanicRules
extends RefCounted
## Паника героя (docs/16 §7): шкала 0–100 в characters[cid].panic. Растёт от угрозы, провалов этапов, травм
## и гибели товарищей; спадает, пока герой не на миссии. Реакция на сильную панику зависит от тегов:
## Трус сбегает с этапа, Гордыня не даёт отступить, Решимость на пределе даёт +2 Воли, Ярость — +10% в бою,
## остальные при 80+ получают −1 ко всем проверкам. Хладнокровие — паника растёт вдвое медленнее.

const MAX := 100
const REACT := 60          # с этого уровня срабатывают реакции тегов
const BREAK := 80          # без особых тегов: −1 ко всем проверкам
const GAIN_FAIL := 20
const GAIN_PARTIAL := 8
const GAIN_TRAUMA := 25
const GAIN_DEATH := 40
const GAIN_THREAT := 5     # за каждую единицу угрозы сверх двух — при прибытии
const DECAY := 0.5         # в секунду, пока герой не на миссии
const RAGE_COMBAT := 0.10


static func value(state: RunState, cid: String) -> int:
	return int(state.character(cid).get("panic", 0))


static func word(v: int) -> String:
	if v >= BREAK:
		return "на грани"
	if v >= REACT:
		return "в панике"
	if v >= 30:
		return "встревожен"
	return "спокоен"


## Добавить панику (с учётом Хладнокровия). Возвращает запись для отчёта при пересечении порога.
static func add(content: Content, state: RunState, cid: String, amount: int, reason: String) -> Array:
	var ch := state.character(cid)
	if ch.is_empty() or not state.is_alive(cid) or amount == 0:
		return []
	var tags := MissionFlow.hero_tags(content, state, cid)
	if amount > 0 and tags.has("Хладнокровие"):
		amount = int(ceil(amount / 2.0))
	var before := int(ch.get("panic", 0))
	var after := clampi(before + amount, 0, MAX)
	ch["panic"] = after
	if before < REACT and after >= REACT:
		return [{"kind": "panic", "card": cid, "text": "%s в панике (%s)" % [content.card_name(cid), reason]}]
	return []


## Спад паники по часам — у тех, кто не на миссии.
static func decay(state: RunState, dt: float) -> void:
	for cid: String in state.characters:
		var ch: Dictionary = state.characters[cid]
		if int(ch.get("panic", 0)) > 0 and not MissionFlow.on_mission(state, cid):
			ch["panic"] = maxi(0, int(round(float(ch["panic"]) - DECAY * dt)))


## Сбежит ли герой перед этапом (Трус в панике).
static func flees(content: Content, state: RunState, cid: String) -> bool:
	return value(state, cid) >= REACT and MissionFlow.hero_tags(content, state, cid).has("Трус")


## Откажется ли отряд отступать (Гордыня в панике у кого-то из отряда): "" — нет, иначе имя.
static func refuses_retreat(content: Content, state: RunState, heroes: Array) -> String:
	for cid: String in heroes:
		if state.is_alive(cid) and value(state, cid) >= REACT and MissionFlow.hero_tags(content, state, cid).has("Гордыня"):
			return content.card_name(cid)
	return ""


## Модификаторы проверки от паники: [{source, stat, value}].
static func check_parts(content: Content, state: RunState, cid: String) -> Array:
	var v := value(state, cid)
	if v < REACT:
		return []
	var tags := MissionFlow.hero_tags(content, state, cid)
	if tags.has("Решимость"):
		return [{"source": "Решимость на пределе", "stat": "will", "value": 2}] if v >= MAX else []
	if v >= BREAK and not tags.has("Ярость") and not tags.has("Хладнокровие"):
		var out: Array = []
		for s: String in ["power", "will", "cunning"]:
			out.append({"source": "Паника", "stat": s, "value": -1})
		return out
	return []


## Прибавка в бою от Ярости в панике.
static func combat_bonus(content: Content, state: RunState, cid: String) -> float:
	if value(state, cid) >= REACT and MissionFlow.hero_tags(content, state, cid).has("Ярость"):
		return RAGE_COMBAT
	return 0.0


## Как герой ведёт себя в панике — по его тегам (для планшета и брифинга).
static func reaction(content: Content, state: RunState, cid: String) -> String:
	var tags := MissionFlow.hero_tags(content, state, cid)
	var out: Array = []
	if tags.has("Хладнокровие"):
		out.append("Хладнокровие: паника растёт вдвое медленнее")
	if tags.has("Трус"):
		out.append("Трус: с %d сбегает с этапа (доверие отряда −1)" % REACT)
	if tags.has("Гордыня"):
		out.append("Гордыня: с %d не даёт отряду отступить" % REACT)
	if tags.has("Ярость"):
		out.append("Ярость: с %d — +%d%% силы в бою" % [REACT, int(RAGE_COMBAT * 100)])
	if tags.has("Решимость"):
		out.append("Решимость: на пределе (%d) — +2 Воли" % MAX)
	if not tags.has("Решимость") and not tags.has("Ярость") and not tags.has("Хладнокровие"):
		out.append("с %d — −1 ко всем проверкам" % BREAK)
	return "; ".join(out)
