# HookController.gd - A grappling hook system with Verlet integration
# Features: procedural rope visualization, wall wrapping, ground lock, smooth retract
#
# VIBES:
# - Hyper-fast, momentum-based movement
# - Physics-based grappling with slingshot mechanics
# - Procedural neon-blue energy beam with white outline

extends Node

# --------------------------------------------------------------
# SIGNALS
# --------------------------------------------------------------
signal hook_latched(point: Vector3)
signal hook_released()

# --------------------------------------------------------------
# EXPORTS
# --------------------------------------------------------------
@export_group("Controls")
@export var launch_action_name: String = "grapple"
@export var thrust_action_name: String = "jump"

@export_group("References")
@export var hook_raycast: RayCast3D
@export var player_body: CharacterBody3D
@export var camera: Camera3D

@export_group("Physics")
@export var gravity: Vector3 = Vector3(0, -15.0, 0)
@export var stiffness: float = 15.0
@export var damping: float = 3.0
@export var thrust_mult: float = 25.0
@export var max_rope_length: float = 40.0
@export var rope_radius: float = 0.04
@export var max_stretch: float = 0.3
@export var stretch_recovery: float = 4.0

@export_group("Wrapping")
@export var max_wraps: int = 4
@export var wrap_offset: float = 0.6
@export var wrap_step: float = 0.35

@export_group("Rope Rendering")
@export var rope_color: Color = Color(0.0, 0.4, 1.0, 1.0)
@export var rope_emission_color: Color = Color(0.0, 0.6, 1.0, 1.0)
@export var emission_energy: float = 12.0
@export var outline_color: Color = Color.WHITE

# --------------------------------------------------------------
# CONSTANTS
# --------------------------------------------------------------
const ROPE_SEGMENTS: int = 24
const EXTEND_SPEED: float = 15.0
const RETRACT_SPEED: float = 20.0
const GRADATION_FACTOR: float = 0.98

# --------------------------------------------------------------
# STATE
# --------------------------------------------------------------
var is_grappling: bool = false
var grapple_point: Vector3 = Vector3.ZERO
var is_retracting: bool = false
var rope_extend_anim: float = 0.0

var rope_points: Array[Vector3] = []
var rope_old_points: Array[Vector3] = []

var wrap_points: Array = []
var anchor_points: Array = []

# --------------------------------------------------------------
# RENDERING
# --------------------------------------------------------------
var rope_mesh: ImmediateMesh
var rope_mesh_instance: MeshInstance3D
var rope_material: StandardMaterial3D

func _ready() -> void:
	if hook_raycast:
		hook_raycast.add_exception(player_body)
	_setup_rope_mesh()

func _setup_rope_mesh() -> void:
	rope_mesh = ImmediateMesh.new()
	rope_mesh_instance = MeshInstance3D.new()
	rope_mesh_instance.mesh = rope_mesh
	rope_mesh_instance.top_level = true
	add_child(rope_mesh_instance)

	# Main rope material - neon blue
	rope_material = StandardMaterial3D.new()
	rope_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	rope_material.albedo_color = rope_color
	rope_material.emission_enabled = true
	rope_material.emission = rope_emission_color
	rope_material.emission_energy_multiplier = emission_energy

	# Outline material - white, front-culled for outline effect
	var outline = StandardMaterial3D.new()
	outline.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	outline.cull_mode = StandardMaterial3D.CULL_FRONT
	outline.albedo_color = outline_color
	outline.grow = true
	outline.grow_amount = 0.02

	rope_material.next_pass = outline

	rope_mesh_instance.material_override = rope_material

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pass  # Handle camera rotation in player script

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta: float) -> void:
	var grapple_held = Input.is_action_pressed(launch_action_name)

	if grapple_held and not is_grappling:
		_launch_hook()
		is_retracting = false
	elif not grapple_held and is_grappling and not is_retracting:
		is_retracting = true

	if is_grappling:
		if is_retracting:
			rope_extend_anim = move_toward(rope_extend_anim, 0.0, delta * RETRACT_SPEED)
			if rope_extend_anim <= 0.001:
				_release_hook()
				return
		else:
			rope_extend_anim = move_toward(rope_extend_anim, 1.0, delta * EXTEND_SPEED)

		_simulate_rope(delta)
		_apply_grapple_physics(delta)
		_update_wrapping()
		_draw_rope()
	else:
		if rope_mesh:
			rope_mesh.clear_surfaces()

