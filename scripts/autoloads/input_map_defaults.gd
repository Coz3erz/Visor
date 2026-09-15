extends Node

## The "true" default keybinds, read straight from Project Settings > Input Map.
## Safe to read at ANY time, regardless of what the runtime InputMap currently
## holds or which autoload runs first — ProjectSettings is never touched by
## InputMap.action_add_event() / action_erase_events() at runtime, so there's
## no more "capture before anything else touches it" race, and no lossy
## keycode-only serialization to a save file.
static var default_input_map: Dictionary = {}

func _ready() -> void:
	if default_input_map.is_empty():
		capture_defaults()

static func capture_defaults() -> void:
	default_input_map.clear()
	for action in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		var setting_name := "input/" + String(action)
		if not ProjectSettings.has_setting(setting_name):
			# Not defined in Project Settings (e.g. added purely at runtime) —
			# nothing to reset it back to.
			continue
		var project_default: Dictionary = ProjectSettings.get_setting(setting_name)
		var events: Array = project_default.get("events", [])
		default_input_map[action] = events.duplicate(true)
