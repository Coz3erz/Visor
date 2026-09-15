extends CanvasLayer

## SceneManager.gd — VISOR ocean-iris scene transition.
##
## SETUP:
##   Project Settings > Autoload > add this script, name it "SceneManager", enable it.
##   Do NOT also give this script a `class_name` of "SceneManager" — Godot will not let
##   an autoload singleton share its name with a global class, so this file intentionally
##   has no class_name. Call it globally as SceneManager.change_scene("res://Level.tscn").
##
## LOOK:
##   A deep-ocean aperture. One scalloped opening — abyss navy through teal, with a
##   bright aqua edge — spins and contracts to a point, swaps the scene underneath,
##   then spins back open the SAME direction to reveal it.
##
##   Two elements only, and they are the same shape: the iris itself, and a thin
##   leading ring a beat ahead of it so the closure is announced instead of just
##   appearing. Everything rotates one way, travels one way, at one speed. At this
##   duration anything more reads as clutter.
##
##   No viewport capture, no white flash, no water sim, no particles, no glitch.
##
## USAGE:
##   SceneManager.change_scene("res://scenes/Level2.tscn")
##   SceneManager.return_to_previous_scene()


# ---------------------------------------------------------------------------
# SIGNALS
# ---------------------------------------------------------------------------

signal transition_started(target_path: String)
signal scene_swapped(new_path: String)
signal transition_finished()


# ---------------------------------------------------------------------------
# EXPORTS
# ---------------------------------------------------------------------------

@export_category("Timing")
@export_range(0.05, 2.0, 0.01) var cover_duration: float = 0.34*2
@export_range(0.0, 1.0, 0.01) var hold_duration: float = 0.05*4   ## beat at full closure
@export_range(0.05, 2.0, 0.01) var reveal_duration: float = 0.38*2
@export var cover_trans: Tween.TransitionType = Tween.TRANS_QUART
@export var cover_ease: Tween.EaseType = Tween.EASE_IN     ## accelerates into closure — reads as a slam
@export var reveal_trans: Tween.TransitionType = Tween.TRANS_QUART
@export var reveal_ease: Tween.EaseType = Tween.EASE_OUT   ## explosive open, then settle

@export_category("Ocean Palette")
@export var color_deep: Color = Color(0.015, 0.055, 0.115)  ## abyss navy
@export var color_mid: Color = Color(0.035, 0.235, 0.340)   ## mid-water teal
@export var color_accent: Color = Color(0.36, 0.95, 0.98)   ## bright aqua lens edge

@export_category("Iris Shape")
@export_range(3, 24, 1) var blade_count: int = 6            ## number of aperture blades
@export_range(0.0, 0.95, 0.01) var tooth_depth: float = 0.20 ## how scalloped the edge is — keep low and clean
@export_range(0.5, 40.0, 0.5) var edge_glow_width: float = 5.0 ## px, aqua glow hugging the lens edge
@export var iris_center: Vector2 = Vector2(0.5, 0.5)          ## normalized screen point the lens closes on
@export_range(1.0, 1.5, 0.01) var open_margin: float = 1.08   ## safety margin so "open" never clips on-screen

@export_category("Motion")
@export_range(0.0, 720.0, 1.0) var spin_degrees_cover: float = 55.0
@export_range(0.0, 720.0, 1.0) var spin_degrees_reveal: float = 55.0
@export var reverse_spin_on_return: bool = false  ## off by default so the motion is identical every time

@export_category("Leading Ring")
@export var enable_leading_ring: bool = true
@export_range(0.5, 30.0, 0.5) var ring_width: float = 2.5    ## px thickness
@export_range(0.0, 0.6, 0.01) var ring_lead: float = 0.16    ## how far ahead of the iris it runs when closing
@export_range(0.0, 0.6, 0.01) var ring_lag: float = 0.18     ## how far behind it trails when opening
@export_range(0.0, 1.0, 0.01) var ring_opacity: float = 0.55

@export_category("Logo (Optional)")
@export var logo_texture: Texture2D               ## if set, shown centered mid-transition
@export var logo_size: Vector2 = Vector2(140, 140)
@export var mask_logo_in_circle: bool = true       ## iris-open the logo through a circular mask

@export_category("Behavior")
@export var block_input_during_transition: bool = true
@export_range(1, 200, 1) var canvas_layer_index: int = 128


# ---------------------------------------------------------------------------
# SHADER SOURCE (embedded so the whole effect lives in this one file)
# ---------------------------------------------------------------------------

