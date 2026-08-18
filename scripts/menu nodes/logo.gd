extends RichTextLabel

@export var rotation_speed: float = 1.1
@export var rotation_amplitude: float = 0.1
@export var rotation_offset: float = 0.05

@export var scale_duration: float = 2.0
@export var min_scale: float = 0.6
@export var max_scale: float = 0.7
@export var scale_smoothing: float = 1.8

@export var auto_center_pivot: bool = true

var time: float = 0.0

func _ready() -> void:
	if auto_center_pivot:
		pivot_offset = size / 2

func _process(delta: float) -> void:
	time += delta

	# Update pivot if size changes
	if auto_center_pivot:
		pivot_offset = size / 2

	# Rotation from sine wave
	rotation = sin(time * rotation_speed) * rotation_amplitude + rotation_offset

	# Scale bouncing from max to min over scale_duration
	var scale_progress = fmod(time, scale_duration) / scale_duration
	var current_scale = max_scale - (scale_progress * (max_scale - min_scale))
	var target_scale = Vector2(current_scale, current_scale)

	# Smooth scale interpolation (same feel as logo)
	scale += (target_scale - scale) / scale_smoothing
