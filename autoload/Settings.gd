extends Node

## Player settings, saved to user://settings.cfg and applied on startup.
## Read with Settings.get_value(key); change with Settings.set_value(key, v),
## which applies, saves and emits `changed`.

signal changed(key: String, value: Variant)

const PATH := "user://settings.cfg"
const SECTION := "settings"

## Every setting and its default. Volumes are linear 0..1 per audio bus.
const DEFAULTS := {
	"volume_master": 0.8,
	"volume_music": 0.7,
	"volume_sfx": 0.8,
	"volume_ui": 0.8,
	"ps2_filter": true,
	"ps2_lines": 360, # vertical resolution of the 3D view with the filter on
	"fullscreen": false,
	"vsync": true,
	"max_fps": 0, # 0 = unlimited
}

const BUS_FOR := {
	"volume_master": "Master",
	"volume_music": "Music",
	"volume_sfx": "SFX",
	"volume_ui": "UI",
}

var _values: Dictionary = {}
## Tests set this to keep the player's real settings file untouched.
var persist: bool = true


func _ready() -> void:
	load_settings()


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("Settings: unknown key '%s'" % key)
		return
	_values[key] = value
	_apply(key)
	if persist:
		save_settings()
	changed.emit(key, value)


func reset_to_defaults() -> void:
	for key in DEFAULTS:
		set_value(key, DEFAULTS[key])


func load_settings() -> void:
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if persist and cfg.load(PATH) == OK:
		for key in DEFAULTS:
			var v: Variant = cfg.get_value(SECTION, key, DEFAULTS[key])
			if typeof(v) == typeof(DEFAULTS[key]) or (DEFAULTS[key] is float and v is int):
				_values[key] = v
	for key in DEFAULTS:
		_apply(key)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in DEFAULTS:
		cfg.set_value(SECTION, key, get_value(key))
	cfg.save(PATH)


func _apply(key: String) -> void:
	var v: Variant = get_value(key)
	if BUS_FOR.has(key):
		var bus := AudioServer.get_bus_index(BUS_FOR[key])
		if bus >= 0:
			var lin := clampf(float(v), 0.0, 1.0)
			AudioServer.set_bus_volume_db(bus, linear_to_db(lin) if lin > 0.0 else -80.0)
			AudioServer.set_bus_mute(bus, lin <= 0.0)
		return
	if DisplayServer.get_name() == "headless":
		return # no window to change
	match key:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if v else DisplayServer.WINDOW_MODE_WINDOWED)
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if v else DisplayServer.VSYNC_DISABLED)
		"max_fps":
			Engine.max_fps = int(v)
