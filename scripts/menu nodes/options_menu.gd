extends Control

@export_category("Terminal Style")
@export var bg_color: Color = Color(0.0, 0.0, 0.0, 0.95)
@export var text_color: Color = Color.WHITE
@export var highlight_color: Color = Color(0.2, 0.6, 1.0)
@export var dim_color: Color = Color(0.5, 0.5, 0.5)
@export var prompt_char: String = "> "

# Glow / Ocean Ripple (shader-based)
@export var base_glow_color: Color = Color(0.0, 0.08, 0.35, 1.0)
@export var ring_color: Color = Color(0.0, 0.2, 0.6, 1.0)
@export var secondary_ring_color: Color = Color(0.0, 0.3, 0.8, 1.0)
@export var foam_color: Color = Color(1.0, 1.0, 1.0, 0.8)
@export var bleed: float = 8.0
@export var ring_speed: float = 0.05
@export var secondary_ring_speed: float = 0.03
@export var foam_speed: float = 0.08
@export var foam_width: float = 0.02
@export var foam_wave_freq: float = 4.0   # angular frequency of wavy distortion
@export var foam_wave_amp: float = 0.02    # amplitude of wave distortion
@export var circle_correction: float = 1.0
@export var glow_strength: float = 0.8

# Typewriter effect
@export var reveal_speed: float = 10.0

var font: SystemFont
var font_size: int = 40
var line_height: int = 50
var padding: float = 30.0

var section_names: Array[String] = ["GAMEPLAY", "AUDIO", "GRAPHICS", "CONTROLS"]
var selected_section: int = 0
var focus_on_sections: bool = false

var current_page: String = "gameplay"
var selected_index: int = 0
var entries: Array[Dictionary] = []

# Modal states
var awaiting_input: bool = false
var rebinding_action: String = ""
var typing_mode: bool = false
var typed_text: String = ""
var typing_target: String = ""

var confirming_exit: bool = false
var confirm_selected: int = 0
var confirm_rects: Array[Rect2] = []

var dropdown_open: bool = false
var dropdown_options: Array = []
var dropdown_selected: int = 0
var dropdown_target: String = ""
var dropdown_anchor: Vector2 = Vector2.ZERO

var dragging_slider: bool = false
var using_mouse: bool = false

# Bottom action bar focus
var focus_on_bottom: bool = false
var selected_bottom_index: int = 0
var bottom_actions: Array[String] = ["SAVE", "BACK", "RESET ALL"]

# Scrolling support
var scroll_offset: int = 0
var max_visible_rows: int = 0

# Typewriter reveal progress (0..1)
var reveal: float = 0.0
var animate_reveal: bool = false

# Visual layers
var bg_layer: ColorRect
var glow_layer: ColorRect
var glow_positions: Array[Vector2] = []
var glow_positions_captured: bool = false   # freeze positions after first frame
var time: float = 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = false

	font = SystemFont.new()
	font.font_names = PackedStringArray(["Courier New", "monospace"])

	_create_background_layer()
	_create_glow_layer()

	_build_gameplay_page()
	reveal = 0.0
	animate_reveal = true
	get_viewport().size_changed.connect(_on_resized)
	_on_resized()

func _create_background_layer() -> void:
	bg_layer = ColorRect.new()
	bg_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.color = bg_color
	bg_layer.z_index = -3
	add_child(bg_layer)

func _create_glow_layer() -> void:
	glow_layer = ColorRect.new()
	glow_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow_layer.color = Color(0,0,0,0)
	glow_layer.z_index = -1
	# No blend mode line (default)

	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
uniform int glow_count = 0;
uniform vec2 glow_positions[32];
uniform vec4 base_glow_color : source_color = vec4(0.0, 0.08, 0.35, 1.0);
uniform vec4 ring_color : source_color = vec4(0.0, 0.2, 0.6, 1.0);
uniform vec4 secondary_ring_color : source_color = vec4(0.0, 0.3, 0.8, 1.0);
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 1.0, 0.8);
uniform float bleed = 8.0;
uniform float ring_speed = 0.05;
uniform float secondary_ring_speed = 0.03;
uniform float foam_speed = 0.08;
uniform float foam_width = 0.02;
uniform float foam_wave_freq = 4.0;
uniform float foam_wave_amp = 0.02;
uniform float inv_aspect = 1.0;
uniform float circle_correction = 1.0;
uniform float glow_strength = 0.8;
uniform float time = 0.0;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898,78.233))) * 43758.5453);
}

