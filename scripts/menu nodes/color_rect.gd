extends ColorRect

@export var base_glow_color: Color = Color(0.0, 0.08, 0.35, 1.0)
@export var ring_color: Color = Color(0.0, 0.2, 0.6, 1.0)
@export var secondary_ring_color: Color = Color(0.0, 0.3, 0.8, 1.0)
@export var bleed: float = 8.0
@export var ring_speed: float = 0.05
@export var secondary_ring_speed: float = 0.03
@export var circle_correction: float = 1.0

var shader_material: ShaderMaterial

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(0.0, 0.0, 0.0, 1.0)
	set_process(true)
	_setup_shader()
	get_viewport().size_changed.connect(_on_viewport_resized)

func _process(_delta: float) -> void:
	var viewport_size = get_viewport_rect().size
	if size != viewport_size or position != Vector2.ZERO:
		position = Vector2.ZERO
		size = viewport_size

	if shader_material:
		shader_material.set_shader_parameter("base_glow_color", base_glow_color)
		shader_material.set_shader_parameter("ring_color", ring_color)
		shader_material.set_shader_parameter("secondary_ring_color", secondary_ring_color)
		shader_material.set_shader_parameter("bleed", bleed)
		shader_material.set_shader_parameter("ring_speed", ring_speed)
		shader_material.set_shader_parameter("secondary_ring_speed", secondary_ring_speed)
		shader_material.set_shader_parameter("circle_correction", circle_correction)

		var vs = get_viewport_rect().size
		if vs.x > 0 and vs.y > 0:
			shader_material.set_shader_parameter("inv_aspect", vs.y / vs.x)

func _on_viewport_resized() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _setup_shader() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform vec4 base_glow_color : source_color = vec4(0.0, 0.08, 0.35, 1.0);
uniform vec4 ring_color : source_color = vec4(0.0, 0.2, 0.6, 1.0);
uniform vec4 secondary_ring_color : source_color = vec4(0.0, 0.3, 0.8, 1.0);
uniform float bleed = 8.0;
uniform float ring_speed = 0.05;
uniform float secondary_ring_speed = 0.03;
uniform float inv_aspect = 1.0;
uniform float circle_correction = 1.0;

void fragment() {
	vec2 uv = UV;
	vec2 pos = uv - vec2(0.5, 0.5);
	pos.x *= inv_aspect * circle_correction;
	float dist = length(pos);

	vec3 col = vec3(0.0);

	// Soft central glow
	float glow = exp(-dist * 2.5) * 0.8;
	col += base_glow_color.rgb * glow;

	// Main bleeding rings with smooth fade in/out
	for (int i = 0; i < 4; i++) {
		float t = fract(TIME * ring_speed + float(i) * 0.25);
		float radius = t * 0.7 + 0.2;
		// Smooth envelope: zero at min and max radius
		float envelope = sin(t * PI);
		float d = abs(dist - radius);
		float ring = exp(-d * bleed) * 0.15 * envelope;
		col += ring_color.rgb * ring;
	}

	// Secondary diffuse rings with smooth fade in/out
	for (int i = 0; i < 3; i++) {
		float t = fract(TIME * secondary_ring_speed + float(i) * 0.33 + 0.5);
		float radius = t * 0.6 + 0.25;
		float envelope = sin(t * PI);
		float d = abs(dist - radius);
		float ring = exp(-d * bleed * 0.7) * 0.1 * envelope;
		col += secondary_ring_color.rgb * ring;
	}

	// Subtle pulse
	col *= 0.9 + 0.1 * sin(TIME * 1.2 + dist * 1.5);

	// Dither to prevent banding
	float dither = (fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 0.015;
	col += vec3(dither);

	COLOR = vec4(col, 1.0);
}
"""
	shader_material = ShaderMaterial.new()
	shader_material.shader = shader
	material = shader_material

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_fullscreen"):
		_toggle_fullscreen()

func _toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
