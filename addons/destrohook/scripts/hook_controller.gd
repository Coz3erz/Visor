@icon("res://addons/destrohook/textures/hook.png")
class_name HookController
extends Node

@export_group("Controls")
@export var launch_action_name: String = "grapple"          # hold to keep hooked
@export var thrust_action_name: String = "jump"             # jump for thrust boost

@export_group("References")
@export var hook_scene: PackedScene
@export var player_body: CharacterBody3D
@export var hook_raycast: RayCast3D
@export var hook_source: Node3D

@export_group("Settings")
@export var thrust_mult: float = 15.0
var rest_length: float = 2.0
@export var stiffness: float = 30.0
@export var damping: float = 3.0

@export var hand_offset: Vector3 = Vector3(0.3, -0.3, -0.5)

@export var max_wraps: int = 4
@export var wrap_offset: float = 0.2

var is_hook_launched: bool = false
var is_retracting: bool = false
var _hook_model: Node3D = null
var hook_target_normal: Vector3 = Vector3.ZERO
var hook_target_node: Marker3D = null

var wrap_points: Array = []

var rope_mesh: ImmediateMesh
var rope_mesh_instance: MeshInstance3D
var rope_material: StandardMaterial3D

# Visual parameters – enormous glowing blue, subtle white outline
const ROPE_RADIUS: float = 0.5
const OUTLINE_THICKNESS: float = 0.01
const EMISSION_ENERGY: float = 12.0
const SAG_AMOUNT: float = 0.3
const EXTEND_SPEED: float = 8.0
var rope_extend_anim: float = 0.0

signal hook_launched()
signal hook_attached(body)
signal hook_detached()

func _ready() -> void:
	hook_raycast.add_exception(player_body)

	rope_mesh = ImmediateMesh.new()
	rope_mesh_instance = MeshInstance3D.new()
	rope_mesh_instance.mesh = rope_mesh
	rope_mesh_instance.top_level = true
	add_child(rope_mesh_instance)

	rope_material = StandardMaterial3D.new()
	rope_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	rope_material.albedo_color = Color(0.0, 0.5, 1.0, 1.0)
	rope_material.emission_enabled = true
	rope_material.emission = Color(0.0, 0.6, 1.0, 1.0)
	rope_material.emission_energy_multiplier = EMISSION_ENERGY

	var outline = StandardMaterial3D.new()
	outline.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	outline.cull_mode = StandardMaterial3D.CULL_FRONT
	outline.albedo_color = Color.WHITE
	outline.grow = true
	outline.grow_amount = OUTLINE_THICKNESS

	rope_material.next_pass = outline
	rope_mesh_instance.material_override = rope_material

func _physics_process(delta: float) -> void:
	var grapple_held = Input.is_action_pressed(launch_action_name)

	if grapple_held and not is_hook_launched:
		_launch_hook()
		is_retracting = false
	elif not grapple_held and is_hook_launched and not is_retracting:
		is_retracting = true

	if is_hook_launched:
		if is_retracting:
			rope_extend_anim = move_toward(rope_extend_anim, 0.0, delta * EXTEND_SPEED)
			if rope_extend_anim <= 0.0:
				_retract_hook()
				return
		else:
			rope_extend_anim = move_toward(rope_extend_anim, 1.0, delta * EXTEND_SPEED)

		if not is_retracting:
			_handle_hook(delta)

		_update_wrapping()
		_draw_wrapping_rope()

func _launch_hook() -> void:
	if not hook_raycast.is_colliding():
		return

	is_hook_launched = true
	is_retracting = false
	hook_attached.emit()

	var body: Node3D = hook_raycast.get_collider()
	hook_target_node = Marker3D.new()
	body.add_child(hook_target_node)
	hook_target_node.global_position = hook_raycast.get_collision_point()
	hook_target_normal = hook_raycast.get_collision_normal()

	rest_length = player_body.global_position.distance_to(hook_target_node.global_position)

	_hook_model = hook_scene.instantiate()
	add_child(_hook_model)
	_hook_model.visible = false

	wrap_points.clear()
	rope_extend_anim = 0.0

