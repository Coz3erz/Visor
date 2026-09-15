extends Node

static var settings: Dictionary = {}
static var player_input_map: Dictionary = {}
static var saved_settings: Dictionary = {}
static var saved_input_map: Dictionary = {}
static var dirty: bool = false

const DEFAULT_SETTINGS = {
	"particles": true,
	"glow": true,
	"screen_shake": true,
	"low_detail": false,
	"master_volume": 100,
	"sfx_volume": 100,
	"music_volume": 100,
	"resolution": "1920x1080",
	"vsync": true,
	"max_fps": 0,
	"msaa": "4x",
	"window_mode": "Windowed",
	"brightness": 100
}

func _ready() -> void:
	if InputMapDefaults.default_input_map.is_empty():
		@warning_ignore("static_called_on_instance")
		InputMapDefaults.capture_defaults()
	load_settings()
	saved_settings = settings.duplicate()
	load_player_input_map()
	saved_input_map = player_input_map.duplicate()
	apply_settings()
	update_dirty()

func load_settings() -> void:
	settings.clear()
	var cfg = ConfigFile.new()
	if cfg.load("user://options.cfg") == OK:
		for key in cfg.get_section_keys("settings"):
			settings[key] = cfg.get_value("settings", key)

func save_settings() -> void:
	var cfg = ConfigFile.new()
	for key in settings.keys():
		cfg.set_value("settings", key, settings[key])
	cfg.save("user://options.cfg")
	saved_settings = settings.duplicate()
	update_dirty()

func load_player_input_map() -> void:
	player_input_map.clear()
	var cfg = ConfigFile.new()
	if cfg.load("user://input_map.cfg") == OK:
		for action in cfg.get_sections():
			if action == "events":
				continue
			var events = cfg.get_value(action, "events", [])
			if events is Array:
				player_input_map[action] = events
		apply_player_input_map()
func reset_settings_to_default() -> void:
	settings = DEFAULT_SETTINGS.duplicate()
	dirty = true
	apply_settings()
	saved_settings = settings.duplicate()
	update_dirty()

func reset_inputs_to_default() -> void:
	if InputMapDefaults.default_input_map.is_empty():
		@warning_ignore("static_called_on_instance")
		InputMapDefaults.capture_defaults()
	# Erase all current custom events
	for action in InputMap.get_actions():
		if action.begins_with("ui_"):
			continue
		InputMap.action_erase_events(action)
	# Re-add defaults
	for action in InputMapDefaults.default_input_map.keys():
		if not InputMap.has_action(action):
			continue
		for e in InputMapDefaults.default_input_map[action]:
			InputMap.action_add_event(action, e)
	# Update player_input_map to reflect defaults
	player_input_map.clear()
	for action in InputMapDefaults.default_input_map.keys():
		player_input_map[action] = InputMapDefaults.default_input_map[action].duplicate()
	dirty = true
	update_dirty()

func apply_settings() -> void:
	if settings.get("window_mode", "Windowed") == "Windowed":
		var res = (settings.get("resolution", "1920x1080") as String).split("x")
		if res.size() == 2:
			DisplayServer.window_set_size(Vector2i(int(res[0]), int(res[1])))

	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if settings.get("vsync", true) else DisplayServer.VSYNC_DISABLED
	)

	Engine.max_fps = int(settings.get("max_fps", 0))

	var msaa_val = 0
	match settings.get("msaa", "4x"):
		"Off": msaa_val = 0
		"2x": msaa_val = 1
		"4x": msaa_val = 2
		"8x": msaa_val = 3
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", msaa_val)

	match settings.get("window_mode", "Windowed"):
		"Windowed": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		"Fullscreen": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"Borderless": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), _linear_to_db(int(settings.get("master_volume", 100)) / 100.0))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), _linear_to_db(int(settings.get("sfx_volume", 100)) / 100.0))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), _linear_to_db(int(settings.get("music_volume", 100)) / 100.0))

func update_dirty() -> void:
	dirty = (settings != saved_settings) or (player_input_map != saved_input_map)

func _linear_to_db(linear: float) -> float:
	return 20.0 * log(max(linear, 0.0001))
func save_player_input_map() -> void:
	var cfg = ConfigFile.new()
	for action in InputMap.get_actions():
		if action.begins_with("ui_"):
			continue
		var events = InputMap.action_get_events(action)
		var serialized = []
		for e in events:
			if e is InputEventKey:
				serialized.append({"type": "key", "keycode": e.keycode, "physical_keycode": e.physical_keycode})
			elif e is InputEventMouseButton:
				serialized.append({"type": "mouse_button", "button_index": e.button_index})
		cfg.set_value(action, "events", serialized)
	cfg.save("user://input_map.cfg")
	saved_input_map = player_input_map.duplicate()
	update_dirty()

func apply_player_input_map() -> void:
	for action in player_input_map.keys():
		if not InputMap.has_action(action):
			continue
		var events = player_input_map[action]
		if events is Array:
			InputMap.action_erase_events(action)
			for e in events:
				if e is Dictionary:
					if e.get("type") == "key":
						var ev = InputEventKey.new()
						ev.keycode = e.get("keycode", 0)
						ev.physical_keycode = e.get("physical_keycode", 0)
						InputMap.action_add_event(action, ev)
					elif e.get("type") == "mouse_button":
						var ev = InputEventMouseButton.new()
						ev.button_index = e.get("button_index")
						InputMap.action_add_event(action, ev)