void fragment() {
    vec3 col = vec3(0.0);
    for (int i = 0; i < glow_count; i++) {
        vec2 diff = UV - glow_positions[i];
        diff.x *= inv_aspect * circle_correction;
        float dist = length(diff);

        // Soft central glow
        float central = exp(-dist * 2.5) * 0.8;
        col += base_glow_color.rgb * central;

        // Main rings (soft)
        for (int j = 0; j < 4; j++) {
            float t = fract(time * ring_speed + float(j) * 0.25);
            float radius = t * 0.7 + 0.2;
            float envelope = sin(t * PI);
            float d = abs(dist - radius);
            float ring = exp(-d * bleed) * 0.15 * envelope;
            col += ring_color.rgb * ring;
        }

        // Secondary rings (soft)
        for (int j = 0; j < 3; j++) {
            float t = fract(time * secondary_ring_speed + float(j) * 0.33 + 0.5);
            float radius = t * 0.6 + 0.25;
            float envelope = sin(t * PI);
            float d = abs(dist - radius);
            float ring = exp(-d * bleed * 0.7) * 0.1 * envelope;
            col += secondary_ring_color.rgb * ring;
        }

        // Foam lines (harmonious waves)
        float point_phase = hash(vec2(float(i), 1.0)) * 6.28318;
        for (int j = 0; j < 3; j++) {
            float t = fract(time * foam_speed + float(j) * 0.2 + point_phase * 0.1);
            float radius = mix(0.1, 0.8, t);
            float angle = atan(diff.y, diff.x);
            radius += foam_wave_amp * sin(angle * foam_wave_freq + time * 2.0 + point_phase);
            float envelope = sin(t * PI);
            float d = abs(dist - radius);
            float line = exp(-pow(d / foam_width, 2.0));
            col += foam_color.rgb * line * envelope * 0.8;
        }
    }
    col *= glow_strength;

    // Dithering to reduce banding
    float dither = (hash(UV * 100.0) - 0.5) * 0.015;
    col += vec3(dither);

    COLOR = vec4(col, 1.0);
}
"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	glow_layer.material = mat
	add_child(glow_layer)

func _process(delta: float) -> void:
	time += delta
	if animate_reveal and reveal < 1.0:
		reveal = min(reveal + delta * reveal_speed, 1.0)
		queue_redraw()
	elif animate_reveal and reveal >= 1.0:
		animate_reveal = false

	if glow_layer:
		var mat = glow_layer.material as ShaderMaterial
		mat.set_shader_parameter("time", time)

func _on_resized() -> void:
	var vs = get_viewport_rect().size
	var base = min(vs.x, vs.y)
	font_size = clampi(int(base * 0.05), 28, 48)
	line_height = int(font_size * 1.3)
	padding = font_size

	var top_area = padding + line_height * 2
	var bottom_area = line_height * 2
	var available_height = size.y - top_area - bottom_area
	max_visible_rows = max(1, int(available_height / line_height))

	_update_scroll_range()
	queue_redraw()

func _update_scroll_range() -> void:
	var max_scroll = max(0, entries.size() - max_visible_rows)
	scroll_offset = clampi(scroll_offset, 0, max_scroll)

# ============================================================================
# DRAWING
# ============================================================================
func _draw() -> void:
	if not glow_positions_captured:
		glow_positions.clear()
	# else: keep positions constant

	# Section bar
	var y = padding
	for i in range(section_names.size()):
		var section_text = section_names[i]
		if i == selected_section:
			section_text = "[ " + section_text + " ]"
		else:
			section_text = "  " + section_text + "  "
		var col = highlight_color if i == selected_section else text_color
		var pos = Vector2(padding + i * (font_size * 8), y + font.get_ascent(font_size))
		_draw_text(pos, section_text, col)

	# Options area
	var options_start_y = padding + line_height * 2
	var end_idx = min(scroll_offset + max_visible_rows, entries.size())
	for i in range(scroll_offset, end_idx):
		var line_y = options_start_y + (i - scroll_offset) * line_height
		var layout = _get_entry_layout(i, line_y)
		var line_text: String = layout["text"]
		var col = highlight_color if layout["active"] else text_color
		var display_text = line_text
		if animate_reveal:
			var visible_chars = int(reveal * line_text.length())
			display_text = line_text.substr(0, visible_chars)
		_draw_text(Vector2(padding, line_y + font.get_ascent(font_size)), display_text, col)

	# Bottom action bar
	_draw_bottom_actions()

	# Overlays
	if awaiting_input:
		var prompt = "Press any key for " + rebinding_action + "..."
		var display = prompt
		if animate_reveal:
			var visible = int(reveal * prompt.length())
			display = prompt.substr(0, visible)
		_draw_text(Vector2(padding, size.y - line_height * 3 + font.get_ascent(font_size)), display, highlight_color)
	elif typing_mode:
		var prompt = "Type value for " + typing_target + ": " + typed_text + "_"
		var display = prompt
		if animate_reveal:
			var visible = int(reveal * prompt.length())
			display = prompt.substr(0, visible)
		_draw_text(Vector2(padding, size.y - line_height * 3 + font.get_ascent(font_size)), display, highlight_color)

	if dropdown_open:
		_draw_dropdown()

	if confirming_exit:
		_draw_confirm_dialog()

	if not glow_positions_captured:
		glow_positions_captured = true
	_update_glow_shader()