const IRIS_SHADER_CODE := """
shader_type canvas_item;

uniform float progress : hint_range(-0.3, 1.3) = 0.0;
uniform float ring_progress : hint_range(-0.3, 1.3) = 0.0;
uniform float ring_alpha : hint_range(0.0, 1.0) = 0.0;
uniform float rotation = 0.0;

uniform vec2 screen_size = vec2(1920.0, 1080.0);
uniform vec2 iris_center_uv = vec2(0.5, 0.5);
uniform float open_margin : hint_range(1.0, 1.5) = 1.08;
uniform int blade_count : hint_range(3, 24) = 6;
uniform float tooth_depth : hint_range(0.0, 0.95) = 0.20;
uniform float edge_width_px : hint_range(0.5, 40.0) = 5.0;
uniform float ring_width_px : hint_range(0.5, 30.0) = 2.5;

uniform vec4 color_a : source_color = vec4(0.015, 0.055, 0.115, 1.0);
uniform vec4 color_b : source_color = vec4(0.035, 0.235, 0.340, 1.0);
uniform vec4 color_edge : source_color = vec4(0.36, 0.95, 0.98, 1.0);

// Radius of the scalloped aperture at a given angle, for a given closure amount.
// Both the iris and the leading ring use this with the SAME rotation, so they are
// the same shape travelling the same way — never two competing motions.
float iris_radius(float p, float theta, float open_r, float bc) {
	float teeth = 1.0 + tooth_depth * clamp(p, 0.0, 1.0) * cos(bc * (theta + rotation));
	return max(open_r * (1.0 - p) * teeth, 0.0);
}

void fragment() {
	vec2 center_px = iris_center_uv * screen_size;
	vec2 d = FRAGCOORD.xy - center_px;
	float r = length(d);
	float theta = atan(d.y, d.x);

	// Farthest corner — guarantees "fully open" clears the whole screen.
	float max_r = max(
		max(length(center_px), length(center_px - vec2(screen_size.x, 0.0))),
		max(length(center_px - vec2(0.0, screen_size.y)), length(center_px - screen_size))
	);
	float open_r = max_r * open_margin;
	float bc = float(blade_count);

	float shape_r = iris_radius(progress, theta, open_r, bc);
	float dist = r - shape_r;
	float covered = step(0.0, dist);

	// Alternating blade sectors read as depth bands in the water.
	float sector = floor(mod(theta + rotation, TAU) / TAU * bc);
	vec3 rgb = mix(color_a.rgb, color_b.rgb, mod(sector, 2.0));
	float alpha = covered;

	// Aqua glow on the lens edge.
	float glow = (1.0 - smoothstep(0.0, edge_width_px, abs(dist))) * covered;
	rgb = mix(rgb, color_edge.rgb, glow);
	alpha = max(alpha, glow);

	// Leading / trailing ring — same shape, same rotation, offset in time only.
	float ring_r = iris_radius(ring_progress, theta, open_r, bc);
	float ring = (1.0 - smoothstep(0.0, ring_width_px, abs(r - ring_r))) * (1.0 - covered) * ring_alpha;
	rgb = mix(rgb, color_edge.rgb, ring);
	alpha = max(alpha, ring);

	COLOR = vec4(rgb, clamp(alpha, 0.0, 1.0));
}
"""

const LOGO_MASK_SHADER_CODE := """
shader_type canvas_item;

uniform float mask_progress : hint_range(0.0, 1.0) = 1.0;
uniform float edge_softness : hint_range(0.0, 0.2) = 0.05;

void fragment() {
	vec2 uv = (UV - vec2(0.5)) * 2.0;
	float d = length(uv);
	float alpha = 1.0 - smoothstep(mask_progress - edge_softness, mask_progress, d);
	vec4 tex_color = texture(TEXTURE, UV);
	COLOR = vec4(tex_color.rgb, tex_color.a * alpha);
}
"""


# ---------------------------------------------------------------------------
# PRIVATE STATE
# ---------------------------------------------------------------------------

var _overlay: Control
var _iris_rect: ColorRect
var _logo: TextureRect
var _iris_material: ShaderMaterial
var _logo_material: ShaderMaterial
var _active_tween: Tween
var _is_transitioning: bool = false
var _current_scene_path: String = ""
var _scene_history: Array[String] = []


# ---------------------------------------------------------------------------
# LIFECYCLE
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = canvas_layer_index
	process_mode = Node.PROCESS_MODE_ALWAYS  # transition can still play even if gameplay is paused
	_build_overlay()

	var cs := get_tree().current_scene
	_current_scene_path = cs.scene_file_path if cs else ""


# ---------------------------------------------------------------------------
# PUBLIC API
# ---------------------------------------------------------------------------

func change_scene(path: String) -> void:
	if _is_transitioning:
		push_warning("SceneManager: change_scene ignored, a transition is already in progress.")
		return
	if not (path.begins_with("res://") or path.begins_with("user://")):
		push_error("SceneManager: '%s' is not a valid scene path." % path)
		return

	_is_transitioning = true
	_scene_history.append(_current_scene_path)
	await _run_transition(path, false)


