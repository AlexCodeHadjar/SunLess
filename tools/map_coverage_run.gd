extends RefCounted
## Какие картинки карт-планов реально появляются в игре и почему: бот проходит главы, после каждого шага карта
## (SleeperMap) синхронизируется — записываются облики мест (<место>_<облик>), точки угроз, метки, полосы дорог и роя.
## Запуск: tools/map_coverage.gd (грузит этот файл, когда автозагрузки уже есть).
## Итог: {глава: {runs, files {имя: прогонов}, why {имя: [причины]}, overlays {что: прогонов}}} — для коллажей.

const CHAPTERS := ["shore", "academy", "city", "tree", "dark_city"]


func run(tree: SceneTree) -> void:
	var out_path := "user://map_coverage.json"
	var runs := 12
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.substr(6)
		if a.begins_with("--runs="):
			runs = int(a.substr(7))
	var c := Content.load_from("res://data")
	var result := {}
	for chapter: String in CHAPTERS:
		var files := {}
		var whys := {}
		var overlays := {}
		for sd in runs:
			var seen := {}
			var s := MapStory.start(c, chapter, 4100 + sd * 23)
			var map := SleeperMap.make(MapRules.config(c, chapter), Rect2(0, 0, 1920, 1080))
			tree.root.add_child(map)
			for step in 3000:
				_collect(c, s, map, seen, whys, overlays)
				var r := AutoPlay.step(c, s)
				s = r["state"]
				if str(r["error"]) != "" or s.demo_complete or s.game_over or s.chapter != chapter:
					break
			_collect(c, s, map, seen, whys, overlays)
			map.free()
			for f: String in seen:
				files[f] = int(files.get(f, 0)) + 1
		var ov := {}
		for k: String in overlays:
			ov[k] = (overlays[k] as Dictionary).size()
		result[chapter] = {"runs": runs, "region": DayRules.region_of(c, chapter), "files": files, "why": whys, "overlays": ov}
		print("[coverage] %s: %d картинок встретилось" % [chapter, files.size()])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result, " "))
	f.close()


func _collect(c: Content, s: RunState, map: SleeperMap, seen: Dictionary, whys: Dictionary, overlays: Dictionary) -> void:
	if not MapRules.has_map(c, s.chapter):
		return
	map.sync(c, s, Atmosphere.sky(c, s))
	var run_id := s.rng_seed
	for lid: String in map._shown:
		var st := str(map._shown[lid])
		if st == "":
			continue
		var name := "%s_%s" % [lid, st]
		seen[name] = true
		var w := MapStory.why(c, s, lid, st)
		if w != "":
			var lst: Array = whys.get(name, [])
			var key := w.split(" «")[0] if w.begins_with("след") else w
			if not lst.any(func(x: String) -> bool: return x.begins_with(key)) and lst.size() < 4:
				lst.append(w)
			whys[name] = lst
	var th: Dictionary = map._info.get("threat", {})
	for p: Dictionary in th.get("points", []):
		seen[str(p["tex"])] = true
		if str(p.get("glow", "")) != "":
			seen[str(p["glow"])] = true
	for m: Dictionary in th.get("marks", []):
		for d: String in m.get("decals", []):
			seen[d] = true
	for rd: Dictionary in th.get("roads", []):
		seen[str(rd["tex"])] = true
	if not (th.get("swarms", []) as Array).is_empty() and str(th.get("strip", "")) != "":
		seen[str(th["strip"])] = true
	var tr: Dictionary = map._info.get("terrain", {})
	for k: String in ["zones", "movers", "rubble"]:
		if not (tr.get(k, []) as Array).is_empty():
			var d2: Dictionary = overlays.get(k, {})
			d2[run_id] = true
			overlays[k] = d2
	if not (map._info.get("water", []) as Array).is_empty():
		var d3: Dictionary = overlays.get("water_paths", {})
		d3[run_id] = true
		overlays["water_paths"] = d3
	if not (map._info.get("flooded", []) as Array).is_empty():
		var d4: Dictionary = overlays.get("flood", {})
		d4[run_id] = true
		overlays["flood"] = d4
	if not MapRules.emerged(s).is_empty():
		var d5: Dictionary = overlays.get("emerged", {})
		d5[run_id] = true
		overlays["emerged"] = d5