func _retract_hook() -> void:
	is_hook_launched = false
	is_retracting = false
	hook_target_node.queue_free()
	_hook_model.queue_free()
	rope_mesh.clear_surfaces()
	wrap_points.clear()
	rope_extend_anim = 0.0
	hook_detached.emit()

func _handle_hook(delta: float) -> void:
	var pivot = hook_target_node.global_position
	if wrap_points.size() > 0:
		pivot = wrap_points[0]

	var pull_vector = (pivot - player_body.global_position).normalized()
	var distance = player_body.global_position.distance_to(pivot)

	var spring_force_magnitude = stiffness * (distance - rest_length)
	if spring_force_magnitude > 0:
		spring_force_magnitude *= 2
	else:
		spring_force_magnitude = 0

	var relative_velocity = -player_body.velocity
	var damping_force_magnitude = damping * relative_velocity.dot(pull_vector)
	var total_force = (spring_force_magnitude + damping_force_magnitude) * pull_vector

	# Prevent vertical lift while on the ground
	if player_body.is_on_floor():
		total_force.y = 0.0
		if player_body.velocity.y <= 0.0:
			player_body.velocity.y = min(player_body.velocity.y, 0.0)

	if Input.is_action_just_pressed(thrust_action_name):
		player_body.velocity += pull_vector * thrust_mult

	player_body.velocity += total_force * delta

	var source_position = hook_source.global_position if hook_source else player_body.global_position
	_hook_model.extend_from_to(source_position, hook_target_node.global_position, hook_target_normal, delta)

func _update_wrapping() -> void:
	var space_state = player_body.get_world_3d().direct_space_state
	var hand_pos = _get_hand_position()
	var target = hook_target_node.global_position

	var new_wraps: Array = []
	var current_start = hand_pos
	var active_target = target

	for i in range(max_wraps):
		if current_start.distance_to(active_target) < 0.3:
			break
		var query = PhysicsRayQueryParameters3D.create(current_start, active_target)
		query.exclude = [player_body.get_rid()]
		var result = space_state.intersect_ray(query)
		if not result:
			break
		var hit = result.position
		if hit.distance_to(active_target) < 0.3:
			break
		var normal = result.normal
		if normal.length_squared() < 0.01:
			normal = (current_start - hit).normalized()
		var corner = hit + normal * wrap_offset
		new_wraps.append(corner)
		current_start = corner
		active_target = target

	wrap_points = new_wraps

