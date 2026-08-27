extends Node

@export_category("Transition")
@export var transition_fps: float = 12.0
@export var char_fill_time: float = 0.6
@export var hold_time: float = 0.4
@export var char_clear_time: float = 0.6
@export var extra_rows: int = 10

@export_category("Appearance")
@export var text_color: Color = Color(0.0, 1.0, 0.0, 1.0)
@export var cell_width: float = 24.0
@export var cell_height: float = 24.0
@export var font_size: int = 24
@export var gibberish_chars: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-=[]{};:,.<>/?\\|"

@export_category("Canvas")
@export var canvas_layer_index: int = 100

var canvas_layer: CanvasLayer
var text_control: TransitionText
var transition_timer: Timer
var is_transitioning: bool = false
var previous_scene_path: String = ""

func _ready() -> void:
	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = canvas_layer_index
	add_child(canvas_layer)

	text_control = TransitionText.new()
	text_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_control.font_size = font_size
	text_control.cell_width = cell_width
	text_control.cell_height = cell_height
	text_control.text_color = text_color
	text_control.gibberish_chars = gibberish_chars
	text_control.char_fill = 0.0
	text_control.reverse_draw = false
	canvas_layer.add_child(text_control)

	transition_timer = Timer.new()
	transition_timer.wait_time = 1.0 / transition_fps
	transition_timer.autostart = false
	transition_timer.timeout.connect(_on_transition_tick)
	add_child(transition_timer)

func change_scene(scene_path: String) -> void:
	if is_transitioning:
		return
	is_transitioning = true
	previous_scene_path = get_tree().current_scene.scene_file_path
	await _cover_screen()
	get_tree().change_scene_to_file(scene_path)
	await _settle_scene()
	await _uncover_screen()
	is_transitioning = false

func return_to_previous_scene() -> void:
	if previous_scene_path != "":
		change_scene(previous_scene_path)
	else:
		change_scene("res://scenes/main/main_menu.tscn")

func _settle_scene() -> void:
	for i in range(5):
		await get_tree().process_frame

func _cover_screen() -> void:
	text_control.visible = true
	text_control.char_fill = 0.0
	text_control.reverse_draw = false
	text_control.extra_rows = extra_rows
	transition_timer.start()
	var tween = create_tween()
	tween.tween_property(text_control, "char_fill", 1.0, char_fill_time)
	await tween.finished
	text_control.char_fill = 1.0
	transition_timer.stop()
	await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(hold_time).timeout

func _uncover_screen() -> void:
	text_control.reverse_draw = true
	text_control.extra_rows = extra_rows
	transition_timer.start()
	var tween = create_tween()
	tween.tween_property(text_control, "char_fill", 0.0, char_clear_time)
	await tween.finished
	transition_timer.stop()
	await get_tree().create_timer(0.1).timeout
	text_control.visible = false
	text_control.reverse_draw = false
	text_control.char_fill = 0.0

func _on_transition_tick() -> void:
	text_control.queue_redraw()

class TransitionText extends Control:
	var font: Font
	var rng := RandomNumberGenerator.new()
	var font_size: int = 16
	var cell_width: float = 16.0
	var cell_height: float = 16.0
	var text_color: Color = Color(0.0, 1.0, 0.0, 1.0)
	var gibberish_chars: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-=[]{};:,.<>/?\\|"
	var char_fill: float = 0.0
	var reverse_draw: bool = false
	var column_offsets: Array[int] = []
	var viewport_size: Vector2 = Vector2.ZERO
	var extra_rows: int = 0

	func _ready() -> void:
		set_process(false)
		rng.randomize()
		font = SystemFont.new()
		font.font_names = PackedStringArray(["Courier New", "monospace"])
		get_viewport().size_changed.connect(_on_viewport_resized)
		_on_viewport_resized()

	func _on_viewport_resized() -> void:
		var new_size = get_viewport_rect().size
		if new_size != viewport_size:
			viewport_size = new_size
			_generate_column_offsets()

	func _generate_column_offsets() -> void:
		var cols = int(ceil(viewport_size.x / cell_width))
		column_offsets.clear()
		for i in range(cols):
			column_offsets.append(rng.randi_range(0, 2))

	func _draw() -> void:
		if char_fill <= 0.0 or viewport_size == Vector2.ZERO:
			return
		var rows_total = int(ceil(viewport_size.y / cell_height))
		var cols_total = int(ceil(viewport_size.x / cell_width))
		if cols_total != column_offsets.size():
			_generate_column_offsets()

		var base_rows = int(rows_total * char_fill)

		for col in range(cols_total):
			var visible_rows = base_rows
			if reverse_draw:
				visible_rows = max(0, base_rows - column_offsets[col] - extra_rows)
				var start_row = rows_total - visible_rows
				for r in range(start_row, rows_total):
					_draw_cell(col, r)
			else:
				visible_rows = min(rows_total, base_rows + column_offsets[col] + extra_rows)
				for r in range(visible_rows):
					_draw_cell(col, r)

	func _draw_cell(col: int, row: int) -> void:
		var x = col * cell_width
		var y = row * cell_height
		draw_rect(Rect2(x, y, cell_width, cell_height), Color.BLACK)
		var char_str = gibberish_chars[rng.randi_range(0, gibberish_chars.length() - 1)]
		draw_string(font, Vector2(x, y + cell_height * 0.8), char_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