func return_to_previous_scene() -> void:
	if _is_transitioning:
		push_warning("SceneManager: return_to_previous_scene ignored, a transition is already in progress.")
		return
	if _scene_history.is_empty():
		push_warning("SceneManager: no previous scene to return to.")
		return

	var prev_path: String = _scene_history.pop_back()
	if prev_path.is_empty():
		push_warning("SceneManager: previous scene path is empty; cannot return.")
		return

	_is_transitioning = true
	await _run_transition(prev_path, true)


# ---------------------------------------------------------------------------
# INTERNAL TRANSITION LOGIC
#
# Three tweened values total: closure, ring closure, rotation. All on ONE Tween.
# The ring only reads as "ahead" or "behind" because its tween is given a shorter
# duration / a delay on that same timeline — never a second Tween, and never an
# opposing direction.
# ---------------------------------------------------------------------------

func _run_transition(target_path: String, reverse: bool) -> void:
	transition_started.emit(target_path)
	_apply_visual_params()

	var spin_dir: float = -1.0 if (reverse and reverse_spin_on_return) else 1.0
	var spin_cover_rad := deg_to_rad(spin_degrees_cover) * spin_dir
	var spin_reveal_rad := deg_to_rad(spin_degrees_reveal) * spin_dir

	_reset_shader_state()
	_overlay.visible = true

	var load_err := ResourceLoader.load_threaded_request(target_path)
	if load_err != OK:
		push_warning("SceneManager: threaded load request failed (%d) for '%s'; will fall back to a direct load." % [load_err, target_path])

	var tw := create_tween()
	_active_tween = tw

	# ---------------- close ----------------
	tw.set_parallel(true)
	tw.tween_method(_set_iris_progress, 0.0, 1.0, cover_duration).set_trans(cover_trans).set_ease(cover_ease)
	tw.tween_method(_set_rotation, 0.0, spin_cover_rad, cover_duration).set_trans(cover_trans).set_ease(cover_ease)

	if enable_leading_ring:
		# Shorter duration on the same timeline => it arrives first.
		var ring_dur: float = maxf(cover_duration * (1.0 - ring_lead), 0.01)
		tw.tween_method(_set_ring_progress, 0.0, 1.0, ring_dur).set_trans(cover_trans).set_ease(cover_ease)
		tw.tween_method(_set_ring_alpha, 0.0, ring_opacity, cover_duration * 0.3)

	if _logo:
		var logo_delay: float = cover_duration * 0.25
		var logo_dur: float = cover_duration - logo_delay
		tw.tween_property(_logo, "modulate:a", 1.0, logo_dur).set_delay(logo_delay)
		if _logo_material:
			tw.tween_method(_set_logo_mask, 0.0, 1.0, logo_dur).set_delay(logo_delay)

	# ---------------- fully closed, scene swaps underneath ----------------
	tw.set_parallel(false)
	if hold_duration > 0.0:
		tw.tween_interval(hold_duration)
	tw.tween_callback(_perform_scene_swap.bind(target_path))

	# ---------------- open, same direction ----------------
	tw.set_parallel(true)
	tw.tween_method(_set_iris_progress, 1.0, 0.0, reveal_duration).set_trans(reveal_trans).set_ease(reveal_ease)
	tw.tween_method(_set_rotation, spin_cover_rad, spin_cover_rad + spin_reveal_rad, reveal_duration).set_trans(reveal_trans).set_ease(reveal_ease)

	if enable_leading_ring:
		# Delayed on the same timeline => it leaves last.
		var lag_delay: float = reveal_duration * ring_lag
		tw.tween_method(_set_ring_progress, 1.0, 0.0, maxf(reveal_duration - lag_delay, 0.01)) \
			.set_delay(lag_delay).set_trans(reveal_trans).set_ease(reveal_ease)
		tw.tween_method(_set_ring_alpha, ring_opacity, 0.0, reveal_duration)

	if _logo:
		tw.tween_property(_logo, "modulate:a", 0.0, reveal_duration)
		if _logo_material:
			tw.tween_method(_set_logo_mask, 1.0, 0.0, reveal_duration)

	tw.set_parallel(false)
	tw.tween_callback(_finish_transition)

	await tw.finished


