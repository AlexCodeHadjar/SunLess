class_name Palette
extends RefCounted
## Цвета интерфейса (docs/11 — Визуальная спецификация, §1).

const BG_DEEP := Color("#0E0F14")
const BG_PANEL := Color("#171922")
const BG_RAISED := Color("#222532")
const LINE := Color("#3A3E4E")
const TEXT := Color("#E6E1D6")
const TEXT_DIM := Color("#9A9CA6")
const SILVER := Color("#C9CED6")
const GOLD := Color("#B89A5E")
const MANA := Color("#6F8FD8")
const COINS := Color("#B9A7E6")  # осколки душ
const TRAUMA := Color("#6E1E26")
const TRAUMA_BRIGHT := Color("#B0303C")
const INITIATOR := Color("#5B4A7A")
const REQ_MET := Color("#6FA9C9")
const REQ_MISS := Color("#C79A4B")
const STAT_UP := Color("#6FA47B")
const STAT_DOWN := Color("#B65F63")
const STAT_NEUTRAL := Color("#A8ADB4")

const RARITY := {
	"common": Color("#8A8D96"),
	"rare": Color("#5E86B0"),
	"epic": Color("#8A6BB8"),
	"legendary": Color("#B89A5E"),
	"mythic": Color("#E8E8F0"),
}

const STAT_NAMES := {"power": "Сила", "will": "Воля", "cunning": "Хитрость"}
const STAT_SHORT := {"power": "С", "will": "В", "cunning": "Х"}


## Градиент шкалы шанса: тёмно-красный → зелёный → золотой (файл 02).
static func chance_color(chance: int, monochrome: bool = false) -> Color:
	var t := clampf(chance / 100.0, 0.0, 1.0)
	if monochrome:
		return Color("#4A4E5A").lerp(SILVER, t)
	var stops := [
		[0.0, Color("#6E1A20")], [0.30, Color("#9A4A2E")], [0.55, Color("#4F8F55")],
		[0.85, Color("#8FAE4A")], [0.99, Color("#C2AE42")], [1.0, Color("#E0B43C")],
	]
	for i in range(1, stops.size()):
		if t <= stops[i][0]:
			var a: Array = stops[i - 1]
			var b: Array = stops[i]
			return (a[1] as Color).lerp(b[1], (t - a[0]) / maxf(0.0001, b[0] - a[0]))
	return stops[-1][1]