func _get_hand_position() -> Vector3:
	if not camera:
		return player_body.global_position if player_body else Vector3.ZERO
	return camera.global_position + camera.global_transform.basis * Vector3(0.5, -0.6, -0.8)

func _launch_hook() -> void:
	if not hook_raycast or not hook_raycast.is_colliding():
		return

	is_grappling = true
	is_retracting = false

	var collider = hook_raycast.get_collider()
	grapple_point = hook_raycast.get_collision_point()

	wrap_points.clear()
	anchor_points.clear()

	# Initialize rope points
	rope_points.clear()
	rope_old_points.clear()

	var hand_pos = _get_hand_position()
	for i in range(ROPE_SEGMENTS):
		rope_points.append(hand_pos)
		rope_old_points.append(hand_pos)

	hook_latched.emit(grapple_point)

func _release_hook() -> void:
	is_grappling = false
	is_retracting = false

	if rope_mesh:
		rope_mesh.clear_surfaces()

	wrap_points.clear()
	anchor_points.clear()

	hook_released.emit()

func _simulate_rope(delta: float) -> void:
	var hand_pos = _get_hand_position()
	var target_p = grapple_point

	if rope_points.size() != ROPE_SEGMENTS:
		rope_points.clear()
		rope_old_points.clear()
		for i in range(ROPE_SEGMENTS):
			rope_points.append(hand_pos)
			rope_old_points.append(hand_pos)

	# Calculate segment length based on extend animation
	var seg_len = hand_pos.distance_to(target_p) / (ROPE_SEGMENTS - 1)
	if rope_extend_anim >= 1.0:
		seg_len = max_rope_length / (ROPE_SEGMENTS - 1)

	# 1. Apply Forces (Verlet integration)
	for i in range(1, ROPE_SEGMENTS):
		var temp = rope_points[i]
		var vel = (rope_points[i] - rope_old_points[i]) * GRADATION_FACTOR
		rope_points[i] += vel + gravity * delta * delta
		rope_old_points[i] = temp

	# 2. Distance Constraints (Stiffness)
	for iter in range(10):
		rope_points[0] = hand_pos
		rope_points[ROPE_SEGMENTS - 1] = target_p

		for i in range(ROPE_SEGMENTS - 1):
			var p1 = rope_points[i]
			var p2 = rope_points[i + 1]
			var dir = p2 - p1
			var dist = dir.length()
			if dist > 0.0001:
				var error = dist - seg_len
				var correction = dir.normalized() * error * 0.5
				if i != 0:
					rope_points[i] += correction
				if i + 1 != ROPE_SEGMENTS - 1:
					rope_points[i + 1] -= correction

func _apply_grapple_physics(delta: float) -> void:
	if not player_body:
		return

	var hand_pos = _get_hand_position()
	var to_pivot = grapple_point - hand_pos
	var dist = to_pivot.length()

	# Calculate stretch amounts
	var target_dist = max_rope_length * rope_extend_anim
	var stretch_amount = 0.0
	if dist > target_dist:
		stretch_amount = min(dist - target_dist, max_stretch)
	else:
		stretch_amount = move_toward(stretch_amount, 0.0, stretch_recovery * delta)

	# Apply spring force if stretched
	if dist > target_dist + stretch_amount and dist > 0.1:
		var pull_dir = to_pivot.normalized()
		var extension = dist - (target_dist + stretch_amount)
		var force = pull_dir * (extension * stiffness - player_body.velocity.dot(pull_dir) * damping)

		# Ground lock - prevent upward pull when on floor
		if player_body.is_on_floor():
			force.y = 0
			if player_body.velocity.y > 0:
				player_body.velocity.y = 0

		player_body.velocity += force * delta

		# Thrust boost on jump
		if Input.is_action_just_pressed(thrust_action_name):
			player_body.velocity += pull_dir * thrust_mult