func _perform_scene_swap(target_path: String) -> void:
	var packed: PackedScene = null
	var status := ResourceLoader.load_threaded_get_status(target_path)

	if status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE or status == ResourceLoader.THREAD_LOAD_FAILED:
		push_warning("SceneManager: threaded load failed for '%s'; retrying with a direct load." % target_path)
		packed = load(target_path)
	else:
		# Blocks only if the background load genuinely isn't done yet — and the screen
		# is fully covered by the closed iris at this exact instant, so it's invisible.
		packed = ResourceLoader.load_threaded_get(target_path)

	if packed == null:
		push_error("SceneManager: could not load scene '%s'. Keeping the current scene." % target_path)
		return

	var tree := get_tree()
	var old_scene := tree.current_scene
	var new_scene := packed.instantiate()

	tree.root.add_child(new_scene)
	tree.current_scene = new_scene
	if old_scene:
		old_scene.queue_free()

	_current_scene_path = target_path
	scene_swapped.emit(target_path)


func _finish_transition() -> void:
	_overlay.visible = false
	_active_tween = null
	_is_transitioning = false
	_reset_shader_state()
	transition_finished.emit()


func _reset_shader_state() -> void:
	_iris_material.set_shader_parameter("progress", 0.0)
	_iris_material.set_shader_parameter("ring_progress", 0.0)
	_iris_material.set_shader_parameter("ring_alpha", 0.0)
	_iris_material.set_shader_parameter("rotation", 0.0)
	_iris_material.set_shader_parameter("iris_center_uv", iris_center)

	if _logo:
		_logo.modulate.a = 0.0
		if _logo_material:
			_logo_material.set_shader_parameter("mask_progress", 0.0)


# --- Tween-driven setters (kept tiny so the timeline above stays readable) --

func _set_iris_progress(value: float) -> void:
	_iris_material.set_shader_parameter("progress", value)

func _set_ring_progress(value: float) -> void:
	_iris_material.set_shader_parameter("ring_progress", value)

func _set_ring_alpha(value: float) -> void:
	_iris_material.set_shader_parameter("ring_alpha", value)

func _set_rotation(value: float) -> void:
	_iris_material.set_shader_parameter("rotation", value)

func _set_logo_mask(value: float) -> void:
	if _logo_material:
		_logo_material.set_shader_parameter("mask_progress", value)


# ---------------------------------------------------------------------------
# OVERLAY CONSTRUCTION (runs once; the overlay is hidden and reused after
# each transition rather than rebuilt, so there's zero per-transition cost
# and zero permanent visible UI in between transitions)
# ---------------------------------------------------------------------------

func _apply_visual_params() -> void:
	_iris_material.set_shader_parameter("color_a", color_deep)
	_iris_material.set_shader_parameter("color_b", color_mid)
	_iris_material.set_shader_parameter("color_edge", color_accent)
	_iris_material.set_shader_parameter("blade_count", blade_count)
	_iris_material.set_shader_parameter("tooth_depth", tooth_depth)
	_iris_material.set_shader_parameter("edge_width_px", edge_glow_width)
	_iris_material.set_shader_parameter("iris_center_uv", iris_center)
	_iris_material.set_shader_parameter("open_margin", open_margin)
	_iris_material.set_shader_parameter("ring_width_px", ring_width)
	_update_screen_size()


func _update_screen_size() -> void:
	if _iris_material:
		_iris_material.set_shader_parameter("screen_size", get_viewport().get_visible_rect().size)


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP if block_input_during_transition else Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	add_child(_overlay)

	_iris_rect = ColorRect.new()
	_iris_rect.name = "Iris"
	_iris_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_iris_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_iris_rect.color = Color(0.015, 0.055, 0.115, 1.0)  # dark safety fallback if the shader ever fails to compile

	_iris_material = ShaderMaterial.new()
	var iris_shader := Shader.new()
	iris_shader.code = IRIS_SHADER_CODE
	_iris_material.shader = iris_shader
	_iris_rect.material = _iris_material
	_overlay.add_child(_iris_rect)

	get_viewport().size_changed.connect(_update_screen_size)
	_update_screen_size()

	if logo_texture:
		_logo = TextureRect.new()
		_logo.name = "Logo"
		_logo.texture = logo_texture
		_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_logo.custom_minimum_size = logo_size
		_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_logo.modulate.a = 0.0
		_logo.pivot_offset = logo_size * 0.5

		_logo.anchor_left = 0.5
		_logo.anchor_top = 0.5
		_logo.anchor_right = 0.5
		_logo.anchor_bottom = 0.5
		_logo.offset_left = -logo_size.x * 0.5
		_logo.offset_top = -logo_size.y * 0.5
		_logo.offset_right = logo_size.x * 0.5
		_logo.offset_bottom = logo_size.y * 0.5

		if mask_logo_in_circle:
			_logo_material = ShaderMaterial.new()
			var logo_shader := Shader.new()
			logo_shader.code = LOGO_MASK_SHADER_CODE
			_logo_material.shader = logo_shader
			_logo.material = _logo_material

		_overlay.add_child(_logo)
