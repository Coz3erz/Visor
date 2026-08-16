extends Node

signal hook_launched()
signal hook_attached(body)
signal hook_detached()

@export_group("Input")
@export var launch_action_name: String = "grapple"
@export var thrust_action_name: String = "jump"

@export_group("References")
@export var player_body: CharacterBody3D
@export var hook_raycast: RayCast3D
@export var hook_source: Node3D

@export_group("Physics")
@export var spring_k: float = 80.0
@export var spring_damp: float = 10.0
@export var rest_length_mult: float = 1.0
@export var thrust_force: float = 18.0
@export var max_stretch_mult: float = 1.4
@export var over_stretch_k: float = 240.0

@export_group("Hand")
@export var hand_offset: Vector3 = Vector3(0.25, -0.25, -0.4)
@export var hand_wall_skin: float = 0.05
@export var hand_wall_check_distance: float = 0.6

@export_group("Visuals")
@export var rope_color: Color = Color(0.0, 0.5, 1.0, 1.0)
@export var rope_radius: float = 0.5
@export var glow_intensity: float = 12.0
@export var rope_sag: float = 0.3

@export_group("Rope Mesh")
@export var ring_sides: int = 16
@export var outline_thickness: float = 0.05
@export var resample_spacing: float = 0.12

@export_group("Animation")
@export var extend_speed: float = 10.0
@export var retract_speed: float = 3.0
@export var wave_strength: float = 0.12
@export var wave_frequency: float = 14.0
@export var wave_speed: float = 18.0

@export_group("Wall Wrapping (Visual Only)")
@export var wrap_skin: float = 0.08
@export var max_wrap_points: int = 16
@export var debug_wraps: bool = false

@export var aim_indicator_enabled: bool = true
@export var aim_indicator_color: Color = Color(0.0, 1.0, 1.0, 1.0)
@export var aim_indicator_radius: float = 0.12

var _indicator_mi: MeshInstance3D = null
var _indicator_mesh: SphereMesh = null
var _indicator_mat: StandardMaterial3D = null

var _attached := false
var _retracting := false
var _extending := false
var _rope_anim := 0.0
var _anchor: Marker3D = null
var _target_pos := Vector3.ZERO
var _rest_len := 0.0

var _pluck_time := -10.0

var _rope_mi: MeshInstance3D = null
var _rope_mesh: ImmediateMesh = null
var _rope_mat: StandardMaterial3D = null
var _outline_mat: StandardMaterial3D = null

var _debug_mi: MeshInstance3D = null
var _debug_mesh: ImmediateMesh = null
var _debug_mat: StandardMaterial3D = null

var _wrap_points: Array[Vector3] = []

@export_group("Grapple Release")
@export var release_boost_mult: float = 0.6

func _ready() -> void:
	if aim_indicator_enabled:
		_indicator_mesh = SphereMesh.new()
		_indicator_mesh.radius = aim_indicator_radius
		_indicator_mesh.height = aim_indicator_radius * 2.0

		_indicator_mat = StandardMaterial3D.new()
		_indicator_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		_indicator_mat.albedo_color = aim_indicator_color
		_indicator_mat.emission_enabled = true
		_indicator_mat.emission = aim_indicator_color
		_indicator_mat.emission_energy_multiplier = 4.0

		_indicator_mi = MeshInstance3D.new()
		_indicator_mi.mesh = _indicator_mesh
		_indicator_mi.material_override = _indicator_mat
		_indicator_mi.top_level = true
		_indicator_mi.visible = false
		add_child(_indicator_mi)

	if hook_raycast:
		hook_raycast.add_exception(player_body)

	_rope_mesh = ImmediateMesh.new()
	_rope_mi = MeshInstance3D.new()
	_rope_mi.mesh = _rope_mesh
	_rope_mi.top_level = true
	_rope_mi.visible = false
	add_child(_rope_mi)

	_rope_mat = StandardMaterial3D.new()
	_rope_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	_rope_mat.albedo_color = rope_color
	_rope_mat.emission_enabled = true
	_rope_mat.emission = rope_color
	_rope_mat.emission_energy_multiplier = glow_intensity

	_outline_mat = StandardMaterial3D.new()
	_outline_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	_outline_mat.albedo_color = Color.WHITE

	if debug_wraps:
		_debug_mesh = ImmediateMesh.new()
		_debug_mi = MeshInstance3D.new()
		_debug_mi.mesh = _debug_mesh
		_debug_mi.top_level = true
		add_child(_debug_mi)
		_debug_mat = StandardMaterial3D.new()
		_debug_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		_debug_mat.albedo_color = Color.RED

