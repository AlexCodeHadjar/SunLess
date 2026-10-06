class_name SkFighter
extends RefCounted
## Боец «Схватки» (docs/24 §4): сторона, позиция в строю, размер, здоровье, параметры, теги, навыки, состояния.
## Параметры считает SkBuild; меняют бой Skirmish, SkStrike, SkStatus, SkFormation.

var uid := ""              # h0…, e0… — уникален в бою
var side := "hero"         # hero | enemy
var card := ""             # id героя / врага / карты Эха
var name := ""
var pos := 1               # передняя занятая позиция (1 — ближе всех к врагу)
var size := 1              # крупные — 2
var hp := 1
var hp_max := 1
var speed := 0
var acc := 0
var dodge := 0
var crit := 0
var prot := 0.0            # защита: доля урона, которую гасит броня
var res := {}              # сопротивления, %: bleed, poison, stun, move, debuff
var immune: Array = []     # состояния, которые не действуют (от тегов)
var dmg: Array = [1, 2]    # разброс урона оружия
var dmg_mult := 1.0
var rank := 0
var tags: Array = []
var skills: Array = []     # описания навыков (словари из skirmish.json)
var statuses: Array = []   # {type, turns, power?, stat?, value?, by?}
var cooldown := {}         # id навыка → сколько своих ходов ждать
var used := {}             # id навыка → сколько раз применён
var regen := 0
var first_strike := 0      # «Первый удар»: прибавка к скорости первого раунда
var no_corpse := false
var smart := false         # «Разумный»: ИИ выбирает лучшее
var pref: Array = [1, 2]   # любимые позиции (ИИ)
var edge := false          # герой на грани смерти (здоровье 0)
var dead := false
var corpse := false
var corpse_rounds := 0
var removed := false       # труп истлел или добит — бойца нет в строю
var echo := false
var owner := ""            # Эхо: герой-хозяин
var init := 0              # скорость раунда (для очереди)
var actions := 1           # ходов за раунд (крупные боссы — 2)
var phases: Array = []     # фазы босса: [{at, add, text}] (Ф3)
var phase_i := 0
var rage := false          # Ярость: каждый полученный удар — урон +10% (до +30%)
var flee := false          # бежит, когда ранен


## Стоит в строю и может действовать (не труп, не погиб).
func alive() -> bool:
	return not dead and not corpse and not removed


## Занимает место в строю (живой или труп).
func in_line() -> bool:
	return not dead and not removed


## Герой с психикой и гранью смерти (не Эхо).
func is_hero() -> bool:
	return side == "hero" and not echo


func occupies(p: int) -> bool:
	return p >= pos and p < pos + size


func positions() -> Array:
	var out: Array = []
	for i in size:
		out.append(pos + i)
	return out


func has_status(t: String) -> bool:
	return statuses.any(func(s: Dictionary) -> bool: return str(s["type"]) == t)


func status(t: String) -> Dictionary:
	for s: Dictionary in statuses:
		if str(s["type"]) == t:
			return s
	return {}


func skill(id: String) -> Dictionary:
	for s: Dictionary in skills:
		if str(s["id"]) == id:
			return s
	return {}
