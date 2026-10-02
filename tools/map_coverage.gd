extends SceneTree
## Какие картинки карт-планов реально появляются в игре и почему (tools/map_coverage_run.gd).
## Godot --headless --path . -s res://tools/map_coverage.gd -- --out=<файл.json> [--runs=12]
## Логика — в отдельном файле и запускается на первом кадре: тогда автозагрузки уже есть и карта (SleeperMap) собирается.

var _done := false


func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		load("res://tools/map_coverage_run.gd").new().run(self)
	return true