func _physics_process(delta: float) -> void:
	var held := Input.is_action_pressed(launch_action_name)

	if held and not _attached and not _retracting:
		_launch()
	elif not held and _attached:
		_release()

	if _attached:
		_apply_spring(delta)

		if Input.is_action_just_pressed(thrust_action_name) and _anchor:
			var hand := _get_hand()
			var target := _anchor.global_position
			var to_target := target - hand
			var dist := to_target.length()
			if dist > 0.001:
				player_body.velocity += (to_target / dist) * thrust_force
			_pluck_time = Time.get_ticks_msec() / 1000.0

	_update_aim_indicator()

	if _extending:
		_rope_anim = min(_rope_anim + extend_speed * delta, 1.0)
		if _rope_anim >= 1.0:
			_extending = false

	if _retracting:
		_rope_anim -= retract_speed * delta
		if _rope_anim <= 0.0:
			_finish_retract()
			return

	if _attached or _retracting:
		_update_wrap_points()
		_draw_wrapping_rope()
		if debug_wraps:
			_draw_debug_points()

func _launch() -> void:
	if not hook_raycast or not hook_raycast.is_colliding():
		return

	_target_pos = hook_raycast.get_collision_point()
	var body = hook_raycast.get_collider()
	if not body:
		return

	_anchor = Marker3D.new()
	body.add_child(_anchor)
	_anchor.global_position = _target_pos

	var hand := _get_hand()
	_rest_len = hand.distance_to(_target_pos) * rest_length_mult

	_attached = true
	_retracting = false
	_extending = true
	_rope_anim = 0.0
	_wrap_points.clear()
	hook_launched.emit()
	hook_attached.emit(body)

	_rope_mi.visible = true
	_pluck_time = Time.get_ticks_msec() / 1000.0

func _release() -> void:
	# Spider-Man slingshot boost on release
	if player_body and _attached:
		var speed = player_body.velocity.length()
		if speed > 5.0:
			player_body.velocity += player_body.velocity.normalized() * speed * release_boost_mult

	_attached = false
	_retracting = true
	_extending = false
	hook_detached.emit()
	_pluck_time = Time.get_ticks_msec() / 1000.0
func _finish_retract() -> void:
	if _anchor:
		_anchor.queue_free()
		_anchor = null
	_retracting = false
	_rope_anim = 0.0
	if _rope_mi:
		_rope_mi.visible = false
	if _rope_mesh:
		_rope_mesh.clear_surfaces()
	_wrap_points.clear()
	if debug_wraps and _debug_mesh:
		_debug_mesh.clear_surfaces()

func _apply_spring(delta: float) -> void:
	if not player_body or not _anchor:
		return

	var target := _anchor.global_position
	var hand := _get_hand()
	var to_target := target - hand
	var dist := to_target.length()

	if dist < 0.001 or not to_target.is_finite():
		return

	var pull_dir := to_target / dist

	var extension := dist - _rest_len
	var spring_force := 0.0
	if extension > 0.0:
		spring_force = spring_k * extension
		var max_extension := _rest_len * (max_stretch_mult - 1.0)
		if extension > max_extension:
			spring_force += over_stretch_k * (extension - max_extension)

	var vel_along_rope := player_body.velocity.dot(pull_dir)
	var damping_force := spring_damp * vel_along_rope

	var force_magnitude := max(spring_force - damping_force, 0.0)

	if force_magnitude > 0.0:
		var force_vector = pull_dir * force_magnitude * delta
		if player_body.is_on_floor():
			force_vector.y = 0.0
		player_body.velocity += force_vector

	if player_body.is_on_floor():
		player_body.velocity.y = min(player_body.velocity.y, 0.0)

func _wrap_exclude() -> Array:
	return [player_body.get_rid()]

