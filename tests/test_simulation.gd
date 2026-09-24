extends TestCase
## 300 прохождений среза ботом: игра никогда не застревает; печатает сводку для баланса.

const RUNS := 300


func test_slice_never_stuck() -> void:
	var c := content()
	var done := 0
	var dead := 0
	var weeks: Array = []
	var max_tr: Array = []
	for i in RUNS:
		var r := SimBot.play(c, 1000 + i)
		check(not r["stuck"], "застрял (seed %d)" % (1000 + i))
		check(r["done"] or r["dead"], "не дошёл до конца за лимит ходов (seed %d)" % (1000 + i))
		if r["done"]:
			done += 1
			weeks.append(r["weeks"])
		if r["dead"]:
			dead += 1
		max_tr.append(r["max_traumas"])
	weeks.sort()
	var avg := 0.0
	for w: int in weeks:
		avg += w
	avg = avg / maxf(1.0, weeks.size())
	var avg_tr := 0.0
	for t: int in max_tr:
		avg_tr += t
	avg_tr /= float(RUNS)
	print("   [симуляция] прохождений: %d, пройдено: %d, смерть Санни: %d (%.0f%%)" % [RUNS, done, dead, 100.0 * dead / RUNS])
	if not weeks.is_empty():
		print("   [симуляция] недель до конца: среднее %.1f, медиана %d, мин %d, макс %d" % [avg, weeks[weeks.size() / 2], weeks[0], weeks[-1]])
	print("   [симуляция] максимум травм за прохождение в среднем: %.1f" % avg_tr)
