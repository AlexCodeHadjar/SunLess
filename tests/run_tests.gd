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
]


func _initialize() -> void:
	var total := 0
	var failed: Array[String] = []
	for path: String in SUITES:
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