func _update_wrapping() -> void:
	if not player_body or not wrap_points:
		return

	var space_state = player_body.get_world_3d().direct_space_state
	var hand_pos = _get_hand_position()
	var target = grapple_point

	var new_wraps: Array = []
	var current = hand_pos
	var check_target = target

	for i in range(max_wraps):
		if current.distance_to(check_target) < 0.2:
			break

		var query = PhysicsRayQueryParameters3D.create(current, check_target)
		query.exclude = [player_body.get_rid()]
		var result = space_state.intersect_ray(query)

		if not result:
			break

		var hit_pos = result.position
		var normal = result.normal

		if hit_pos.distance_to(check_target) < 0.2:
			break

		if normal.length_squared() < 0.01:
			normal = (current - hit_pos).normalized()

		# Place wrap point offset from wall
		var corner = hit_pos + normal * wrap_offset

		# Check if wall is actually blocking the line of sight
		var loS_check = PhysicsRayQueryParameters3D.create(hand_pos, check_target)
		loS_check.exclude = [player_body.get_rid()]
		var loS_result = space_state.intersect_ray(loS_check)

		if loS_result and loS_result.position.distance_to(target) < hand_pos.distance_to(target):
			# Line of sight changed, remove old wraps that are no longer valid
			break

		new_wraps.append(corner)
		current = corner
		var dir = (check_target - corner).normalized()
		check_target = corner + dir * wrap_step

	wrap_points = new_wraps

func _draw_rope() -> void:
	rope_mesh.clear_surfaces()
	if rope_points.size() < 2 or rope_extend_anim < 0.01:
		return

	var hand_pos = _get_hand_position()
	var target = grapple_point

	# Build polyline with wrap points
	var polyline = [hand_pos]
	for wp in wrap_points:
		polyline.append(wp)
	polyline.append(target)

	if polyline.size() < 2:
		return

	var core_radius = rope_radius * rope_extend_anim

	# Calculate segment lengths and tangents
	var tangents: Array = []
	for i in range(polyline.size()):
		if i == 0:
			tangents.append((polyline[1] - polyline[0]).normalized())
		elif i == polyline.size() - 1:
			tangents.append((polyline[i] - polyline[i - 1]).normalized())
		else:
			tangents.append((polyline[i + 1] - polyline[i - 1]).normalized())

	if tangents[0].length() < 0.001:
		tangents[0] = Vector3.FORWARD
	else:
		tangents[0] = tangents[0].normalized()

	if tangents.back().length() < 0.001:
		tangents[tangents.size() - 1] = Vector3.FORWARD
	else:
		tangents[tangents.size() - 1] = tangents[tangents.size() - 1].normalized()

	# Parallel transport for smooth twisting
	var normals: Array = []
	var up = Vector3.UP
	if abs(tangents[0].dot(up)) > 0.9:
		up = Vector3.RIGHT
	normals.append(tangents[0].cross(up).normalized())

	for i in range(1, polyline.size()):
		var prev_normal = normals[i - 1]
		var tangent = tangents[i]

		# Calculate rotation between consecutive tangents
		var axis = tangents[i - 1].cross(tangent)
		if axis.length_squared() > 0.0001:
			axis = axis.normalized()
			var angle = acos(clamp(tangents[i - 1].dot(tangent), -1.0, 1.0))
			normals.append(prev_normal.rotated(axis, angle))
		else:
			normals.append(prev_normal)

	# Draw the rope
	rope_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var sides = 6  # Hexagonal cross-section for that angular look
	var rings = []

	for i in range(polyline.size()):
		var p = polyline[i]
		var t = tangents[i]
		var n = normals[i]
		var right = t.cross(n).normalized()

		var ring = []
		for j in range(sides):
			var angle = float(j) * 2.0 * PI / sides
			var offset = (n * cos(angle) + right * sin(angle)) * core_radius
			ring.append({
				"pos": p + offset,
				"normal": offset.normalized()
			})
		rings.append(ring)

	# Connect rings with triangles
	for i in range(rings.size() - 1):
		var r1 = rings[i]
		var r2 = rings[i + 1]

		for j in range(sides):
			var nj = (j + 1) % sides

			# First triangle of the quad
			_add_quad_vertex(rope_mesh, r1[j])
			_add_quad_vertex(rope_mesh, r1[nj])
			_add_quad_vertex(rope_mesh, r2[j])

			# Second triangle of the quad
			_add_quad_vertex(rope_mesh, r1[nj])
			_add_quad_vertex(rope_mesh, r2[nj])
			_add_quad_vertex(rope_mesh, r2[j])

	rope_mesh.surface_end()

func _add_quad_vertex(rope_mesh: ImmediateMesh, vertex: Dictionary) -> void:
	rope_mesh.surface_set_normal(vertex["normal"])
	rope_mesh.surface_add_vertex(vertex["pos"])

# --------------------------------------------------------------
# Editor Debug
# --------------------------------------------------------------
func _get_configuration_warning() -> String:
	if not hook_raycast:
		return "HookController requires a RayCast3D for the hook_raycast property."
	if not player_body:
		return "HookController requires a CharacterBody3D for the player_body property."
	return ""