func _draw_bottom_actions() -> void:
	var bottom_y = size.y - line_height * 2
	var gap = font_size * 5
	var x = padding

	for i in range(bottom_actions.size()):
		var text = bottom_actions[i]
		var is_selected = focus_on_bottom and i == selected_bottom_index

		var display_text = ("> " if is_selected else "  ") + text
		var drawn_text = display_text
		if animate_reveal:
			var visible_chars = int(reveal * display_text.length())
			drawn_text = display_text.substr(0, visible_chars)

		var col = highlight_color if is_selected else text_color
		_draw_text(Vector2(x, bottom_y + font.get_ascent(font_size)), drawn_text, col)

		x += font.get_string_size(display_text).x + gap

func _draw_text(pos: Vector2, text: String, color: Color) -> void:
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	if not glow_positions_captured:
		var text_size = font.get_string_size(text)
		var center = pos + Vector2(text_size.x / 2.0, -text_size.y / 2.0)
		glow_positions.append(center)

func _update_glow_shader() -> void:
	if glow_layer == null:
		return
	var mat = glow_layer.material as ShaderMaterial
	var vs = get_viewport_rect().size
	var count = min(glow_positions.size(), 32)
	mat.set_shader_parameter("glow_count", count)
	var pos_array = []
	for i in range(count):
		var uv = Vector2(glow_positions[i].x / vs.x, glow_positions[i].y / vs.y)
		pos_array.append(uv)
	for i in range(count, 32):
		pos_array.append(Vector2.ZERO)
	mat.set_shader_parameter("glow_positions", pos_array)
	mat.set_shader_parameter("base_glow_color", base_glow_color)
	mat.set_shader_parameter("ring_color", ring_color)
	mat.set_shader_parameter("secondary_ring_color", secondary_ring_color)
	mat.set_shader_parameter("foam_color", foam_color)
	mat.set_shader_parameter("bleed", bleed)
	mat.set_shader_parameter("ring_speed", ring_speed)
	mat.set_shader_parameter("secondary_ring_speed", secondary_ring_speed)
	mat.set_shader_parameter("foam_speed", foam_speed)
	mat.set_shader_parameter("foam_width", foam_width)
	mat.set_shader_parameter("foam_wave_freq", foam_wave_freq)
	mat.set_shader_parameter("foam_wave_amp", foam_wave_amp)
	mat.set_shader_parameter("circle_correction", circle_correction)
	mat.set_shader_parameter("glow_strength", glow_strength)
	mat.set_shader_parameter("inv_aspect", vs.y / vs.x)

func _draw_confirm_dialog() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.85))
	var prompt = "Unsaved changes! What do you want to do?"
	var options = ["Save & Exit", "Exit Without Saving", "Cancel"]
	var px = padding
	var py = size.y * 0.3
	_draw_text(Vector2(px, py + font.get_ascent(font_size)), prompt, text_color)
	confirm_rects.clear()
	var y = py + line_height * 1.5
	for i in range(options.size()):
		var col = highlight_color if i == confirm_selected else text_color
		_draw_text(Vector2(px, y + font.get_ascent(font_size)), options[i], col)
		var rect = Rect2(px, y, size.x - px * 2, line_height)
		confirm_rects.append(rect)
		y += line_height

func _draw_dropdown() -> void:
	var dd_x = dropdown_anchor.x
	var dd_y = dropdown_anchor.y
	var dd_width = size.x - dd_x - padding
	draw_rect(Rect2(dd_x, dd_y, dd_width, dropdown_options.size() * line_height + 10), Color(0, 0, 0, 0.9))
	for i in range(dropdown_options.size()):
		var prefix = "> " if i == dropdown_selected else "  "
		var col = highlight_color if i == dropdown_selected else text_color
		_draw_text(Vector2(dd_x + 10, dd_y + 10 + i * line_height + font.get_ascent(font_size)), prefix + str(dropdown_options[i]), col)

