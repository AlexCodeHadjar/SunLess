extends SceneTree
## Запуск: Godot --headless --path . -s res://tests/run_tests.gd
## Код выхода 0 — все тесты прошли.

const SUITES := [
	"res://tests/test_rules.gd",
	"res://tests/test_content.gd",
	"res://tests/test_combat.gd",
	"res://tests/test_missions.gd",
	"res://tests/test_mission_core.gd",
	"res://tests/test_heroes_shop.gd",
	"res://tests/test_atmosphere.gd",
	"res://tests/test_mission_depth.gd",
	"res://tests/test_squad_life.gd",
	"res://tests/test_growth.gd",
	"res://tests/test_services.gd",
	"res://tests/test_camp.gd",
	"res://tests/test_journal.gd",
	"res://tests/test_onslaught.gd",
	"res://tests/test_tutorial.gd",
	"res://tests/test_shore.gd",
	"res://tests/test_psyche.gd",
	"res://tests/test_memory.gd",
	"res://tests/test_dev.gd",
	"res://tests/test_story.gd",
	"res://tests/test_edge.gd",
	"res://tests/test_strikes.gd",
	"res://tests/test_academy_fights.gd",
	"res://tests/test_tide.gd",
	"res://tests/test_modifiers.gd",
	"res://tests/test_loot.gd",
	"res://tests/test_deck.gd",
	"res://tests/test_map.gd",
	"res://tests/test_travel.gd",
	"res://tests/test_gates.gd",
	"res://tests/test_chapter4.gd",
	"res://tests/test_figure.gd",
	"res://tests/test_shore_events.gd",
]


func _initialize() -> void:
	var total := 0
	var failed: Array[String] = []
	# --only=<часть имени набора> — только эти наборы (быстрая проверка одной механики)
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7)
	for path: String in SUITES:
		if only != "" and not path.contains(only):
			continue
		var suite: TestCase = load(path).new()
		for m: Dictionary in suite.get_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			total += 1
			suite.current = "%s::%s" % [path.get_file().get_basename(), name]
			var before := suite.failures.size()
			suite.call(name)
			var status := "OK  " if suite.failures.size() == before else "FAIL"
			print("%s %s" % [status, suite.current])
		failed.append_array(suite.failures)
	print("")
	for f in failed:
		print("  ✗ " + f)
	print("Тестов: %d, провалов: %d" % [total, failed.size()])
	quit(0 if failed.is_empty() else 1)