func _draw_wrapping_rope() -> void:
	rope_mesh.clear_surfaces()
	var hand_pos = _get_hand_position()
	var polyline = [hand_pos] + wrap_points + [hook_target_node.global_position]
	if polyline.size() < 2:
		return

	const SEGMENTS = 36
	const RADIAL_STEPS = 6

	var total_length = 0.0
	var seg_lengths = []
	for i in range(polyline.size() - 1):
		var l = polyline[i].distance_to(polyline[i + 1])
		total_length += l
		seg_lengths.append(l)

	var extend_dist = total_length * rope_extend_anim

	# Full smooth curve (for tangents/normals)
	var smooth_points = []
	for i in range(SEGMENTS + 1):
		var t = float(i) / SEGMENTS
		var target_dist = total_length * t
		var cum = 0.0
		var found = false
		for j in range(polyline.size() - 1):
			if cum + seg_lengths[j] >= target_dist:
				var local_t = (target_dist - cum) / seg_lengths[j] if seg_lengths[j] > 0 else 0.0
				smooth_points.append(polyline[j].lerp(polyline[j + 1], local_t))
				found = true
				break
			cum += seg_lengths[j]
		if not found:
			smooth_points.append(polyline.back())

	var tangents = []
	for i in range(smooth_points.size()):
		var p = smooth_points[i]
		var fwd: Vector3
		if i == 0:
			fwd = (smooth_points[1] - p).normalized()
		elif i == smooth_points.size() - 1:
			fwd = (p - smooth_points[i - 1]).normalized()
		else:
			fwd = (smooth_points[i + 1] - smooth_points[i - 1]).normalized()
		tangents.append(fwd)

	var normals = []
	var up = Vector3.UP
	if abs(tangents[0].dot(up)) > 0.99: up = Vector3.FORWARD
	normals.append(tangents[0].cross(up).normalized())
	for i in range(1, smooth_points.size()):
		var prev_normal = normals[i - 1]
		var tangent = tangents[i]
		var axis = tangents[i - 1].cross(tangent)
		if axis.length() > 0.001:
			axis = axis.normalized()
			var angle = acos(clamp(tangents[i - 1].dot(tangent), -1.0, 1.0))
			normals.append(prev_normal.rotated(axis, angle))
		else:
			normals.append(prev_normal)

	# Visible points (up to extend_dist)
	var path_points = []
	var cum = 0.0
	path_points.append(polyline[0])
	for i in range(polyline.size() - 1):
		var seg_len = seg_lengths[i]
		if cum + seg_len >= extend_dist:
			var local_t = (extend_dist - cum) / seg_len if seg_len > 0 else 0.0
			path_points.append(polyline[i].lerp(polyline[i + 1], local_t))
			break
		cum += seg_len
		path_points.append(polyline[i + 1])

	if path_points.size() < 2:
		return

	# Sag (heavy droop)
	for i in range(path_points.size()):
		var t = float(i) / max(path_points.size() - 1, 1)
		path_points[i] += Vector3.DOWN * SAG_AMOUNT * sin(t * PI)

	# Build the tube mesh – both ends tapered to zero
	rope_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings = []
	for i in range(path_points.size()):
		var p = path_points[i]
		var idx = int(round(i * float(smooth_points.size() - 1) / max(path_points.size() - 1, 1)))
		var fwd = tangents[min(idx, tangents.size() - 1)]
		var normal = normals[min(idx, normals.size() - 1)]
		var binormal = fwd.cross(normal).normalized()

		var r: float
		if i == 0 or i == path_points.size() - 1:
			r = 0.0
		else:
			r = ROPE_RADIUS

		var ring = []
		for j in range(RADIAL_STEPS):
			var angle = float(j) * 2.0 * PI / RADIAL_STEPS
			var n = (normal * cos(angle) + binormal * sin(angle)).normalized()
			ring.append({"pos": p + n * r, "normal": n})
		rings.append(ring)

	for i in range(rings.size() - 1):
		var r1 = rings[i]; var r2 = rings[i + 1]
		for j in range(RADIAL_STEPS):
			var nj = (j + 1) % RADIAL_STEPS
			rope_mesh.surface_set_normal(r1[j].normal); rope_mesh.surface_add_vertex(r1[j].pos)
			rope_mesh.surface_set_normal(r1[nj].normal); rope_mesh.surface_add_vertex(r1[nj].pos)
			rope_mesh.surface_set_normal(r2[j].normal); rope_mesh.surface_add_vertex(r2[j].pos)

			rope_mesh.surface_set_normal(r1[nj].normal); rope_mesh.surface_add_vertex(r1[nj].pos)
			rope_mesh.surface_set_normal(r2[nj].normal); rope_mesh.surface_add_vertex(r2[nj].pos)
			rope_mesh.surface_set_normal(r2[j].normal); rope_mesh.surface_add_vertex(r2[j].pos)
	rope_mesh.surface_end()

func _get_hand_position() -> Vector3:
	var cam = player_body.get_node_or_null("Neck/Camera") as Camera3D
	if not cam:
		cam = player_body.get_viewport().get_camera_3d()
	if cam:
		return cam.global_position + cam.global_transform.basis * hand_offset
	if hook_source:
		return hook_source.global_position
	return player_body.global_position