# ============================================================================
# PAGE BUILDERS
# ============================================================================
func _build_gameplay_page() -> void:
	current_page = "gameplay"
	entries.clear()
	entries.append({"text": _bool_text("Particles", GameSettings.settings.get("particles", true)), "action": "toggle", "param": "particles"})
	entries.append({"text": _bool_text("Glow", GameSettings.settings.get("glow", true)), "action": "toggle", "param": "glow"})
	entries.append({"text": _bool_text("Screen Shake", GameSettings.settings.get("screen_shake", true)), "action": "toggle", "param": "screen_shake"})
	entries.append({"text": _bool_text("Low Detail Mode", GameSettings.settings.get("low_detail", false)), "action": "toggle", "param": "low_detail"})
	scroll_offset = 0
	_update_scroll_range()
	queue_redraw()

func _build_audio_page() -> void:
	current_page = "audio"
	entries.clear()
	entries.append(_slider_entry("Master Volume", "master_volume", 0, 100))
	entries.append(_slider_entry("SFX Volume", "sfx_volume", 0, 100))
	entries.append(_slider_entry("Music Volume", "music_volume", 0, 100))
	scroll_offset = 0
	_update_scroll_range()
	queue_redraw()

func _build_graphics_page() -> void:
	current_page = "graphics"
	entries.clear()
	entries.append(_cycle_entry("Resolution", "resolution", ["1280x720", "1600x900", "1920x1080", "2560x1440"]))
	entries.append({"text": _bool_text("VSync", GameSettings.settings.get("vsync", true)), "action": "toggle", "param": "vsync"})
	entries.append(_cycle_entry("Max FPS", "max_fps", [0, 30, 60, 120, 144, 240]))
	entries.append(_cycle_entry("MSAA", "msaa", ["Off", "2x", "4x", "8x"]))
	entries.append(_cycle_entry("Window Mode", "window_mode", ["Windowed", "Fullscreen", "Borderless"]))
	entries.append(_slider_entry("Brightness", "brightness", 0, 200))
	scroll_offset = 0
	_update_scroll_range()
	queue_redraw()

func _build_controls_page() -> void:
	current_page = "controls"
	entries.clear()
	var actions = _get_custom_actions()
	if actions.is_empty():
		entries.append({"text": "No custom actions found", "action": "back"})
	else:
		for action in actions:
			var key_text = _get_action_display(action)
			entries.append({"text": action.replace("_", " ") + "  [" + key_text + "]", "action": "rebind", "param": action})
	entries.append({"text": "Reset Keybinds", "action": "reset_keys"})
	scroll_offset = 0
	_update_scroll_range()
	queue_redraw()

func _build_current_page() -> void:
	match current_page:
		"gameplay": _build_gameplay_page()
		"audio": _build_audio_page()
		"graphics": _build_graphics_page()
		"controls": _build_controls_page()
		_: _build_gameplay_page()
	queue_redraw()

func _open_section(idx: int) -> void:
	selected_section = idx
	selected_index = 0
	scroll_offset = 0
	focus_on_sections = false
	focus_on_bottom = false
	reveal = 0.0
	animate_reveal = true
	match idx:
		0: _build_gameplay_page()
		1: _build_audio_page()
		2: _build_graphics_page()
		3: _build_controls_page()
	queue_redraw()

# ============================================================================
# LAYOUT HELPERS
# ============================================================================
func _get_entry_layout(i: int, line_y: float) -> Dictionary:
	var is_active = (i == selected_index and not focus_on_sections and not focus_on_bottom)
	var prefix = "> " if is_active else "  "
	var full_text = prefix + entries[i].text
	var layout = {
		"y": line_y,
		"x": padding,
		"text": full_text,
		"active": is_active
	}
	if entries[i].action == "adjust":
		var label = entries[i].get("label", "")
		var prefix_and_label = prefix + label + ": ["
		var label_width = font.get_string_size(prefix_and_label).x
		var bar_start_x = padding + label_width + font_size * 0.5
		var bar_str = entries[i].get("bar", "")
		var bar_width = font.get_string_size(bar_str).x
		var bar_end_x = bar_start_x + bar_width
		layout["bar_start_x"] = bar_start_x
		layout["bar_end_x"] = bar_end_x
		layout["bar_rect"] = Rect2(bar_start_x, line_y, bar_end_x - bar_start_x, line_height)
	return layout

