extends Node

## SceneManager – autoload singleton for scene switching with hacker-style text transition.

@export_category("Transition")
@export var char_fill_time: float = 0.7
@export var hold_time: float = 0.1
@export var char_clear_time: float = 0.5

@export_category("Appearance")
@export var text_color: Color = Color(0.0, 0.999, 0.0, 1.0)
@export var cell_width: float = 20.0
@export var cell_height: float = 20.0
@export var font_size: int = 20
@export var gibberish_chars: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-=[]{};:,.<>/?\\|"

@export_category("Canvas")
@export var canvas_layer_index: int = 100

var canvas_layer: CanvasLayer
var text_control: TransitionText
var is_transitioning: bool = false

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

func change_scene(scene_path: String) -> void:
	if is_transitioning:
		return
	is_transitioning = true
	await _cover_screen()
	get_tree().change_scene_to_file(scene_path)
	await _settle_scene()
	await _uncover_screen()
	is_transitioning = false

func change_scene_to_packed(scene: PackedScene) -> void:
	if is_transitioning:
		return
	is_transitioning = true
	await _cover_screen()
	get_tree().change_scene_to_packed(scene)
	await _settle_scene()
	await _uncover_screen()
	is_transitioning = false

func reload_current_scene() -> void:
	await change_scene(get_tree().current_scene.scene_file_path)

func _settle_scene() -> void:
	for i in range(5):
		await get_tree().process_frame

func _cover_screen() -> void:
	text_control.visible = true
	text_control.char_fill = 0.0
	text_control.reverse_draw = false
	var tween = create_tween()
	tween.tween_property(text_control, "char_fill", 1.0, char_fill_time)
	await tween.finished
	await get_tree().create_timer(hold_time).timeout

func _uncover_screen() -> void:
	text_control.reverse_draw = true
	var tween = create_tween()
	tween.tween_property(text_control, "char_fill", 0.0, char_clear_time)
	await tween.finished
	text_control.visible = false
	text_control.reverse_draw = false
	text_control.char_fill = 0.0

class TransitionText extends Control:
	var font: Font
	var rng := RandomNumberGenerator.new()
	var font_size: int = 12
	var cell_width: float = 10.0
	var cell_height: float = 16.0
	var text_color: Color = Color(0.0, 1.0, 0.0, 1.0)
	var gibberish_chars: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-=[]{};:,.<>/?\\|"
	
	var char_fill: float = 0.0   # 0..1 – overall fill progress
	var reverse_draw: bool = false
	var column_offsets: Array[int] = []
	var viewport_size: Vector2 = Vector2.ZERO

	func _ready() -> void:
		set_process(true)
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
			# 0, 1, or 2 extra characters of randomness per column
			column_offsets.append(rng.randi_range(0, 4))

	func _process(_delta: float) -> void:
		queue_redraw()

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
				# Top-to-bottom disappearance: keep bottom rows visible,
				# but with the same column offsets to keep the leading edge ragged.
				visible_rows = max(0, base_rows - column_offsets[col])
				# For reverse, draw from bottom up.
				var start_row = rows_total - visible_rows
				for r in range(start_row, rows_total):
					_draw_cell(col, r, cols_total, rows_total)
			else:
				# Top-to-bottom fill: add offsets to front columns.
				visible_rows = min(rows_total, base_rows + column_offsets[col])
				for r in range(visible_rows):
					_draw_cell(col, r, cols_total, rows_total)

	func _draw_cell(col: int, row: int, cols_total: int, rows_total: int) -> void:
		var x = col * cell_width
		var y = row * cell_height
		# Black background
		draw_rect(Rect2(x, y, cell_width, cell_height), Color.BLACK)
		# Random character
		var char_str = gibberish_chars[rng.randi_range(0, gibberish_chars.length() - 1)]
		draw_string(font, Vector2(x, y + cell_height * 0.8), char_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
