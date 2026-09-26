class_name Atmosphere
extends RefCounted
## Небо над картой главы (фон, docs/15 §19). День и ночь сменяют друг друга по игровым часам;
## сюжет поверх этого зажигает кровавую луну или затмение — пока открыта миссия с полем `sky`.
## Затмение сильнее луны. Только атмосфера: на правила и шансы небо не влияет.

const DAY_CYCLE := 180.0   # игровых секунд: первая половина — ночь, вторая — день
const NAMES := {"night": "Ночь", "day": "День", "eclipse": "Затмение", "blood_moon": "Кровавая луна"}
## Предзнаменование, когда сюжет меняет небо.
const OMENS := {
	"blood_moon": "Над перевалом восходит кровавая луна. Смерть ходит рядом.",
	"eclipse": "Солнце гаснет. Над горами — затмение: Кошмар близится к концу.",
}
## Для живой карты (MapLife): какое время суток изображает небо.
const TOD := {"night": 0.0, "day": 0.5, "eclipse": 0.0, "blood_moon": 0.0}


static func sky(content: Content, state: RunState) -> String:
	var omen := story_sky(content, state)
	if omen != "":
		return omen
	return "day" if fposmod(state.clock, DAY_CYCLE) >= DAY_CYCLE / 2.0 else "night"


## Небо, которое задаёт сюжет: открытая или идущая миссия текущей главы с полем `sky`.
static func story_sky(content: Content, state: RunState) -> String:
	var best := ""
	for mid: String in state.missions:
		if not str(state.missions[mid].get("status", "")) in ["open", "active"]:
			continue
		if MissionFlow.chapter_of(content, mid) != state.chapter:
			continue
		var s := str(content.missions.get(mid, {}).get("sky", ""))
		if s == "eclipse":
			return s
		if s == "blood_moon":
			best = s
	return best
