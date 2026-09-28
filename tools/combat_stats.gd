extends SceneTree
## Статистика боёв для редактора (вкладка «Сила»): Godot --headless --path . -s res://tools/combat_stats.gd
## Бот (AutoPlay) проходит игру несколько раз; когда открывается миссия с боем, берётся то, что у игрока есть
## в этот момент: живые герои и усиления. Для каждого состава отряда (все сочетания до мест миссии, ведущий —
## лучший, кармашки разложены как у игрока) считается честный шанс победы (Strikes.odds — как в прогнозе).
## Итог — tools/editor/combat_stats.json: по боям (миссия, действие, этап) и по противникам.

const SEEDS := 8
const OUT := "res://tools/editor/combat_stats.json"


func _initialize() -> void:
	var c := Content.load_from("res://data")
	var fights := {}
	for sd in SEEDS:
		var s := MissionFlow.new_run(c, 9100 + sd)
		var seen := {}
		var steps := 0
		while steps < 12000 and not s.game_over:
			steps += 1
			for mid: String in MissionFlow.open_missions(s):
				if seen.has(mid) or MissionFlow.chapter_of(c, mid) != s.chapter:
					continue
				seen[mid] = true
				_sample(c, s, mid, fights)
			var r := AutoPlay.step(c, s)
			s = r["state"]
			if str(r["error"]) != "" or bool(r.get("finished", false)):
				break
	var out := {"generated": Time.get_datetime_string_from_system(), "seeds": SEEDS, "fights": [], "enemies": {}}
	for key: String in fights:
		var f: Dictionary = fights[key]
		var best: Array = f["best"]
		var typical: Array = f["typical"]
		var solo: Array = f["solo"]
		var bare: Array = f["bare"]
		var row := {"key": key, "mission": f["mission"], "title": f["title"], "chapter": f["chapter"], "type": f["type"],
			"action": f["action"], "action_label": f["action_label"], "stage": f["stage"], "enemies": f["enemies"], "field": f["field"],
			"samples": best.size(), "best": _avg(best), "best_min": _min(best), "best_max": _max(best), "typical": _avg(typical),
			"solo": _avg(solo), "bare": _avg(bare), "team": f["team"], "heroes_seen": f["heroes_seen"], "enh_seen": f["enh_seen"]}
		out["fights"].append(row)
		for eid: String in f["enemies"]:
			var e: Dictionary = out["enemies"].get(eid, {"fights": [], "best": [], "typical": []})
			if not Array(e["fights"]).has(key):
				e["fights"].append(key)
			e["best"].append(row["best"])
			e["typical"].append(row["typical"])
			out["enemies"][eid] = e
	for eid: String in out["enemies"]:
		var e2: Dictionary = out["enemies"][eid]
		e2["best"] = _avg(e2["best"])
		e2["typical"] = _avg(e2["typical"])
	out["fights"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["key"]) < str(b["key"]))
	var fa := FileAccess.open(OUT, FileAccess.WRITE)
	fa.store_string(JSON.stringify(out, " "))
	fa.close()
	print("[combat_stats] боёв: %d, противников: %d → %s" % [out["fights"].size(), out["enemies"].size(), OUT])
	quit(0)


## Все бои миссии в текущем состоянии игрока: по каждому этапу-бою — шансы для всех составов отряда.
func _sample(c: Content, s: RunState, mid: String, fights: Dictionary) -> void:
	var m: Dictionary = c.missions[mid]
	var pool: Array = MissionFlow.heroes(c, s).filter(func(h: String) -> bool: return not MissionFlow.excluded(c, mid, h))
	var need: Array = Array(m.get("requires_heroes", [])).filter(func(h: String) -> bool: return pool.has(h))
	var mx := mini(int(m.get("squad", {}).get("max", 1)), pool.size())
	var teams := _teams(pool, need, maxi(1, mx))
	if teams.is_empty():
		return
	var enh := s.collection.filter(func(x: String) -> bool: return c.card_kind(x) == "enhancement").size()
	for a: Dictionary in m.get("actions", []):
		var stages: Array = a.get("stages", [])
		for i in stages.size():
			var st: Dictionary = MissionFlow.boss_stage(s, m, stages[i])
			if not st.has("combat"):
				continue
			var key := "%s/%s/%d" % [mid, a["id"], i]
			var f: Dictionary = fights.get(key, {"mission": mid, "title": str(m.get("title", mid)), "chapter": MissionFlow.chapter_of(c, mid),
				"type": str(m.get("type", "")), "action": str(a["id"]), "action_label": str(a.get("label", "")), "stage": str(st.get("name", "")),
				"enemies": Array(st["combat"].get("enemies", [])), "field": str(st["combat"].get("field", "")),
				"best": [], "typical": [], "solo": [], "bare": [], "team": [], "heroes_seen": [], "enh_seen": 0})
			var best := -1.0
			var best_team: Array = []
			var sum := 0.0
			var solo := 0.0
			for team: Array in teams:
				var s2 := s.copy()
				AutoPlay.equip(c, s2, team)
				var odds := float(MissionForecast.combat_setup(c, s2, m, a, st, team, true)["fight"])
				sum += odds
				if team.size() == 1:
					solo = maxf(solo, odds)
				if odds > best:
					best = odds
					best_team = team
			var s3 := s.copy()
			for cid: String in best_team:
				s3.character(cid)["pocket"] = []
			f["best"].append(best)
			f["typical"].append(sum / teams.size())
			f["solo"].append(solo)
			f["bare"].append(float(MissionForecast.combat_setup(c, s3, m, a, st, best_team, true)["fight"]))
			f["team"] = best_team
			f["heroes_seen"] = pool
			f["enh_seen"] = maxi(int(f["enh_seen"]), enh)
			fights[key] = f


## Все составы: обязательные герои + любые другие до max мест.
func _teams(pool: Array, need: Array, mx: int) -> Array:
	var rest: Array = pool.filter(func(h: String) -> bool: return not need.has(h))
	var out: Array = []
	var n := rest.size()
	for mask in range(0, 1 << n):
		var team: Array = need.duplicate()
		for i in n:
			if mask & (1 << i):
				team.append(rest[i])
		if not team.is_empty() and team.size() <= mx:
			out.append(team)
	return out


func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for x: float in a:
		t += x
	return snappedf(t / a.size(), 0.001)


func _min(a: Array) -> float:
	return snappedf(a.min(), 0.001) if not a.is_empty() else 0.0


func _max(a: Array) -> float:
	return snappedf(a.max(), 0.001) if not a.is_empty() else 0.0