func _line_index_from_pos(pos: Vector2) -> int:
	if pos.y >= size.y - line_height * 2:
		return -1
	var options_start_y = padding + line_height * 2
	var rel_y = pos.y - options_start_y
	if rel_y < 0 or rel_y >= max_visible_rows * line_height:
		return -1
	var visible_index = int(rel_y / line_height)
	var actual_index = scroll_offset + visible_index
	if actual_index < 0 or actual_index >= entries.size():
		return -1
	if pos.x < padding or pos.x > size.x - padding:
		return -1
	return actual_index

func _section_index_from_pos(pos: Vector2) -> int:
	if pos.y < 0 or pos.y > line_height * 2:
		return -1
	var x = pos.x - padding
	var idx = int(x / (font_size * 8))
	if idx >= 0 and idx < section_names.size():
		return idx
	return -1

func _bottom_action_index(pos: Vector2) -> int:
	if pos.y < size.y - line_height * 2 or pos.y >= size.y - line_height:
		return -1
	var x = padding
	var gap = font_size * 5
	for i in range(bottom_actions.size()):
		var display_text = ("> " if focus_on_bottom and i == selected_bottom_index else "  ") + bottom_actions[i]
		var width = font.get_string_size(display_text).x
		var segment_width = width + gap
		if pos.x >= x and pos.x < x + segment_width:
			return i
		x += segment_width
	return -1

# ============================================================================
# INPUT
# ============================================================================
func _input(event: InputEvent) -> void:
	if confirming_exit:
		_input_confirm(event)
		return
	if dropdown_open:
		_input_dropdown(event)
		return
	if typing_mode:
		_input_typing(event)
		return
	if awaiting_input:
		_input_rebind(event)
		return

	if event is InputEventMouseMotion:
		using_mouse = true
		if dragging_slider:
			_handle_mouse_motion(event.position)
		else:
			var idx = _line_index_from_pos(event.position)
			if idx != -1:
				selected_index = idx
				focus_on_sections = false
				focus_on_bottom = false
				queue_redraw()
			else:
				var bottom_idx = _bottom_action_index(event.position)
				if bottom_idx != -1:
					selected_bottom_index = bottom_idx
					focus_on_bottom = true
					focus_on_sections = false
					queue_redraw()
	elif event is InputEventMouseButton:
		if event.pressed:
			using_mouse = true
			if event.button_index == MOUSE_BUTTON_LEFT:
				var bottom_idx = _bottom_action_index(event.position)
				if bottom_idx != -1:
					_handle_bottom_action(bottom_idx)
					return
				if event.position.y < line_height * 2:
					var sec_idx = _section_index_from_pos(event.position)
					if sec_idx != -1:
						selected_section = sec_idx
						_open_section(selected_section)
						queue_redraw()
					return
				var idx = _line_index_from_pos(event.position)
				if idx >= 0 and idx < entries.size():
					selected_index = idx
					focus_on_sections = false
					focus_on_bottom = false
					var entry = entries[idx]
					if entry.action == "adjust":
						dragging_slider = true
						_handle_mouse_motion(event.position)
					else:
						_activate_selected()
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				var idx = _line_index_from_pos(event.position)
				if idx != -1:
					selected_index = idx
					focus_on_sections = false
					focus_on_bottom = false
					_adjust_option(1)
					queue_redraw()
				else:
					if scroll_offset > 0:
						scroll_offset -= 1
						_update_scroll_range()
						queue_redraw()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				var idx = _line_index_from_pos(event.position)
				if idx != -1:
					selected_index = idx
					focus_on_sections = false
					focus_on_bottom = false
					_adjust_option(-1)
					queue_redraw()
				else:
					if scroll_offset < max(0, entries.size() - max_visible_rows):
						scroll_offset += 1
						_update_scroll_range()
						queue_redraw()
		else:
			if event.button_index == MOUSE_BUTTON_LEFT and dragging_slider:
				dragging_slider = false
	elif event is InputEventKey:
		if event.pressed:
			using_mouse = false
			match event.keycode:
				KEY_UP:
					_navigate_up()
				KEY_DOWN:
					_navigate_down()
				KEY_LEFT:
					_navigate_left()
				KEY_RIGHT:
					_navigate_right()
				KEY_ENTER, KEY_KP_ENTER:
					if not event.echo:
						_activate_focused()
				KEY_ESCAPE:
					if not event.echo:
						_back()

