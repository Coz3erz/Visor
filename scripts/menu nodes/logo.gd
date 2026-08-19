extends Sprite2D

@export_group("Bounce")
@export var enable_bounce: bool = true
@export var rotation_speed: float = 1.1
@export var rotation_amplitude: float = 0.1
@export var rotation_offset: float = 0.05
@export var scale_duration: float = 2.0
@export var min_scale: float = 0.6
@export var max_scale: float = 0.7
@export var scale_smoothing: float = 1.8

@export_group("Chromatic Ghost Effect")
@export var enable_chromatic: bool = true
@export var ghost_offset: float = 0.003
@export var red_ghost_offset: Vector2 = Vector2(0.003, 0.0)
@export var blue_ghost_offset: Vector2 = Vector2(-0.003, 0.0)
@export var ghost_pulse_speed: float = 2.0
@export var ghost_intensity: float = 0.6

@export_group("Static / Glitch Lines")
@export var enable_static: bool = true
@export var static_line_density: float = 40.0
@export var static_line_speed: float = 20.0
@export var static_line_intensity: float = 0.4
@export var static_lines_beyond_logo: bool = false
@export var static_line_beyond_intensity: float = 0.2

@export_group("Glitch Bursts")
@export var enable_glitch_burst: bool = true
@export var glitch_burst_rate: float = 2.0
@export var glitch_burst_strength: float = 0.03
@export var glitch_burst_duration: float = 0.15

@export_group("Screen Centering & Offset")
@export var auto_center_screen: bool = true
@export var logo_offset: Vector2 = Vector2.ZERO

var time: float = 0.0
var shader_material: ShaderMaterial

func _ready() -> void:
	centered = true

	if auto_center_screen:
		position = get_viewport_rect().size * 0.5 + logo_offset
		get_viewport().size_changed.connect(_on_viewport_resized)

	shader_material = ShaderMaterial.new()
	shader_material.shader = _create_shader()
	material = shader_material
	_update_shader_params()

func _on_viewport_resized() -> void:
	if auto_center_screen:
		position = get_viewport_rect().size * 0.5 + logo_offset

func _create_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform bool enable_chromatic = true;
uniform float ghost_offset = 0.003;
uniform vec2 red_ghost_offset = vec2(0.003, 0.0);
uniform vec2 blue_ghost_offset = vec2(-0.003, 0.0);
uniform float ghost_pulse_speed = 2.0;
uniform float ghost_intensity = 0.6;

uniform bool enable_static = true;
uniform float static_line_density = 40.0;
uniform float static_line_speed = 20.0;
uniform float static_line_intensity = 0.4;
uniform bool static_lines_beyond_logo = false;
uniform float static_line_beyond_intensity = 0.2;

uniform bool enable_glitch_burst = true;
uniform float glitch_burst_rate = 2.0;
uniform float glitch_burst_strength = 0.03;
uniform float glitch_burst_duration = 0.15;

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

void fragment() {
	vec4 original = texture(TEXTURE, UV);
	float mask = step(0.02, max(original.r, max(original.g, original.b)));

	// Chromatic ghosts (duplicated text slightly offset)
	vec4 red_ghost = texture(TEXTURE, UV + red_ghost_offset);
	vec4 blue_ghost = texture(TEXTURE, UV + blue_ghost_offset);
	vec3 ghost_color = vec3(0.0);
	ghost_color += vec3(1.0, 0.0, 0.0) * red_ghost.r * ghost_intensity;
	ghost_color += vec3(0.0, 0.0, 1.0) * blue_ghost.b * ghost_intensity;
	ghost_color *= mask;

	// Static lines (horizontal glitch lines)
	vec3 static_col = vec3(0.0);
	if (enable_static) {
		float line_pos = floor(UV.y * static_line_density);
		float line_rand = hash(line_pos + floor(TIME * static_line_speed));
		if (line_rand > 0.85) {
			float line_mask = step(abs(UV.y - (line_pos / static_line_density)), 0.002);
			static_col = vec3(0.2, 0.4, 0.9) * line_mask * static_line_intensity;
		}
	}

	// Glitch burst (sudden whole-sprite shift)
	vec3 glitch_col = vec3(0.0);
	if (enable_glitch_burst) {
		float burst_trigger = hash(floor(TIME * glitch_burst_rate));
		if (burst_trigger > 0.6) {
			float burst_time = TIME - floor(TIME * glitch_burst_rate) / glitch_burst_rate;
			if (burst_time < glitch_burst_duration) {
				vec2 burst_offset = vec2(
					(hash(TIME) - 0.5) * glitch_burst_strength,
					(hash(TIME + 1.0) - 0.5) * glitch_burst_strength
				);
				vec4 burst_sample = texture(TEXTURE, UV + burst_offset);
				glitch_col = burst_sample.rgb * mask;
				glitch_col *= vec3(1.2, 0.8, 1.0);
			}
		}
	}

	// Build final colour:
	// First, logo content (original + ghosts + glitch) masked to logo.
	vec3 final_col = original.rgb;
	if (enable_chromatic) {
		final_col += ghost_color;
	}
	if (enable_glitch_burst) {
		final_col += glitch_col;
	}
	final_col *= mask;

	// Static lines: if extending beyond logo, add after mask, with its own intensity control.
	if (static_lines_beyond_logo) {
		final_col += static_col * static_line_beyond_intensity;
	} else {
		final_col += static_col;
	}

	COLOR = vec4(final_col, original.a);
}
"""
	return shader

func _process(delta: float) -> void:
	time += delta

	if auto_center_screen:
		position = get_viewport_rect().size * 0.5 + logo_offset

	if enable_bounce:
		rotation = sin(time * rotation_speed) * rotation_amplitude + rotation_offset

		var scale_progress = fmod(time, scale_duration) / scale_duration
		var current_scale = max_scale - (scale_progress * (max_scale - min_scale))
		var target_scale = Vector2(current_scale, current_scale)
		scale += (target_scale - scale) / scale_smoothing

	_update_shader_params()

func _update_shader_params() -> void:
	if not shader_material:
		return
	shader_material.set_shader_parameter("enable_chromatic", enable_chromatic)
	shader_material.set_shader_parameter("ghost_offset", ghost_offset)
	shader_material.set_shader_parameter("red_ghost_offset", red_ghost_offset)
	shader_material.set_shader_parameter("blue_ghost_offset", blue_ghost_offset)
	shader_material.set_shader_parameter("ghost_pulse_speed", ghost_pulse_speed)
	shader_material.set_shader_parameter("ghost_intensity", ghost_intensity)
	shader_material.set_shader_parameter("enable_static", enable_static)
	shader_material.set_shader_parameter("static_line_density", static_line_density)
	shader_material.set_shader_parameter("static_line_speed", static_line_speed)
	shader_material.set_shader_parameter("static_line_intensity", static_line_intensity)
	shader_material.set_shader_parameter("static_lines_beyond_logo", static_lines_beyond_logo)
	shader_material.set_shader_parameter("static_line_beyond_intensity", static_line_beyond_intensity)
	shader_material.set_shader_parameter("enable_glitch_burst", enable_glitch_burst)
	shader_material.set_shader_parameter("glitch_burst_rate", glitch_burst_rate)
	shader_material.set_shader_parameter("glitch_burst_strength", glitch_burst_strength)
	shader_material.set_shader_parameter("glitch_burst_duration", glitch_burst_duration)
