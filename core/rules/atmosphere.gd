class_name Atmosphere
extends RefCounted
## Небо над картой главы (фон, docs/15 §19). Небо задаёт фаза недели (DayRules, docs/16 §12);
## сюжет поверх этого зажигает кровавую луну, шторм или затмение — пока открыта миссия с полем `sky`.
## Затмение сильнее луны, луна — шторма (шторм — небо Забытого Берега: прилив, ливень, молнии). Небо влияет на миссии (docs/16 §4): ночью легче скрываться, днём — выживать и
## выслеживать, под кровавой луной враги злее, но добыча богаче, в затмение сильнее Тень.

const NIGHT_ENEMY := 0.10    # ночь: твари сильнее в бою
const BLOOD_ENEMY := 0.20    # кровавая луна: враг сильнее в бою
const BLOOD_MEMORY := 2.0    # …и Воспоминания выпадают вдвое чаще
const BLOOD_LOOT := 1.5      # …но осколков с него больше
const ECLIPSE_SHADOW := 0.10 # затмение: герой с Тенью сильнее в бою
## Бонусы проверок: небо -> [{tags (любой из тегов проверки), stat, value}]
const CHECK_BONUS := {
	"night": [{"tags": ["stealth"], "stat": "cunning", "value": 1}],
	"day": [{"tags": ["survival", "chase", "climb"], "stat": "cunning", "value": 1}],
	"eclipse": [{"tags": ["ritual", "stealth"], "stat": "will", "value": 1}],
	"blood_moon": [],
	"storm": [{"tags": ["climb", "chase"], "stat": "cunning", "value": -1}, {"tags": ["weather", "survival"], "stat": "will", "value": -1}],
}
## Коротко для брифинга: чем небо поможет или помешает.
const HINTS := {
	"night": "Ночь: скрытность +1 Хитрость; твари в бою +10%",
	"day": "День: выживание, погоня и подъём +1 Хитрость",
	"eclipse": "Затмение: ритуалы и скрытность +1 Воля; Тень в бою +10%",
	"blood_moon": "Кровавая луна: враги +20% в бою, психика −5 за выход; Воспоминания вдвое чаще, осколков ×1.5",
	"storm": "Шторм: подъём и погоня −1 Хитрость, непогода и выживание −1 Воля",
}
const NAMES := {"night": "Ночь", "day": "День", "eclipse": "Затмение", "blood_moon": "Кровавая луна", "storm": "Шторм"}
## Предзнаменование, когда сюжет меняет небо.
const OMENS := {
	"blood_moon": "Над перевалом восходит кровавая луна. Смерть ходит рядом.",
	"eclipse": "Солнце гаснет. Над горами — затмение: Кошмар близится к концу.",
	"storm": "С моря идёт шторм. Вода поднимается — ищите высоту.",
}
## Для живой карты (MapLife): какое время суток изображает небо.
const TOD := {"night": 0.0, "day": 0.5, "eclipse": 0.0, "blood_moon": 0.0, "storm": 0.75}


static func sky(content: Content, state: RunState) -> String:
	var omen := story_sky(content, state)
	if omen != "":
		return omen
	return str(DayRules.phase(content, state).get("sky", "day"))


## Небо, которое задаёт сюжет: открытая или идущая миссия текущей главы с полем `sky`
## (у босса в несколько заходов — небо текущего захода).
static func story_sky(content: Content, state: RunState) -> String:
	var best := ""
	for mid: String in state.missions:
		if not str(state.missions[mid].get("status", "")) in ["open", "active"]:
			continue
		if MissionFlow.chapter_of(content, mid) != state.chapter:
			continue
		var m: Dictionary = content.missions.get(mid, {})
		var s := str(m.get("sky", ""))
		var phases: Array = m.get("boss", {}).get("phases", [])
		if not phases.is_empty():
			var ph: Dictionary = phases[clampi(int(state.missions[mid].get("phase", 0)), 0, phases.size() - 1)]
			s = str(ph.get("sky", s))
		if s == "eclipse":
			return s
		if s == "blood_moon":
			best = s
		elif s == "storm" and best == "":
			best = s
	return best


## Бонус неба к проверке с тегами tags: [{source, stat, value}] для StatResolver.
static func check_parts(content: Content, state: RunState, tags: Array) -> Array:
	if state == null or content == null:
		return []
	var sk := sky(content, state)
	var out: Array = []
	for b: Dictionary in CHECK_BONUS.get(sk, []):
		for t: String in b["tags"]:
			if tags.has(t):
				out.append({"source": "Небо: %s" % str(NAMES.get(sk, sk)).to_lower(), "stat": b["stat"], "value": int(b["value"])})
				break
	return out
