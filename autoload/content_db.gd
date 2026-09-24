extends Node
## Загружает и проверяет данные при старте.

var data: Content
var errors: Array[String] = []


func _ready() -> void:
	reload()


func reload() -> void:
	data = Content.load_from("res://data")
	errors = ContentValidator.validate(data)
	for e in errors:
		push_error("[ContentDB] " + e)
