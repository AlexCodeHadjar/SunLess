extends Node
## Звук: шины Music / Ambient / SFX / UI, петли музыки и эмбиента, короткие эффекты
## с лёгким разбросом высоты тона. Ассеты — CC0 (см. audio/CREDITS.md).

const SFX := {
	"hover": ["card-slide-1", "card-slide-2", "card-slide-3", "card-slide-5"],
	"pick": ["card-slide-2", "card-slide-5"],
	"place": ["card-place-1", "card-place-2", "card-place-3"],
	"open": ["card-shove-1", "card-shove-2"],
	"fan": ["card-fan-1"],
	"shuffle": ["card-shuffle"],
	"roll_shake": ["dice-shake-1"],
	"roll": ["dice-throw-1"],
	"success": ["impactBell_heavy_002"],
	"bell": ["impactBell_heavy_000"],
	"fail": ["impactSoft_heavy_000", "impactSoft_heavy_002"],
	"trauma": ["impactPunch_heavy_001"],
	"break": ["impactGlass_medium_001"],
	"death": ["impactMining_002"],
	"ash": ["card-shove-2"],
	"tick": ["impactWood_light_000"],
	"step": ["footstep_snow_000"],
	"new_event": ["cards-pack-open-1"],
}
const BUSES := ["Music", "Ambient", "SFX", "UI"]
const UI_KEYS := ["hover", "pick", "place", "open", "fan", "tick"]

var _cache := {}
var _music: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _last_hover_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	_music = _make_player("Music")
	_ambient = _make_player("Ambient")
	for i in 12:
		_pool.append(_make_player("SFX"))
	apply_volumes()


func _make_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func apply_volumes() -> void:
	var map := {"Master": "vol_master", "Music": "vol_music", "Ambient": "vol_ambient", "SFX": "vol_sfx", "UI": "vol_ui"}
	for bus: String in map:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			continue
		var v: float = float(SettingsService.get_value(map[bus]))
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.001)


func _stream(path: String, loop: bool = false) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStream = load(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = loop
	_cache[path] = s
	return s


## Короткий эффект по ключу из SFX.
func play(key: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if key == "hover":
		var now := Time.get_ticks_msec()
		if now - _last_hover_ms < 70:
			return
		_last_hover_ms = now
	var names: Array = SFX.get(key, [])
	if names.is_empty():
		return
	var s := _stream("res://audio/sfx/%s.ogg" % names[randi() % names.size()])
	if s == null:
		return
	var p := _free_player()
	p.bus = "UI" if UI_KEYS.has(key) else "SFX"
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.93, 1.07)
	p.play()


func _free_player() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	return _pool[0]


func play_music(path: String = "res://audio/music/longing.ogg") -> void:
	_start_loop(_music, path, -8.0)


func play_ambient(path: String = "res://audio/ambient/wind_drips.ogg") -> void:
	_start_loop(_ambient, path, -6.0)


func _start_loop(p: AudioStreamPlayer, path: String, target_db: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var s := _stream(path, true)
	if s == null or (p.playing and p.stream == s):
		return
	p.stream = s
	p.volume_db = -40.0
	p.play()
	create_tween().tween_property(p, "volume_db", target_db, 2.5)