func _thick_cast(space_state: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array) -> Dictionary:
	var delta_vec := to - from
	var dist := delta_vec.length()
	if dist < wrap_skin + 0.05:
		return {}
	var dir := delta_vec / dist
	var short_to := to - dir * wrap_skin

	var up := Vector3.UP
	if abs(dir.dot(up)) > 0.95:
		up = Vector3.RIGHT
	var side := dir.cross(up).normalized()
	var vert := side.cross(dir).normalized()

	var offsets := [Vector3.ZERO, side * rope_radius, -side * rope_radius, vert * rope_radius, -vert * rope_radius]

	var best_hit := {}
	var best_dist := INF

	for off in offsets:
		var query := PhysicsRayQueryParameters3D.create(from + off, short_to + off)
		query.exclude = exclude
		var hit := space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var d: float = from.distance_to(hit.position)
		if d < best_dist:
			best_dist = d
			best_hit = hit

	return best_hit

func _try_unwrap(space_state: PhysicsDirectSpaceState3D, hand: Vector3, anchor_pos: Vector3, exclude: Array) -> void:
	while not _wrap_points.is_empty():
		var look_at: Vector3 = _wrap_points[1] if _wrap_points.size() > 1 else anchor_pos
		var hit := _thick_cast(space_state, hand, look_at, exclude)
		if not hit.is_empty():
			break
		_wrap_points.remove_at(0)
		if debug_wraps:
			print("[Hook] unwrapped -> %d point(s) left" % _wrap_points.size())

func _try_wrap(space_state: PhysicsDirectSpaceState3D, hand: Vector3, anchor_pos: Vector3, exclude: Array) -> void:
	while _wrap_points.size() < max_wrap_points:
		var look_at: Vector3 = _wrap_points[0] if not _wrap_points.is_empty() else anchor_pos
		var hit := _thick_cast(space_state, hand, look_at, exclude)
		if hit.is_empty():
			break
		var normal: Vector3 = hit.normal
		if normal.length() < 0.01:
			break
		var pivot: Vector3 = hit.position + normal * wrap_skin
		_wrap_points.insert(0, pivot)
		if debug_wraps:
			print("[Hook] wrapped -> %d point(s) now" % _wrap_points.size())

func _update_wrap_points() -> void:
	if not _anchor or not player_body:
		_wrap_points.clear()
		return

	var hand := _get_hand()
	var anchor_pos := _anchor.global_position
	var space_state := player_body.get_world_3d().direct_space_state
	var exclude := _wrap_exclude()

	_try_unwrap(space_state, hand, anchor_pos, exclude)
	_try_wrap(space_state, hand, anchor_pos, exclude)

func _draw_debug_points() -> void:
	if not _debug_mesh:
		return
	_debug_mesh.clear_surfaces()
	if _wrap_points.is_empty():
		return
	_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _debug_mat)
	var s := 0.15
	for p in _wrap_points:
		_debug_mesh.surface_add_vertex(p - Vector3(s, 0, 0))
		_debug_mesh.surface_add_vertex(p + Vector3(s, 0, 0))
		_debug_mesh.surface_add_vertex(p - Vector3(0, s, 0))
		_debug_mesh.surface_add_vertex(p + Vector3(0, s, 0))
		_debug_mesh.surface_add_vertex(p - Vector3(0, 0, s))
		_debug_mesh.surface_add_vertex(p + Vector3(0, 0, s))
	_debug_mesh.surface_end()

func _truncate_path(path: Array[Vector3], keep_fraction: float) -> Array[Vector3]:
	if keep_fraction >= 1.0 or path.size() < 2:
		return path
	if keep_fraction <= 0.0:
		return []

	var total_length := 0.0
	for i in range(path.size() - 1):
		total_length += path[i].distance_to(path[i + 1])
	if total_length < 0.001:
		return path

	var target_length := total_length * keep_fraction
	var result: Array[Vector3] = [path[0]]
	var accumulated := 0.0

	for i in range(path.size() - 1):
		var seg_len := path[i].distance_to(path[i + 1])
		if accumulated + seg_len >= target_length:
			var remaining := target_length - accumulated
			var t := (remaining / seg_len) if seg_len > 0.001 else 0.0
			result.append(path[i].lerp(path[i + 1], t))
			return result
		accumulated += seg_len
		result.append(path[i + 1])

	return result

func _resample_path(path: Array[Vector3], spacing: float) -> Array[Vector3]:
	if path.size() < 2 or spacing <= 0.001:
		return path
	var result: Array[Vector3] = [path[0]]
	for i in range(path.size() - 1):
		var a := path[i]
		var c := path[i + 1]
		var seg_len := a.distance_to(c)
		var steps := max(1, int(ceil(seg_len / spacing)))
		for s in range(1, steps + 1):
			result.append(a.lerp(c, float(s) / float(steps)))
	return result

