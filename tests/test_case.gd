class_name TestCase
extends RefCounted
## Минимальный каркас тестов без сторонних аддонов.

var failures: Array[String] = []
var current := ""


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("%s: %s" % [current, msg])


func eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if actual != expected:
		failures.append("%s: %s ожидалось %s, получено %s" % [current, msg, str(expected), str(actual)])


func content() -> Content:
	return Content.load_from("res://data")
