extends Button

@export_group("Text")
@export var button_text: String = "Button"
@export var font_size: int = 24
@export var text_color: Color = Color.WHITE

@export_group("Glitch Effect")
@export var normal_intensity: float = 0.08
@export var hover_intensity: float = 2.5
@export var chromatic_offset: float = 2.5
@export var static_line_count: int = 5
@export var burst_rate: float = 1.0
@export var burst_strength: float = 6.0
@export var burst_duration: float = 0.1

@export_group("Layout")
@export var auto_center: bool = true
@export var screen_offset: Vector2 = Vector2.ZERO

var main_label: Label
var red_label: Label
var blue_label: Label
var static_lines: Array = []   # stores ColorRects now parented to viewport

var is_hovered: bool = false
var time: float = 0.0
var burst_timer: float = 0.0
var current_intensity: float = 0.0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	flat = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Transparent button background
	add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_theme_stylebox_override("disabled", StyleBoxEmpty.new())

	# Hide built-in text; we use custom labels
	text = ""

	# Create base labels (main, red ghost, blue ghost)
	main_label = _create_label(button_text, text_color)
	red_label = _create_label(button_text, Color(1, 0, 0, 0.8))
	blue_label = _create_label(button_text, Color(0, 0, 1, 0.8))

	# Red and blue are behind main, but we can reorder later
	main_label.z_index = 2
	red_label.z_index = 1
	blue_label.z_index = 1

	# Create static line rectangles on the viewport (so they can roam the whole screen)
	for i in range(static_line_count):
		var line := ColorRect.new()
		line.color = Color(0.3, 0.5, 1.0, 0.7)
		line.size = Vector2(0, 2)
		line.visible = false
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Add to the viewport, not the button, so positions can be global
		get_viewport().add_child(line)
		static_lines.append(line)

	# Resize button to fit main label
	size = main_label.get_minimum_size() + Vector2(20, 10)

	# Position
	if auto_center:
		_center_button()
		get_viewport().size_changed.connect(_center_button)

	# Hover signals
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _create_label(text_content: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text_content
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Use full rect anchors so label fills the button
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(lbl)
	return lbl

func _center_button() -> void:
	position = get_viewport_rect().size * 0.5 + screen_offset - size * 0.5

func _on_mouse_entered() -> void:
	is_hovered = true

func _on_mouse_exited() -> void:
	is_hovered = false

func _process(delta: float) -> void:
	time += delta
	current_intensity = lerp(current_intensity,
		hover_intensity if is_hovered else normal_intensity, 10.0 * delta)

	# Random glitch burst
	if burst_timer > 0:
		burst_timer -= delta
	else:
		if rng.randf() < burst_rate * delta:
			burst_timer = burst_duration

	# Calculate random offsets for labels
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

	# Apply offsets to labels using offset properties
	_set_label_offset(red_label, off_red)
	_set_label_offset(blue_label, off_blue)
	_set_label_offset(main_label, off_main)

	# Static lines visibility and random positions across the viewport
	var lines_visible = false
	if burst_timer > 0 or rng.randf() < current_intensity * 0.3:
		lines_visible = true

	var viewport_size = get_viewport_rect().size
	for line in static_lines:
		line.visible = false
		if lines_visible:
			line.visible = true
			# Random width and position anywhere on screen
			var line_width = rng.randf_range(50.0, 300.0)
			line.size.x = line_width
			# Position anywhere within the viewport
			line.position = Vector2(
				rng.randf_range(0.0, viewport_size.x - line_width),
				rng.randf_range(0.0, viewport_size.y)
			)

func _set_label_offset(lbl: Label, off: Vector2) -> void:
	lbl.offset_left = off.x
	lbl.offset_right = off.x
	lbl.offset_top = off.y
	lbl.offset_bottom = off.y

func _exit_tree() -> void:
	# Clean up static lines when button is destroyed
	for line in static_lines:
		if is_instance_valid(line):
			line.queue_free()
	static_lines.clear()