func _navigate_up() -> void:
	if focus_on_sections:
		selected_section = (selected_section - 1 + section_names.size()) % section_names.size()
		queue_redraw()
	elif focus_on_bottom:
		focus_on_bottom = false
		focus_on_sections = false
		selected_index = min(entries.size() - 1, scroll_offset + max_visible_rows - 1)
		queue_redraw()
	else:
		if selected_index > 0:
			selected_index -= 1
			if selected_index < scroll_offset:
				scroll_offset = selected_index
				_update_scroll_range()
		else:
			selected_index = entries.size() - 1
			scroll_offset = max(0, entries.size() - max_visible_rows)
		queue_redraw()

func _navigate_down() -> void:
	if focus_on_sections:
		selected_section = (selected_section + 1) % section_names.size()
		queue_redraw()
	elif focus_on_bottom:
		selected_bottom_index = (selected_bottom_index + 1) % bottom_actions.size()
		queue_redraw()
	else:
		if selected_index < entries.size() - 1:
			selected_index += 1
			if selected_index >= scroll_offset + max_visible_rows:
				scroll_offset = selected_index - max_visible_rows + 1
				_update_scroll_range()
			queue_redraw()
		else:
			focus_on_bottom = true
			focus_on_sections = false
			selected_bottom_index = 0
			queue_redraw()

func _navigate_left() -> void:
	if focus_on_sections:
		selected_section = (selected_section - 1 + section_names.size()) % section_names.size()
		queue_redraw()
	elif focus_on_bottom:
		selected_bottom_index = (selected_bottom_index - 1 + bottom_actions.size()) % bottom_actions.size()
		queue_redraw()
	else:
		_adjust_option(-1)
		queue_redraw()

func _navigate_right() -> void:
	if focus_on_sections:
		selected_section = (selected_section + 1) % section_names.size()
		queue_redraw()
	elif focus_on_bottom:
		selected_bottom_index = (selected_bottom_index + 1) % bottom_actions.size()
		queue_redraw()
	else:
		_adjust_option(1)
		queue_redraw()

func _activate_focused() -> void:
	if focus_on_sections:
		_open_section(selected_section)
	elif focus_on_bottom:
		_handle_bottom_action(selected_bottom_index)
	else:
		_activate_selected()

func _handle_bottom_action(index: int) -> void:
	match bottom_actions[index]:
		"SAVE":
			_save_all()
		"BACK":
			_exit_action()
		"RESET ALL":
			_reset_all_action()

func _reset_all_action() -> void:
	GameSettings.reset_settings_to_default()
	GameSettings.save_settings()
	_build_current_page()
	queue_redraw()

func _reset_keys_action() -> void:
	GameSettings.reset_inputs_to_default()
	GameSettings.save_player_input_map()
	if current_page == "controls":
		_build_controls_page()
	else:
		_build_current_page()
	queue_redraw()

func _exit_action() -> void:
	if GameSettings.dirty:
		confirming_exit = true
		confirm_selected = 0
		focus_on_sections = false
		focus_on_bottom = false
		queue_redraw()
	else:
		_exit_to_main_menu()

func _back() -> void:
	if awaiting_input:
		awaiting_input = false
		_build_current_page()
		return
	if typing_mode:
		typing_mode = false
		typed_text = ""
		_build_current_page()
		return
	if dropdown_open:
		dropdown_open = false
		_build_current_page()
		return
	if focus_on_sections:
		if GameSettings.dirty:
			confirming_exit = true
			confirm_selected = 0
		else:
			_exit_to_main_menu()
		queue_redraw()
		return
	if focus_on_bottom:
		focus_on_bottom = false
		selected_index = min(entries.size() - 1, scroll_offset + max_visible_rows - 1)
		queue_redraw()
		return
	focus_on_sections = true
	focus_on_bottom = false
	queue_redraw()

func _handle_mouse_motion(pos: Vector2) -> void:
	if not dragging_slider:
		return
	var line_y = padding + line_height * 2 + (selected_index - scroll_offset) * line_height
	var layout = _get_entry_layout(selected_index, line_y)
	if layout.is_empty() or not layout.has("bar_start_x"):
		return
	var bar_start = layout["bar_start_x"]
	var bar_end = layout["bar_end_x"]
	if bar_end - bar_start <= 0.001:
		return
	var ratio = clamp((pos.x - bar_start) / (bar_end - bar_start), 0.0, 1.0)
	var entry = entries[selected_index]
	GameSettings.settings[entry.param] = int(entry.min + ratio * (entry.max - entry.min))
	GameSettings.dirty = true
	_build_current_page()
	queue_redraw()

