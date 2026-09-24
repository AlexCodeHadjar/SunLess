extends Node
## Настройки игрока в user://settings.cfg (ConfigFile). Применяются сразу.

const PATH := "user://settings.cfg"

var values := {
	"fullscreen": false,
	"roll_speed": 1.0,        # 1.0 обычная, 0.35 быстрая, 0.0 без анимации
	"reduce_motion": false,
	"chance_monochrome": false,
	"tutorial": true,
	"canon_notes": true,
}


func _ready() -> void:
	load_settings()
	apply()


func get_value(key: String) -> Variant:
	return values.get(key)


func set_value(key: String, value: Variant) -> void:
	values[key] = value
	apply()
	save_settings()


func apply() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if values["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k: String in values:
		values[k] = cfg.get_value("settings", k, values[k])


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k: String in values:
		cfg.set_value("settings", k, values[k])
	cfg.save(PATH)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		set_value("fullscreen", not values["fullscreen"])
