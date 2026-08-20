extends Button

@export_group("Text")
@export var button_text: String = "Button"
@export var font_size: int = 24
@export var text_color: Color = Color.WHITE
@export var text_hover_color: Color = Color(0.0, 1.0, 1.0, 1.0)

@export_group("Glitch Effect")
@export var normal_intensity: float = 0.08
@export var hover_intensity: float = 2.5
@export var chromatic_offset: float = 2.5
@export var burst_rate: float = 1.0
@export var burst_strength: float = 6.0
@export var burst_duration: float = 0.1

# Static line effect
@export var max_static_lines: int = 9            # target count when hovered
@export var static_line_pool_size: int = 20      # total nodes for random appearing
@export var static_line_height: float = 0.5      # thickness of each line (can be as low as 0.1)
@export var static_line_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var static_line_opacity: float = 1.0     # global opacity for static lines
@export var static_dispersion_x: float = 120.0
@export var static_dispersion_y: float = 60.0
@export var static_count_change_rate: float = 200.0   # how fast desired count changes (very fast)
@export var static_line_min_lifetime: float = 0.01
@export var static_line_max_lifetime: float = 0.05

@export_group("Layout")
@export var auto_center: bool = true
@export var screen_offset: Vector2 = Vector2.ZERO

var main_label: Label
var red_label: Label
var blue_label: Label
var static_line_nodes: Array = []   # all possible ColorRects
var active_lines: Array = []        # references to currently active lines with lifetime

var is_hovered: bool = false
var time: float = 0.0
var burst_timer: float = 0.0
var current_intensity: float = 0.0
var desired_static_count: float = 0.0
var actual_static_count: float = 0.0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	flat = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = false

	add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_theme_stylebox_override("disabled", StyleBoxEmpty.new())

	text = ""

	main_label = _create_label(button_text, text_color)
	red_label = _create_label(button_text, Color(1, 0, 0, 0.8))
	blue_label = _create_label(button_text, Color(0, 0, 1, 0.8))

	main_label.z_index = 2
	red_label.z_index = 1
	blue_label.z_index = 1

	# Create pool of static line ColorRects
	for i in range(static_line_pool_size):
		var line := ColorRect.new()
		line.color = static_line_color
		line.size = Vector2(0, static_line_height)
		line.visible = false
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(line)
		static_line_nodes.append(line)

	size = main_label.get_minimum_size() + Vector2(20, 10)

	if auto_center:
		_center_button()
		get_viewport().size_changed.connect(_center_button)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _create_label(text_content: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text_content
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(lbl)
	return lbl

func _center_button() -> void:
	position = get_viewport_rect().size * 0.5 + screen_offset - size * 0.5

func _on_mouse_entered() -> void:
	is_hovered = true
	main_label.add_theme_color_override("font_color", text_hover_color)

func _on_mouse_exited() -> void:
	is_hovered = false
	main_label.add_theme_color_override("font_color", text_color)

func _process(delta: float) -> void:
	time += delta
	current_intensity = lerp(current_intensity,
		hover_intensity if is_hovered else normal_intensity, 10.0 * delta)

	if burst_timer > 0:
		burst_timer -= delta
	else:
		if rng.randf() < burst_rate * delta:
			burst_timer = burst_duration

	# Chromatic offsets for labels
	var off_red := Vector2.ZERO
	var off_blue := Vector2.ZERO
	var off_main := Vector2.ZERO

	var burst_power := 1.0 if burst_timer > 0 else 0.0
	var chrom = chromatic_offset * current_intensity

	off_red.x = rng.randf_range(-chrom, chrom) + burst_power * rng.randf_range(-burst_strength, burst_strength)
	off_red.y = rng.randf_range(-chrom, chrom) * 0.5 + burst_power * rng.randf_range(-burst_strength, burst_strength) * 0.5
	off_blue = -off_red
	off_main = Vector2(
		rng.randf_range(-burst_strength, burst_strength) * burst_power,
		rng.randf_range(-burst_strength, burst_strength) * burst_power * 0.5
	)

	_set_label_offset(red_label, off_red)
	_set_label_offset(blue_label, off_blue)
	_set_label_offset(main_label, off_main)

	# Desired static line count
	desired_static_count = max_static_lines if is_hovered else 0.0
	actual_static_count = move_toward(actual_static_count, desired_static_count, static_count_change_rate * delta)

	# Manage active lines to match actual_static_count
	var current_active = active_lines.size()
	var target_active = int(round(actual_static_count))

	# Add lines if needed
	while current_active < target_active:
		_spawn_static_line()
		current_active += 1

	# Remove lines if needed
	while current_active > target_active:
		_despawn_static_line()
		current_active -= 1

	# Update lifetime and remove expired lines
	for i in range(active_lines.size() - 1, -1, -1):
		var entry = active_lines[i]
		entry["lifetime"] -= delta
		if entry["lifetime"] <= 0.0:
			_despawn_static_line_at(i)
		else:
			# Apply global opacity
			entry["node"].modulate.a = static_line_opacity

func _spawn_static_line() -> void:
	# Find an inactive line node
	for line in static_line_nodes:
		if not line.visible:
			var center = size * 0.5
			var angle = rng.randf_range(0.0, TAU)
			var radius_mult = rng.randf_range(0.5, 1.0)
			var rx = static_dispersion_x * radius_mult
			var ry = static_dispersion_y * radius_mult
			var pos = Vector2(
				center.x + cos(angle) * rx,
				center.y + sin(angle) * ry
			)
			var line_width = rng.randf_range(20.0, 80.0)
			line.size.x = line_width
			line.size.y = static_line_height
			line.position = pos - Vector2(line_width * 0.5, static_line_height * 0.5)
			line.color = static_line_color
			line.visible = true
			line.modulate.a = static_line_opacity
			var lifetime = rng.randf_range(static_line_min_lifetime, static_line_max_lifetime)
			active_lines.append({"node": line, "lifetime": lifetime})
			return

func _despawn_static_line() -> void:
	if active_lines.size() > 0:
		_despawn_static_line_at(0)   # remove first

func _despawn_static_line_at(index: int) -> void:
	var entry = active_lines[index]
	entry["node"].visible = false
	active_lines.remove_at(index)

func _set_label_offset(lbl: Label, off: Vector2) -> void:
	lbl.offset_left = off.x
	lbl.offset_right = off.x
	lbl.offset_top = off.y
	lbl.offset_bottom = off.y
