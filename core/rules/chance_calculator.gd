class_name ChanceCalculator
extends RefCounted
## Формула шанса (файл 02, GDD 4.8). Одна функция и для показа, и для броска.

const STATS: Array[String] = ["power", "will", "cunning"]


## totals, req: {"power": int, "will": int, "cunning": int}; отсутствующие ключи = 0.
## Участвуют только характеристики с требованием > 0. Возвращает целое 0..100.
static func compute(totals: Dictionary, req: Dictionary) -> int:
	var sum_req := 0
	var base := 0
	var excess := 0
	var all_met := true
	for s in STATS:
		var r := int(req.get(s, 0))
		if r <= 0:
			continue
		var v := maxi(0, int(totals.get(s, 0)))
		sum_req += r
		base += mini(v, r)
		excess += maxi(v - r, 0)
		if v < r:
			all_met = false
	if sum_req == 0 or all_met:
		return 100
	var exact := (float(base) + float(excess) / 8.0) / float(sum_req) * 100.0
	# Эпсилон защищает от 94.99999 вместо 95 из-за двоичной арифметики.
	return clampi(int(floor(exact + 0.000001)), 0, 100)


static func label(chance: int) -> String:
	if chance <= 0:
		return "Невозможно"
	if chance < 20:
		return "Очень низкий"
	if chance < 45:
		return "Низкий"
	if chance < 70:
		return "Средний"
	if chance < 90:
		return "Высокий"
	if chance < 100:
		return "Почти гарантированный"
	return "Гарантировано"
