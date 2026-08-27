extends Node

static var default_input_map: Dictionary = {}

func _ready() -> void:
	if default_input_map.is_empty():
		capture_defaults()

static func capture_defaults() -> void:
	default_input_map.clear()
	for action in InputMap.get_actions():
		if action.begins_with("ui_"):
			continue
		default_input_map[action] = InputMap.action_get_events(action).duplicate(true)
