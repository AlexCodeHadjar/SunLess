extends SceneTree
## Симуляция «Схватки» (docs/24): бои ИИ против ИИ по составам — победы, длина боя, гибель и грань героев.
## Для баланса фаз Ф1–Ф3 и Ф8.
##   "$G" --headless --path . -s res://tools/skirmish_sim.gd [-- --n=50]

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


func _init() -> void:
	var n := 50
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--n="):
			n = int(a.substr(4))
	var c := Content.load_from()
	var total := 0
	var errors := 0
	for fi: Array in FIGHTS:
		var st := {"win": 0, "loss": 0, "retreat": 0}
		var rounds := 0
		var deaths := 0
		var edges := 0
		for i in n:
			var s := MissionFlow.new_run(c, 1000 + i, "shore")
			for cid: String in ["P02", "P03", "P04"]:
				EffectApplier.add_card(c, s, cid)
			var sk := Skirmish.create(c, s, {"heroes": fi[1], "enemies": fi[2], "light": ["bright", "dim", "dusk", "dark"][i % 4]})
			var out := sk.auto(800)
			st[out] = int(st.get(out, 0)) + 1
			rounds += sk.round_no
			for e: Dictionary in sk.log:
				match str(e.get("kind", "")):
					"death":
						deaths += 1
					"edge":
						edges += 1
					"error":
						errors += 1
			total += 1
		print("%-28s побед %3d%%  раундов %4.1f  грань %4.2f  гибель %4.2f на бой" % [fi[0], int(100.0 * st["win"] / n),
			float(rounds) / n, float(edges) / n, float(deaths) / n])
	print("боёв: %d, ошибок ИИ: %d" % [total, errors])
	quit(1 if errors > 0 else 0)
