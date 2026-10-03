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
const COINS := Color("#B9A7E6")  # осколки душ
const REST := Color("#6F8FD8")   # отдых героев
const TRAUMA := Color("#6E1E26")
const TRAUMA_BRIGHT := Color("#B0303C")
const REQ_MET := Color("#6FA9C9")
const REQ_MISS := Color("#C79A4B")
const STAT_UP := Color("#6FA47B")
const STAT_DOWN := Color("#B65F63")
const STAT_NEUTRAL := Color("#A8ADB4")
## модификаторы миссий (ModifierRules): тон значка
const MOD_TONE := {"bad": Color("#C0666A"), "good": Color("#7DB38A"), "mixed": Color("#D2A95A")}

const RARITY := {
	"common": Color("#8A8D96"),
	"rare": Color("#5E86B0"),
	"epic": Color("#8A6BB8"),
	"legendary": Color("#B89A5E"),
	"mythic": Color("#E8E8F0"),
}

const STAT_NAMES := {"power": "Сила", "will": "Воля", "cunning": "Хитрость"}
const STAT_SHORT := {"power": "С", "will": "В", "cunning": "Х"}

