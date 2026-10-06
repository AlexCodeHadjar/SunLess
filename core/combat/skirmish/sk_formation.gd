class_name SkFormation
extends RefCounted
## Строй «Схватки» (docs/24 §4.1): позиции 1–4 у каждой стороны (1 — ближе к врагу), крупные занимают две.
## Строй смыкается: живые и трупы стоят подряд, без пропусков. Сдвиг — перестановка по порядку в строю.

const SIZE := 4


## Бойцы стороны в строю (живые и трупы) по порядку позиций.
static func line(fighters: Array, side: String) -> Array:
	var out: Array = fighters.filter(func(f: SkFighter) -> bool: return f.side == side and f.in_line())
	out.sort_custom(func(a: SkFighter, b: SkFighter) -> bool: return a.pos < b.pos)
	return out


## Сомкнуть строй: позиции подряд с 1 в нынешнем порядке.
static func relayout(fighters: Array, side: String) -> void:
	var p := 1
	for f: SkFighter in line(fighters, side):
		f.pos = p
		p += f.size


## Боец (живой или труп), занимающий позицию p, или null.
static func at(fighters: Array, side: String, p: int) -> SkFighter:
	for f: SkFighter in line(fighters, side):
		if f.occupies(p):
			return f
	return null


## Сдвинуть бойца на n мест в строю (n > 0 — назад, n < 0 — вперёд). Возвращает, на сколько сдвинулся.
static func move(fighters: Array, f: SkFighter, n: int) -> int:
	var arr := line(fighters, f.side)
	var i := arr.find(f)
	if i < 0 or n == 0:
		return 0
	var j := clampi(i + n, 0, arr.size() - 1)
	if j == i:
		return 0
	arr.remove_at(i)
	arr.insert(j, f)
	var p := 1
	for x: SkFighter in arr:
		x.pos = p
		p += x.size
	return j - i


## Поставить бойцов в строй по порядку списка (размеры учитываются); лишние, кому нет места, — вне строя.
static func place(order: Array) -> void:
	var p := 1
	for f: SkFighter in order:
		if p + f.size - 1 > SIZE:
			f.removed = true
			continue
		f.pos = p
		p += f.size
