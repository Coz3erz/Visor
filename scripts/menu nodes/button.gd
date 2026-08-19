extends Button

@export_group("Text")
@export var button_text: String = "Button"
@export var font_size: int = 24
@export var text_color: Color = Color.WHITE

@export_group("Glitch Effects")
@export var enable_chromatic: bool = true
@export var enable_static: bool = true
@export var enable_burst: bool = true
@export var normal_intensity: float = 0.3
@export var hover_intensity: float = 1.2
@export var chromatic_offset: Vector2 = Vector2(0.005, 0.0)
@export var static_density: float = 30.0
@export var static_speed: float = 15.0
@export var burst_rate: float = 2.0
@export var burst_strength: float = 0.05
@export var burst_duration: float = 0.1

@export_group("Layout")
@export var auto_center: bool = true
@export var screen_offset: Vector2 = Vector2.ZERO

var label: Label
var shader_material: ShaderMaterial

func _ready() -> void:
	# Transparent button background
	add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_theme_stylebox_override("disabled", StyleBoxEmpty.new())

	flat = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Create label for visual text (button's own text remains empty)
	label = Label.new()
	label.text = button_text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", text_color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label)

	# Apply shader to label (affects only the glyphs)
	shader_material = ShaderMaterial.new()
	shader_material.shader = _create_shader()
	label.material = shader_material

	# Resize button to fit label
	size = label.get_minimum_size()

	# Initial positioning
	if auto_center:
		_center_button()
		get_viewport().size_changed.connect(_center_button)

	# Hover signals
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	_update_shader_params()

func _center_button() -> void:
	position = get_viewport_rect().size * 0.5 + screen_offset - size * 0.5

func _on_mouse_entered() -> void:
	shader_material.set_shader_parameter("effect_intensity", hover_intensity)

func _on_mouse_exited() -> void:
	shader_material.set_shader_parameter("effect_intensity", normal_intensity)

func _create_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float effect_intensity = 0.3;
uniform bool enable_chromatic = true;
uniform bool enable_static = true;
uniform bool enable_burst = true;
uniform vec2 chromatic_offset = vec2(0.005, 0.0);
uniform float static_density = 30.0;
uniform float static_speed = 15.0;
uniform float burst_rate = 2.0;
uniform float burst_strength = 0.05;
uniform float burst_duration = 0.1;

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

void fragment() {
	vec4 original = texture(TEXTURE, UV);
	float text_mask = original.a;   // only visible text pixels

	vec3 col = original.rgb;

	// Chromatic aberration
	if (enable_chromatic) {
		vec4 red_ghost = texture(TEXTURE, UV + chromatic_offset * effect_intensity);
		vec4 blue_ghost = texture(TEXTURE, UV - chromatic_offset * effect_intensity);
		col += vec3(1.0, 0.0, 0.0) * red_ghost.r * text_mask * effect_intensity * 0.4;
		col += vec3(0.0, 0.0, 1.0) * blue_ghost.b * text_mask * effect_intensity * 0.4;
	}

	// Static horizontal lines
	if (enable_static) {
		float line = floor(UV.y * static_density);
		float rand = hash(line + floor(TIME * static_speed));
		if (rand > 0.8) {
			float line_mask = step(abs(UV.y - (line / static_density)), 0.003);
			col += vec3(0.2, 0.4, 0.8) * line_mask * text_mask * effect_intensity;
		}
	}

	// Glitch bursts (brief random displacement)
	if (enable_burst) {
		float burst_trigger = hash(floor(TIME * burst_rate));
		if (burst_trigger > 0.6) {
			float burst_time = TIME - floor(TIME * burst_rate) / burst_rate;
			if (burst_time < burst_duration) {
				vec2 offset = vec2(
					(hash(TIME) - 0.5) * burst_strength,
					(hash(TIME + 1.0) - 0.5) * burst_strength
				);
				vec4 burst_sample = texture(TEXTURE, UV + offset);
				col += burst_sample.rgb * text_mask * effect_intensity * 0.5;
			}
		}
	}

	// Keep transparent background
	COLOR = vec4(col * text_mask, original.a);
}
"""
	return shader

func _update_shader_params() -> void:
	if shader_material:
		shader_material.set_shader_parameter("effect_intensity", normal_intensity)
		shader_material.set_shader_parameter("enable_chromatic", enable_chromatic)
		shader_material.set_shader_parameter("enable_static", enable_static)
		shader_material.set_shader_parameter("enable_burst", enable_burst)
		shader_material.set_shader_parameter("chromatic_offset", chromatic_offset)
		shader_material.set_shader_parameter("static_density", static_density)
		shader_material.set_shader_parameter("static_speed", static_speed)
		shader_material.set_shader_parameter("burst_rate", burst_rate)
		shader_material.set_shader_parameter("burst_strength", burst_strength)
		shader_material.set_shader_parameter("burst_duration", burst_duration)
