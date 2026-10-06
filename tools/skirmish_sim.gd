extends SceneTree
## Симуляция «Схватки» (docs/24): бои ИИ против ИИ — победы, длина боя, грань и гибель героев.
##   "$G" --headless --path . -s res://tools/skirmish_sim.gd [-- --n=50]             — по составам (баланс Ф1–Ф3, Ф8)
##   "$G" --headless --path . -s res://tools/skirmish_sim.gd -- --enemies [--n=12]   — каждый враг со своим строем против
##     стандартного отряда Берега (Санни, Нефис, Касси, Кастер, без карт) → tools/editor/skirmish_stats.json
##     (редактор контента, вкладка «Сила» → «Схватка»)

const FIGHTS := [
	["Берег: 2 Падальщика", ["P01", "P02", "P03"], ["M03", "M03"]],
	["Берег: Щупальца", ["P01", "P02", "P03"], ["M09", "M12", "M12"]],
	["Берег: Центурион со свитой", ["P01", "P02", "P03", "P04"], ["M04", "M03", "M03"]],
	["Кошмар: 4 Личинки", ["P02", "P04"], ["M01", "M01", "M01", "M01"]],
	["Багровый Отшельник", ["P01", "P02", "P03", "P04"], ["MW1"]],
	["Мрачный город: Скелеты", ["P01", "P02", "P03"], ["M27", "M27", "M27"]],
	["Санни один на один", ["P01"], ["M03"]],
	["Горный Король", ["P02", "P03", "P04"], ["M02", "M01"]],
]
const PARTY := ["P01", "P02", "P03", "P04"]
const OUT := "res://tools/editor/skirmish_stats.json"


func _init() -> void:
	var n := 50
	var per_enemy := false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--n="):
			n = int(a.substr(4))
		elif a == "--enemies":
			per_enemy = true
	var c := Content.load_from()
	var errors := _enemies(c, n if n != 50 else 12) if per_enemy else _fights(c, n)
	quit(1 if errors > 0 else 0)


func _state(c: Content, seed_value: int) -> RunState:
	var s := MissionFlow.new_run(c, seed_value, "shore")
	for cid: String in ["P02", "P03", "P04"]:
		EffectApplier.add_card(c, s, cid)
	return s


## Один бой: {out, rounds, edges, deaths, errors}.
func _fight(c: Content, s: RunState, heroes: Array, enemies: Array, light: String, pack: bool) -> Dictionary:
	var sk := Skirmish.create(c, s, {"heroes": heroes, "enemies": enemies, "light": light, "pack": pack,
		"mirror": "P01" if enemies.any(func(x: String) -> bool: return x.begins_with("MT")) else ""})
	var out := sk.auto(900)
	var r := {"out": out, "rounds": sk.round_no, "edges": 0, "deaths": 0, "errors": 0}
	for e: Dictionary in sk.log:
		match str(e.get("kind", "")):
			"death":
				r["deaths"] += 1
			"edge":
				r["edges"] += 1
			"error":
				r["errors"] += 1
	return r


func _fights(c: Content, n: int) -> int:
	var total := 0
	var errors := 0
	for fi: Array in FIGHTS:
		var wins := 0
		var rounds := 0
		var deaths := 0
		var edges := 0
		for i in n:
			var r := _fight(c, _state(c, 1000 + i), fi[1], fi[2], ["bright", "dim", "dusk", "dark"][i % 4], false)
			wins += 1 if r["out"] == "win" else 0
			rounds += int(r["rounds"])
			deaths += int(r["deaths"])
			edges += int(r["edges"])
			errors += int(r["errors"])
			total += 1
		print("%-28s побед %3d%%  раундов %4.1f  грань %4.2f  гибель %4.2f на бой" % [fi[0], int(100.0 * wins / n),
			float(rounds) / n, float(edges) / n, float(deaths) / n])
	print("боёв: %d, ошибок ИИ: %d" % [total, errors])
	return errors


## Каждый враг со своим строем (SkPack) — параметры и итоги для редактора.
func _enemies(c: Content, n: int) -> int:
	var rows: Array = []
	var errors := 0
	var ids: Array = c.enemies.keys()
	ids.sort()
	for eid: String in ids:
		var f := SkBuild.enemy(c, eid)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var line := SkPack.fill(c, [eid], rng)
		var wins := 0
		var rounds := 0
		var deaths := 0
		var edges := 0
		for i in n:
			var r := _fight(c, _state(c, 3000 + i), PARTY, [eid], ["bright", "dim", "dusk", "dark"][i % 4], true)
			wins += 1 if r["out"] == "win" else 0
			rounds += int(r["rounds"])
			deaths += int(r["deaths"])
			edges += int(r["edges"])
			errors += int(r["errors"])
		var e: Dictionary = c.enemies[eid]
		rows.append({"id": eid, "name": f.name, "kind": str(e.get("kind", "normal")), "rank": f.rank, "size": f.size,
			"actions": f.actions, "hp": f.hp_max, "speed": f.speed, "dodge": f.dodge, "prot": snappedf(f.prot, 0.01),
			"dmg": [int(floor(float(f.dmg[0]) * f.dmg_mult)), int(floor(float(f.dmg[1]) * f.dmg_mult))],
			"skills": f.skills.filter(func(x: Dictionary) -> bool: return not str(x.get("kind", "")) in ["step", "pass"]).map(
				func(x: Dictionary) -> String: return str(x.get("name", x["id"]))),
			"line": line, "win": snappedf(float(wins) / n, 0.01), "rounds": snappedf(float(rounds) / n, 0.1),
			"edges": snappedf(float(edges) / n, 0.01), "deaths": snappedf(float(deaths) / n, 0.01)})
		print("%-6s %-36s побед %3d%%  раундов %4.1f  гибель %4.2f" % [eid, f.name, int(100.0 * wins / n), float(rounds) / n, float(deaths) / n])
	var data := {"generated": Time.get_datetime_string_from_system(), "fights": n, "party": PARTY, "enemies": rows}
	var fa := FileAccess.open(OUT, FileAccess.WRITE)
	fa.store_string(JSON.stringify(data, "\t") + "\n")
	fa.close()
	print("врагов: %d, ошибок ИИ: %d → %s" % [rows.size(), errors, OUT])
	return errors
