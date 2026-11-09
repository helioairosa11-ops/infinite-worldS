extends Node
## Persistent user settings (graphics, audio, controls, language).

signal changed

const PATH := "res://saves/settings.cfg"

var render_distance: int = 8
var fov: float = 75.0
var mouse_sensitivity: float = 0.25
var shadows: bool = true
var vsync: bool = true
var fullscreen: bool = false
var fancy_leaves: bool = true
var clouds: bool = true
var max_fps: int = 0
var vol_master: float = 0.8
var vol_music: float = 0.5
var vol_sfx: float = 0.9
var vol_ambient: float = 0.7
var language: String = "pt"
var player_name: String = "Explorer"
var last_ip: String = "127.0.0.1"
var invert_y: bool = false
var view_bobbing: bool = true

## action -> default keycode
const DEFAULT_KEYS := {
	"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
	"jump": KEY_SPACE, "sneak": KEY_SHIFT, "sprint": KEY_CTRL, "inventory": KEY_E,
	"drop": KEY_Q, "chat": KEY_T, "toggle_hud": KEY_F1, "debug": KEY_F3,
	"perspective": KEY_F5, "screenshot": KEY_F2,
}
var keys: Dictionary = {}

func _ready() -> void:
	keys = DEFAULT_KEYS.duplicate()
	load_settings()
	apply()

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for p in _props():
		if cf.has_section_key("settings", p):
			set(p, cf.get_value("settings", p))
	for a in DEFAULT_KEYS:
		if cf.has_section_key("keys", a):
			keys[a] = int(cf.get_value("keys", a))

func save_settings() -> void:
	var cf := ConfigFile.new()
	for p in _props():
		cf.set_value("settings", p, get(p))
	for a in keys:
		cf.set_value("keys", a, keys[a])
	cf.save(PATH)

func _props() -> Array:
	return ["render_distance", "fov", "mouse_sensitivity", "shadows", "vsync", "fullscreen",
		"fancy_leaves", "clouds", "max_fps", "vol_master", "vol_music", "vol_sfx", "vol_ambient",
		"language", "player_name", "last_ip", "invert_y", "view_bobbing"]

func apply() -> void:
	_apply_input_map()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			if not (want == DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED):
				DisplayServer.window_set_mode(want)
	Engine.max_fps = max_fps
	_apply_audio()
	TranslationServer.set_locale(language)
	changed.emit()

func _apply_audio() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_ensure_bus("Ambient")
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(vol_master, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(vol_music, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(vol_sfx, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambient"), linear_to_db(maxf(vol_ambient, 0.0001)))

func _ensure_bus(n: String) -> void:
	if AudioServer.get_bus_index(n) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, n)
		AudioServer.set_bus_send(i, "Master")

func _apply_input_map() -> void:
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		InputMap.action_erase_events(a)
		var ev := InputEventKey.new()
		ev.physical_keycode = keys[a]
		InputMap.action_add_event(a, ev)
	for a in ["attack", "use", "pick_block"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		InputMap.action_erase_events(a)
	var m := InputEventMouseButton.new(); m.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", m)
	m = InputEventMouseButton.new(); m.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("use", m)
	m = InputEventMouseButton.new(); m.button_index = MOUSE_BUTTON_MIDDLE
	InputMap.action_add_event("pick_block", m)

func key_name(action: String) -> String:
	return OS.get_keycode_string(keys.get(action, 0))