func _apply_sag(path: Array[Vector3], amount: float) -> Array[Vector3]:
	if path.size() < 2 or amount <= 0.001:
		return path
	var cum: Array[float] = [0.0]
	for i in range(1, path.size()):
		cum.append(cum[i - 1] + path[i - 1].distance_to(path[i]))
	var total: float = cum[cum.size() - 1]
	if total < 0.001:
		return path
	var result: Array[Vector3] = []
	for i in range(path.size()):
		var t: float = cum[i] / total
		var p := path[i]
		p.y -= amount * sin(t * PI)
		result.append(p)
	return result

func _compute_tangents(path: Array[Vector3]) -> Array[Vector3]:
	var tangents: Array[Vector3] = []
	for i in range(path.size()):
		if i == 0:
			tangents.append((path[1] - path[0]).normalized())
		elif i == path.size() - 1:
			tangents.append((path[i] - path[i - 1]).normalized())
		else:
			tangents.append((path[i + 1] - path[i - 1]).normalized())
	for i in range(tangents.size()):
		if tangents[i].length() < 0.001:
			tangents[i] = Vector3.UP
	return tangents

func _compute_normals(path: Array[Vector3], tangents: Array[Vector3]) -> Array[Vector3]:
	var normals: Array[Vector3] = []
	var up := Vector3.UP
	if abs(tangents[0].dot(up)) > 0.9:
		up = Vector3.RIGHT
	var first_right := tangents[0].cross(up).normalized()
	var first_up := first_right.cross(tangents[0]).normalized()
	normals.append(first_up)

	for i in range(1, path.size()):
		var prev_normal := normals[i - 1]
		var prev_tangent := tangents[i - 1]
		var tangent := tangents[i]
		var axis := prev_tangent.cross(tangent)
		if axis.length_squared() > 0.0001:
			axis = axis.normalized()
			var angle := acos(clamp(prev_tangent.dot(tangent), -1.0, 1.0))
			normals.append(prev_normal.rotated(axis, angle))
		else:
			normals.append(prev_normal)
	return normals

func _apply_pluck_wave(path: Array[Vector3]) -> Array[Vector3]:
	if path.size() < 2:
		return path

	var time := Time.get_ticks_msec() / 1000.0
	var since_pluck := time - _pluck_time
	var decay := clamp(1.0 - since_pluck / 0.8, 0.0, 1.0)

	var tension_amp := 0.0
	if _anchor and _rest_len > 0.001:
		var hand := _get_hand()
		var dist := hand.distance_to(_anchor.global_position)
		tension_amp = clamp((dist - _rest_len) / (_rest_len * 0.2), 0.0, 1.0)

	var speed_amp := clamp(player_body.velocity.length() / 12.0, 0.0, 1.0)

	# Always keep a small ambient vibration while attached, even if stationary.
	# The decay, tension, and speed add extra intensity on top of that floor.
	var amp = wave_strength * (0.2 + decay * 0.5 + tension_amp * 0.3 + speed_amp * 0.3)
	amp = min(amp, wave_strength * 1.5)

	if amp <= 0.001:
		return path

	var tangents := _compute_tangents(path)
	var normals := _compute_normals(path, tangents)

	var result: Array[Vector3] = []
	for i in range(path.size()):
		var t = float(i) / max(path.size() - 1, 1)
		var envelope := sin(t * PI)

		# Two overlapping standing waves for organic motion.
		var vibration := sin(t * wave_frequency * PI) * sin(time * wave_speed) * 0.6
		vibration += sin(t * wave_frequency * PI * 2.0) * sin(time * wave_speed * 1.3) * 0.4
		var offset = vibration * amp * envelope
		result.append(path[i] + normals[i] * offset)

	return result
