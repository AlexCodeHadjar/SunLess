extends SceneTree
## Калибровка ударов (docs/16 §9е п.7): Godot --headless --path . -s res://tools/strike_calib.gd
## Для разных пар «отряд — противник»: перевес сил r = H/E, доля побед в автобое, оценка прогноза (Strikes.odds)
## и для сравнения — прежний бросок «2 из 3» при шансе раунда H/(H+E).

const N := 150


func _old(r: float) -> float:
	var p := clampf(r / (1.0 + r), 0.05, 0.95)
	return p * p * (3.0 - 2.0 * p)


func _initialize() -> void:
	var c := Content.load_from("res://data")
	var rows: Array = []
	var squads := [["P01", []], ["P02", []], ["P04", ["P01"]], ["P02", ["P03", "P04"]]]
	var fields := ["F_05", "F_08", "F_03"]
	for eid: String in c.enemies:
		for sq: Array in squads:
			var s := MissionFlow.new_run(c, 7)
			s.chapter = "academy"
			for h: String in [sq[0]] + sq[1]:
				if not s.owns(h):
					EffectApplier.add_card(c, s, h)
			var spec := {"enemies": [eid], "field": fields[rows.size() % fields.size()]}
			var probe := CombatSession.create_for_mission(c, s, "T", spec, sq[0], [], sq[1], {"id": "T", "tags": ["combat"]}, {"id": "T_a", "tags": []})
			probe.round_no = 1
			var led := probe.ledger({})
			var r := float(led["hero"]) / maxf(1.0, float(led["enemy"]))
			if r < 0.3 or r > 3.0:
				continue
			var odds := probe.fight_odds(led)
			var wins := 0
			for i in N:
				var s2 := s.copy()
				s2.rng_seed = 1000 + i
				s2.rng_state = 104729 * (i + 1)
				var cs := CombatSession.create_for_mission(c, s2, "T", spec, sq[0], [], sq[1], {"id": "T", "tags": ["combat"]}, {"id": "T_a", "tags": []})
				cs.auto_play()
				if cs.outcome == "win":
					wins += 1
			rows.append([r, 100.0 * wins / N, 100.0 * odds, 100.0 * _old(r), "%s+%d vs %s" % [sq[0], (sq[1] as Array).size(), eid]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var err := 0.0
	var bias := 0.0
	for row: Array in rows:
		print("r=%.2f  побед %5.1f%%  прогноз %5.1f%%  прежде %5.1f%%   %s" % row)
		err += absf(float(row[1]) - float(row[2]))
		bias += float(row[1]) - float(row[2])
	print("пар: %d, средняя ошибка прогноза %.1f п., смещение %+.1f п." % [rows.size(), err / maxf(1, rows.size()), bias / maxf(1, rows.size())])
	quit(0)