func _input_confirm(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP:
				confirm_selected = (confirm_selected - 1 + 3) % 3
				queue_redraw()
			KEY_DOWN:
				confirm_selected = (confirm_selected + 1) % 3
				queue_redraw()
			KEY_ENTER, KEY_KP_ENTER:
				_confirm_execute(confirm_selected)
			KEY_ESCAPE:
				confirming_exit = false
				_build_current_page()
				queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in range(confirm_rects.size()):
			if confirm_rects[i].has_point(event.position):
				_confirm_execute(i)
				break
	elif event is InputEventMouseMotion:
		for i in range(confirm_rects.size()):
			if confirm_rects[i].has_point(event.position):
				if confirm_selected != i:
					confirm_selected = i
					queue_redraw()
				break

func _confirm_execute(index: int) -> void:
	match index:
		0:
			_save_all()
			_exit_to_main_menu()
		1:
			GameSettings.load_settings()
			GameSettings.load_player_input_map()
			GameSettings.apply_settings()
			GameSettings.dirty = false
			_exit_to_main_menu()
		2:
			confirming_exit = false
			_build_current_page()
			queue_redraw()

func _input_dropdown(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP:
				dropdown_selected = (dropdown_selected - 1 + dropdown_options.size()) % dropdown_options.size()
				queue_redraw()
			KEY_DOWN:
				dropdown_selected = (dropdown_selected + 1) % dropdown_options.size()
				queue_redraw()
			KEY_ENTER, KEY_KP_ENTER:
				GameSettings.settings[dropdown_target] = dropdown_options[dropdown_selected]
				GameSettings.dirty = true
				dropdown_open = false
				_build_current_page()
				queue_redraw()
			KEY_ESCAPE:
				dropdown_open = false
				_build_current_page()
				queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var dd_rect = Rect2(dropdown_anchor, Vector2(size.x - dropdown_anchor.x - padding, dropdown_options.size() * line_height + 10))
		if dd_rect.has_point(event.position):
			var rel_y = event.position.y - dropdown_anchor.y - 10
			var idx = int(rel_y / line_height)
			if idx >= 0 and idx < dropdown_options.size():
				GameSettings.settings[dropdown_target] = dropdown_options[idx]
				GameSettings.dirty = true
				dropdown_open = false
				_build_current_page()
				queue_redraw()
		else:
			dropdown_open = false
			_build_current_page()
			queue_redraw()
	elif event is InputEventMouseMotion:
		var dd_rect = Rect2(dropdown_anchor, Vector2(size.x - dropdown_anchor.x - padding, dropdown_options.size() * line_height + 10))
		if dd_rect.has_point(event.position):
			var rel_y = event.position.y - dropdown_anchor.y - 10
			var idx = int(rel_y / line_height)
			if idx >= 0 and idx < dropdown_options.size() and idx != dropdown_selected:
				dropdown_selected = idx
				queue_redraw()

func _input_typing(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				var value = typed_text.to_int()
				typed_text = ""
				typing_mode = false
				_set_numeric_setting(typing_target, value)
				_build_current_page()
				queue_redraw()
			KEY_ESCAPE:
				typed_text = ""
				typing_mode = false
				_build_current_page()
				queue_redraw()
			KEY_BACKSPACE:
				if typed_text.length() > 0:
					typed_text = typed_text.substr(0, typed_text.length() - 1)
					queue_redraw()
			_:
				var c = event.as_text_key_label()
				if c.is_valid_int() or c.is_valid_float():
					typed_text += c
					queue_redraw()

func _input_rebind(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			awaiting_input = false
			_build_current_page()
			queue_redraw()
			return
		_assign_action_event(rebinding_action, event)
	elif event is InputEventMouseButton and event.pressed:
		_assign_action_event(rebinding_action, event)

func _assign_action_event(action: String, event: InputEvent) -> void:
	var events = InputMap.action_get_events(action)
	if events.is_empty():
		InputMap.action_add_event(action, event)
	else:
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, event)
		for i in range(1, events.size()):
			InputMap.action_add_event(action, events[i])
	GameSettings.dirty = true
	awaiting_input = false
	if current_page == "controls":
		_build_controls_page()
	else:
		_build_current_page()
	queue_redraw()

func _activate_selected() -> void:
	if selected_index < 0 or selected_index >= entries.size():
		return
	var entry = entries[selected_index]
	match entry.action:
		"toggle":
			var key = entry.param
			GameSettings.settings[key] = not GameSettings.settings.get(key, false)
			GameSettings.dirty = true
			_build_current_page()
			queue_redraw()
		"adjust":
			typing_mode = true
			typing_target = entry.param
			typed_text = str(GameSettings.settings.get(entry.param, 0))
			queue_redraw()
		"cycle":
			dropdown_open = true
			dropdown_target = entry.param
			dropdown_options = entry.options
			dropdown_selected = entry.options.find(GameSettings.settings.get(entry.param))
			var line_y = padding + line_height * 2 + (selected_index - scroll_offset) * line_height
			dropdown_anchor = Vector2(padding + 200, line_y + line_height)
			queue_redraw()
		"rebind":
			rebinding_action = entry.param
			awaiting_input = true
			queue_redraw()
		"reset_keys":
			_reset_keys_action()

func _adjust_option(dir: int) -> void:
	if selected_index < 0 or selected_index >= entries.size():
		return
	var entry = entries[selected_index]
	if entry.action == "adjust":
		var key = entry.param
		var val = int(GameSettings.settings.get(key, 0))
		val = clampi(val + dir, int(entry.min), int(entry.max))
		GameSettings.settings[key] = val
		GameSettings.dirty = true
		_build_current_page()
		queue_redraw()
	elif entry.action == "cycle":
		var opts = entry.options
		var current = GameSettings.settings.get(entry.param, opts[0])
		var idx = opts.find(current)
		if idx == -1:
			idx = 0
		if dir > 0:
			idx = (idx + 1) % opts.size()
		else:
			idx = (idx - 1 + opts.size()) % opts.size()
		GameSettings.settings[entry.param] = opts[idx]
		GameSettings.dirty = true
		_build_current_page()
		queue_redraw()

func _set_numeric_setting(key: String, value: int) -> void:
	var entry = null
	for e in entries:
		if e.has("param") and e.param == key:
			entry = e
			break
	if entry and entry.has("min") and entry.has("max"):
		value = clampi(value, int(entry.min), int(entry.max))
	GameSettings.settings[key] = value
	GameSettings.dirty = true

func _save_all() -> void:
	GameSettings.save_settings()
	GameSettings.save_player_input_map()
	GameSettings.apply_settings()
	GameSettings.dirty = false
	_build_current_page()
	queue_redraw()

func _exit_to_main_menu() -> void:
	var sm = get_node_or_null("/root/SceneManager")
	if sm and sm.has_method("return_to_previous_scene"):
		sm.return_to_previous_scene()
	else:
		get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")

# ============================================================================
# HELPERS FOR PAGE DATA
# ============================================================================
func _get_custom_actions() -> Array[String]:
	var result: Array[String] = []
	for action in InputMap.get_actions():
		if action.begins_with("ui_"):
			continue
		result.append(action)
	return result

func _get_action_display(action: String) -> String:
	var events = InputMap.action_get_events(action)
	if events.is_empty():
		return "None"
	var e = events[0]
	if e is InputEventKey:
		return OS.get_keycode_string(e.keycode)
	elif e is InputEventMouseButton:
		match e.button_index:
			MOUSE_BUTTON_LEFT: return "Left Mouse"
			MOUSE_BUTTON_RIGHT: return "Right Mouse"
			MOUSE_BUTTON_MIDDLE: return "Middle Mouse"
			_: return "Mouse " + str(e.button_index)
	elif e is InputEventJoypadButton:
		return "Joy " + str(e.button_index)
	return "None"

func _bool_text(label: String, value: bool) -> String:
	return "%s: [%s]" % [label, "X" if value else " "]

func _slider_entry(label: String, key: String, min_val: float, max_val: float) -> Dictionary:
	var value = int(GameSettings.settings.get(key, min_val))
	var bar_str = _slider_bar(value, min_val, max_val)
	return {
		"text": "%s: [%s] %d" % [label, bar_str, value],
		"action": "adjust",
		"param": key,
		"min": min_val,
		"max": max_val,
		"label": label,
		"bar": bar_str
	}

func _cycle_entry(label: String, key: String, options: Array) -> Dictionary:
	var current = GameSettings.settings.get(key, options[0])
	var display = "Uncapped" if key == "max_fps" and current == 0 else str(current)
	return {"text": "%s: < %s >" % [label, display], "action": "cycle", "param": key, "options": options}

func _slider_bar(value: float, min_val: float, max_val: float, width: int = 20) -> String:
	var ratio = (value - min_val) / max(max_val - min_val, 1.0)
	var filled = int(ratio * width)
	return "=".repeat(filled) + "-".repeat(width - filled)