func _emit_tube(path: Array[Vector3], tangents: Array[Vector3], normals: Array[Vector3], extra_radius: float, material: Material) -> void:
	var n := path.size()
	if n < 2:
		return

	var radius: float = max(rope_radius + extra_radius, 0.0)

	var rings: Array = []
	for i in range(n):
		var p: Vector3 = path[i]
		var t: Vector3 = tangents[i]
		var nrm: Vector3 = normals[i]
		var b: Vector3 = t.cross(nrm).normalized()

		var ring: Array = []
		for j in range(ring_sides):
			var angle: float = float(j) * TAU / ring_sides
			var offset: Vector3 = (nrm * cos(angle) + b * sin(angle)) * radius
			ring.append({"pos": p + offset, "normal": offset.normalized()})
		rings.append(ring)

	_rope_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for i in range(rings.size() - 1):
		var r1 = rings[i]
		var r2 = rings[i + 1]
		for j in range(ring_sides):
			var nj := (j + 1) % ring_sides

			_rope_mesh.surface_set_normal(r1[j].normal)
			_rope_mesh.surface_add_vertex(r1[j].pos)
			_rope_mesh.surface_set_normal(r1[nj].normal)
			_rope_mesh.surface_add_vertex(r1[nj].pos)
			_rope_mesh.surface_set_normal(r2[j].normal)
			_rope_mesh.surface_add_vertex(r2[j].pos)

			_rope_mesh.surface_set_normal(r1[nj].normal)
			_rope_mesh.surface_add_vertex(r1[nj].pos)
			_rope_mesh.surface_set_normal(r2[nj].normal)
			_rope_mesh.surface_add_vertex(r2[nj].pos)
			_rope_mesh.surface_set_normal(r2[j].normal)
			_rope_mesh.surface_add_vertex(r2[j].pos)
	_rope_mesh.surface_end()

func _draw_wrapping_rope() -> void:
	if not _rope_mesh:
		return

	var hand := _get_hand()
	var raw_path: Array[Vector3] = [hand]
	raw_path.append_array(_wrap_points)

	var has_anchor := _anchor != null
	var anchor_pos := Vector3.ZERO
	if has_anchor:
		anchor_pos = _anchor.global_position
		raw_path.append(anchor_pos)

	if raw_path.size() < 2:
		_rope_mesh.clear_surfaces()
		return

	var anim := clamp(_rope_anim, 0.0, 1.0)
	var path := raw_path
	if anim < 0.999:
		path = _truncate_path(raw_path, anim)

	if path.size() < 2:
		_rope_mesh.clear_surfaces()
		return

	if _wrap_points.is_empty() and has_anchor and rope_sag > 0.001 and _rest_len > 0.001:
		var dist_now := hand.distance_to(anchor_pos)
		var slack := clamp(1.0 - dist_now / _rest_len, 0.0, 1.0)
		if slack > 0.001:
			path = _resample_path(path, resample_spacing)
			path = _apply_sag(path, rope_sag * slack)

	if _attached:
		path = _apply_pluck_wave(path)

	var tangents := _compute_tangents(path)
	var normals := _compute_normals(path, tangents)

	_rope_mesh.clear_surfaces()
	_emit_tube(path, tangents, normals, outline_thickness, _outline_mat)
	_emit_tube(path, tangents, normals, 0.0, _rope_mat)

func _get_hand() -> Vector3:
	var origin: Vector3
	var basis: Basis

	if hook_source:
		origin = hook_source.global_position
		basis = hook_source.global_transform.basis
	elif player_body:
		var cam := player_body.get_node_or_null("Neck/Camera") as Camera3D
		if cam:
			origin = cam.global_position
			basis = cam.global_transform.basis
		else:
			return player_body.global_position + Vector3(0, 1.5, 0)
	else:
		return Vector3.ZERO

	var hand := origin + basis * hand_offset

	if player_body:
		var space_state := player_body.get_world_3d().direct_space_state
		var forward := -basis.z
		var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * hand_wall_check_distance)
		query.exclude = [player_body.get_rid()]
		var hit := space_state.intersect_ray(query)
		if hit:
			var clearance := origin.distance_to(hit.position)
			var push_back := hand_wall_check_distance - clearance
			if push_back > 0.0:
				hand -= forward * push_back

	return hand

func _update_aim_indicator() -> void:
	if not aim_indicator_enabled or not _indicator_mi or not hook_raycast or not player_body:
		return

	if _attached:
		_indicator_mi.visible = false
		return

	if hook_raycast.is_colliding():
		var hit := hook_raycast.get_collision_point()
		var normal := hook_raycast.get_collision_normal()
		_indicator_mi.global_position = hit + normal * 0.03
		_indicator_mi.visible = true
	else:
		_indicator_mi.visible = false
func is_rope_taut() -> bool:
	if not _attached or not _anchor:
		return false
	var hand := _get_hand()
	var dist := hand.distance_to(_anchor.global_position)
	return dist > _rest_len * 1.05   # small threshold to feel natural
