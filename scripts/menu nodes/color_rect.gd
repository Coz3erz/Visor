extends ColorRect

func _ready() -> void:
	await get_tree().process_frame
	_setup_fullscreen_rect()
	_setup_shader()
	get_viewport().size_changed.connect(_setup_fullscreen_rect)

func _setup_fullscreen_rect() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

func _setup_shader() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

void fragment() {
    vec2 uv = UV;
    vec2 center = vec2(0.5, 0.5);
    vec2 pos = uv - center;
    float dist = length(pos);

    vec3 col = vec3(0.0);

    // Soft central glow
    float glow = exp(-dist * 3.5) * 0.9;
    col += vec3(0.0, 0.08, 0.35) * glow;

    // Bleeding rings (soft exponential falloff)
    for (int i = 0; i < 5; i++) {
        float radius = fract(TIME * 0.06 + float(i) * 0.2) * 0.75 + 0.15;
        float d = abs(dist - radius);
        float ring = exp(-d * 8.0) * 0.12;
        col += vec3(0.0, 0.15, 0.5) * ring;
    }

    // Secondary softer rings
    for (int i = 0; i < 3; i++) {
        float radius = fract(TIME * 0.04 + float(i) * 0.33 + 0.5) * 0.7;
        float d = abs(dist - radius);
        float ring = exp(-d * 10.0) * 0.08;
        col += vec3(0.0, 0.2, 0.6) * ring;
    }

    // Subtle pulse
    col *= 0.85 + 0.15 * sin(TIME * 1.5 + dist * 2.0);

    COLOR = vec4(col, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	material = mat

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_fullscreen"):
		_toggle_fullscreen()

func _toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
