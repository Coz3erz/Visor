extends CharacterBody3D

@export_category("Node Links")
@export var head: Node3D
@export var camera: Camera3D
@export var grapple_raycast: RayCast3D
@export var collision_shape: CollisionShape3D

@export_category("Movement")
@export var move_speed: float = 13.0
@export var jump_velocity: float = 8.0
@export var mouse_sensitivity: float = 0.002
@export var gravity: float = 22.0
@export var ground_friction: float = 12.0

@export_category("Slide")
@export var slide_speed_boost: float = 12.0
@export var slide_steer_speed: float = 2.5
@export var slide_speed_decay: float = 1.0
@export var slide_min_speed: float = 14.0
@export var slide_camera_drop: float = 0.4
@export var slide_tilt_amount: float = 0.35
@export var slide_camera_lerp: float = 0.4

@export_category("Air Control")
@export var air_acceleration: float = 20.0
@export var max_air_speed: float = 25.0
@export var air_slide_gravity_mult: float = 0.4

@export_category("Dash")
@export var dash_speed: float = 35.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 1.0

@export_category("Wall Jumps")
@export var wall_jump_pushback: float = 14.0

@export_category("Grapple")
const ROPE_SEGMENTS: int = 24
const ROPE_RADIUS: float = 0.04
const ROPE_RADIAL_STEPS: int = 6
const MAX_WRAPS: int = 4
var is_grappling: bool = false
var grapple_point: Vector3 = Vector3.ZERO
var max_rope_length: float = 0.0
var dynamic_rope_length: float = 0.0
var stretch_amount: float = 0.0
var max_stretch: float = 0.3
var stretch_recovery: float = 4.0
var rope_extend_anim: float = 0.0
var rope_wrap_points: Array = []
var rope_material: StandardMaterial3D
var rope_mesh: ImmediateMesh
var rope_mesh_instance: MeshInstance3D

var is_sliding: bool = false
var is_air_sliding: bool = false
var slide_exit_timer: float = 0.0
var slide_exit_start_speed: float = 0.0
var wall_jumps_done: int = 0
var base_camera_y: float = 0.0

var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	base_camera_y = head.position.y
	camera.fov = 75.0
	_setup_rope_mesh()

func _setup_rope_mesh() -> void:
	rope_mesh = ImmediateMesh.new()
	rope_mesh_instance = MeshInstance3D.new()
	rope_mesh_instance.mesh = rope_mesh
	rope_mesh_instance.top_level = true
	add_child(rope_mesh_instance)
	rope_material = StandardMaterial3D.new()
	rope_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	rope_material.albedo_color = Color(0.0, 0.4, 1.0, 1.0)
	rope_material.emission_enabled = true
	rope_material.emission = Color(0.0, 0.6, 1.0, 1.0)
	rope_material.emission_energy_multiplier = 4.0
	var outline = StandardMaterial3D.new()
	outline.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	outline.cull_mode = StandardMaterial3D.CULL_FRONT
	outline.albedo_color = Color.WHITE
	outline.grow = true
	outline.grow_amount = 0.02
	rope_material.next_pass = outline
	rope_mesh_instance.material_override = rope_material

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, -PI/2, PI/2)
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if event.is_action_pressed("grapple"):
		if grapple_raycast.is_colliding():
			grapple_point = grapple_raycast.get_collision_point()
			is_grappling = true
			max_rope_length = global_position.distance_to(grapple_point)
			dynamic_rope_length = max_rope_length
			stretch_amount = 0.0
			rope_extend_anim = 0.0
			rope_wrap_points.clear()
	elif event.is_action_released("grapple"):
		is_grappling = false
		rope_wrap_points.clear()
		rope_extend_anim = 0.0
		rope_mesh.clear_surfaces()

func _physics_process(delta: float) -> void:
	if dash_cooldown_timer > 0: dash_cooldown_timer -= delta
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0: is_dashing = false
	if slide_exit_timer > 0: slide_exit_timer -= delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var wish_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if Input.is_action_just_pressed("dash") and not is_dashing and dash_cooldown_timer <= 0 and not is_grappling:
		_start_dash(wish_dir)
	if is_dashing:
		velocity = dash_direction * dash_speed
		move_and_slide()
		return

	handle_slide_state(wish_dir, delta)
	handle_jumping(wish_dir)
	handle_camera_tilt(delta)

	if not is_on_floor():
		if is_air_sliding:
			velocity.y -= gravity * air_slide_gravity_mult * delta
		else:
			velocity.y -= gravity * delta

	if is_grappling:
		rope_extend_anim = move_toward(rope_extend_anim, 1.0, delta * 9.0)
		handle_rope_wrapping()
		apply_grapple_physics(delta)
		_draw_rope()
	else:
		rope_mesh.clear_surfaces()

	apply_movement(wish_dir, delta)
	move_and_slide()

func _start_dash(wish_dir: Vector3) -> void:
	is_dashing = true; dash_timer = dash_duration; dash_cooldown_timer = dash_cooldown
	dash_direction = wish_dir if wish_dir.length() > 0.1 else -transform.basis.z

func handle_slide_state(wish_dir: Vector3, delta: float) -> void:
	var crouch_pressed = Input.is_action_pressed("crouch")
	var on_floor = is_on_floor()
	if crouch_pressed and slide_exit_timer > 0:
		is_sliding = true; slide_exit_timer = 0.0
		head.position.y = lerp(head.position.y, base_camera_y - slide_camera_drop, slide_camera_lerp)
		collision_shape.shape.height = lerp(collision_shape.shape.height, 1.0, slide_camera_lerp)
		return
	if on_floor and crouch_pressed:
		if not is_sliding and velocity.length() > 5.0:
			is_sliding = true; velocity += -transform.basis.z * slide_speed_boost; slide_exit_timer = 0.0
		head.position.y = lerp(head.position.y, base_camera_y - slide_camera_drop, slide_camera_lerp)
		collision_shape.shape.height = lerp(collision_shape.shape.height, 1.0, slide_camera_lerp)
		return
	if not on_floor and is_sliding and crouch_pressed:
		is_air_sliding = true; is_sliding = false
		head.position.y = lerp(head.position.y, base_camera_y - slide_camera_drop, slide_camera_lerp)
		collision_shape.shape.height = lerp(collision_shape.shape.height, 1.0, slide_camera_lerp)
		return
	if is_air_sliding:
		if crouch_pressed:
			head.position.y = lerp(head.position.y, base_camera_y - slide_camera_drop, slide_camera_lerp)
			collision_shape.shape.height = lerp(collision_shape.shape.height, 1.0, slide_camera_lerp)
		else:
			is_air_sliding = false; _start_slide_exit()
			head.position.y = lerp(head.position.y, base_camera_y, slide_camera_lerp * 1.5)
			collision_shape.shape.height = lerp(collision_shape.shape.height, 2.0, slide_camera_lerp * 1.5)
		return
	if not crouch_pressed and is_sliding:
		is_sliding = false; _start_slide_exit()
		head.position.y = lerp(head.position.y, base_camera_y, slide_camera_lerp * 1.5)
		collision_shape.shape.height = lerp(collision_shape.shape.height, 2.0, slide_camera_lerp * 1.5)
		return
	if not is_sliding and not is_air_sliding:
		head.position.y = lerp(head.position.y, base_camera_y, slide_camera_lerp)
		collision_shape.shape.height = lerp(collision_shape.shape.height, 2.0, slide_camera_lerp)

func _start_slide_exit() -> void:
	slide_exit_start_speed = Vector2(velocity.x, velocity.z).length()
	slide_exit_timer = 1.5

func handle_jumping(wish_dir: Vector3) -> void:
	if not Input.is_action_just_pressed("jump"): return
	if is_on_floor():
		if is_air_sliding:
			is_air_sliding = false
			velocity.y = jump_velocity * 1.4
			velocity += (-transform.basis.z if wish_dir.length() < 0.1 else wish_dir) * slide_speed_boost * 1.2
			head.position.y = base_camera_y; collision_shape.shape.height = 2.0; slide_exit_timer = 0.0
			return
		if is_sliding:
			velocity.y = jump_velocity; velocity += -transform.basis.z * slide_speed_boost
			is_sliding = false
			head.position.y = base_camera_y; collision_shape.shape.height = 2.0; slide_exit_timer = 0.0
			if Input.is_action_pressed("crouch"): is_air_sliding = true
			return
		velocity.y = jump_velocity
		return
	if is_on_wall_only():
		wall_jumps_done += 1
		var n = get_wall_normal()
		velocity = n * wall_jump_pushback; velocity.y = jump_velocity * 1.3

func handle_camera_tilt(delta: float) -> void:
	var target_tilt = 0.0
	if is_grappling and rope_wrap_points.size() > 0:
		target_tilt = clamp(-to_local(rope_wrap_points.back()).x * 0.02, -0.2, 0.2)
	elif is_grappling:
		target_tilt = clamp(-to_local(grapple_point).x * 0.02, -0.2, 0.2)
	elif is_sliding or is_air_sliding:
		var hvel = Vector3(velocity.x, 0, velocity.z)
		if hvel.length() > 1.0: target_tilt = transform.basis.x.dot(hvel.normalized()) * slide_tilt_amount
	camera.rotation.z = lerp(camera.rotation.z, target_tilt, 12.0 * delta)

func apply_movement(wish_dir: Vector3, delta: float) -> void:
	if is_sliding or is_air_sliding:
		var hvel = Vector3(velocity.x, 0, velocity.z)
		var speed = max(hvel.length(), slide_min_speed)
		speed = max(speed - slide_speed_decay * delta, slide_min_speed)
		var cur = hvel.normalized() if hvel.length() > 0.1 else -transform.basis.z
		var new_dir = lerp(cur, wish_dir, slide_steer_speed * delta).normalized()
		velocity.x = new_dir.x * speed; velocity.z = new_dir.z * speed
		return
	if slide_exit_timer > 0:
		var t = 1.0 - (slide_exit_timer / 1.5)
		var target_speed = lerp(slide_exit_start_speed, move_speed, t)
		var cur2 = Vector2(velocity.x, velocity.z)
		var des = Vector2(wish_dir.x, wish_dir.z) * target_speed
		var new2 = cur2.lerp(des, 4.0 * delta)
		velocity.x = new2.x; velocity.z = new2.y
		return
	if not is_on_floor():
		var cur_hvel = Vector3(velocity.x, 0, velocity.z)
		var wish_hvel = wish_dir * move_speed
		var add = (wish_hvel - cur_hvel).limit_length(air_acceleration * delta)
		velocity += add
		var hspeed = Vector3(velocity.x, 0, velocity.z).length()
		if hspeed > max_air_speed: velocity.x *= max_air_speed / hspeed; velocity.z *= max_air_speed / hspeed
		return
	velocity.x = lerp(velocity.x, wish_dir.x * move_speed, ground_friction * delta)
	velocity.z = lerp(velocity.z, wish_dir.z * move_speed, ground_friction * delta)

func apply_grapple_physics(delta: float) -> void:
	var hand_pos = camera.global_position + camera.global_transform.basis * Vector3(0.3, -0.4, -0.5)
	var to_anchor = grapple_point - hand_pos
	var dist = to_anchor.length()

	if dist > max_rope_length:
		var pull_dir = to_anchor.normalized()
		var extension = clamp(dist - max_rope_length, 0.0, 5.0)
		var spring_k = 65.0
		var damping_c = 10.0
		var spring_force = extension * spring_k
		var vel_outward = velocity.dot(pull_dir)
		var damping_force = vel_outward * damping_c
		var force = pull_dir * (spring_force - damping_force) * delta
		if is_on_floor():
			force.y = 0.0
			if velocity.y <= 0.0: velocity.y = min(velocity.y, 0.0)
		velocity += force

func handle_rope_wrapping() -> void:
	if rope_wrap_points.size() >= MAX_WRAPS:
		return
	var space_state = get_world_3d().direct_space_state
	var hand_pos = camera.global_position + camera.global_transform.basis * Vector3(0.3, -0.4, -0.5)
	var active_anchor = grapple_point
	if rope_wrap_points.size() > 0:
		active_anchor = rope_wrap_points.back()

	var query = PhysicsRayQueryParameters3D.create(hand_pos, active_anchor)
	query.exclude = [get_rid()]
	var result = space_state.intersect_ray(query)

	if result:
		var corner = result.position + result.normal * 0.15
		if hand_pos.distance_to(corner) < hand_pos.distance_to(active_anchor):
			rope_wrap_points.append(corner)

	if rope_wrap_points.size() > 0:
		var previous_anchor = grapple_point
		if rope_wrap_points.size() > 1:
			previous_anchor = rope_wrap_points[rope_wrap_points.size() - 2]
		var unwrap_query = PhysicsRayQueryParameters3D.create(hand_pos, previous_anchor)
		unwrap_query.exclude = [get_rid()]
		if not space_state.intersect_ray(unwrap_query):
			rope_wrap_points.pop_back()

func _draw_rope() -> void:
	rope_mesh.clear_surfaces()
	var space_state = get_world_3d().direct_space_state
	var cam_forward = -camera.global_transform.basis.z
	
	# Push the hand position further away from the camera so the rope start is hidden
	var base_hand_offset = Vector3(0.3, -0.3, -1.0)
	var hand_pos = camera.global_position + camera.global_transform.basis * base_hand_offset
	
	# If a wall is very close, push it forward so it doesn't clip through the camera
	var probe_start = camera.global_position + cam_forward * 0.3
	var probe_query = PhysicsRayQueryParameters3D.create(probe_start, probe_start + cam_forward * 1.0)
	probe_query.exclude = [get_rid()]
	var probe_result = space_state.intersect_ray(probe_query)
	if probe_result:
		var wall_dist = probe_result.position.distance_to(probe_start)
		if wall_dist < 1.2:
			hand_pos = camera.global_position + cam_forward * (wall_dist - 0.15)

	var polyline = [hand_pos]
	for i in range(rope_wrap_points.size() - 1, -1, -1):
		polyline.append(rope_wrap_points[i])
	polyline.append(grapple_point)
	if polyline.size() < 2: return

	var total_length = 0.0
	var segment_lengths = []
	for idx in range(polyline.size() - 1):
		var l = polyline[idx].distance_to(polyline[idx+1]); total_length += l; segment_lengths.append(l)

	var extend_dist = total_length * rope_extend_anim
	var path_points = []
	for idx in range(ROPE_SEGMENTS + 1):
		var t = float(idx) / ROPE_SEGMENTS
		var target_dist = extend_dist * t
		if target_dist > extend_dist: target_dist = extend_dist
		var cum = 0.0
		var found = false
		for seg_idx in range(polyline.size() - 1):
			if cum + segment_lengths[seg_idx] >= target_dist:
				var local_t = 0.0
				if segment_lengths[seg_idx] > 0:
					local_t = (target_dist - cum) / segment_lengths[seg_idx]
				path_points.append(polyline[seg_idx].lerp(polyline[seg_idx + 1], local_t))
				found = true
				break
			cum += segment_lengths[seg_idx]
		if not found: path_points.append(polyline.back())

	# Remove the first point if it's very close to the next, hiding the start
	if path_points.size() >= 2 and path_points[0].distance_to(path_points[1]) < 0.15:
		path_points.remove_at(0)

	if path_points.size() < 2: return

	var sag = 0.12 if velocity.length() <= 5.0 else 0.03
	var time_passed = Time.get_ticks_msec() / 1000.0
	for i in range(path_points.size()):
		var t = float(i) / (path_points.size() - 1)
		path_points[i] += Vector3.DOWN * sag * sin(t * PI)
		if rope_extend_anim < 1.0:
			var wave = sin(t * PI * 4.0 - time_passed * 40.0) * 0.1 * (1.0 - rope_extend_anim)
			path_points[i] += camera.global_transform.basis.y * wave

	rope_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings = []
	for i in range(path_points.size()):
		var current = path_points[i]
		var fwd: Vector3
		if i == 0: fwd = (path_points[i+1] - current).normalized()
		elif i == path_points.size() - 1: fwd = (current - path_points[i-1]).normalized()
		else: fwd = (path_points[i+1] - path_points[i-1]).normalized()
		var up = Vector3.UP
		if abs(fwd.dot(up)) > 0.99: up = Vector3.FORWARD
		var right = fwd.cross(up).normalized()
		var ortho_up = right.cross(fwd).normalized()
		var radius = ROPE_RADIUS
		if i == 0:
			radius = 0.0
		var ring = []
		for j in range(ROPE_RADIAL_STEPS):
			var angle = float(j) * 2.0 * PI / ROPE_RADIAL_STEPS
			var normal_dir = (right * cos(angle) + ortho_up * sin(angle)).normalized()
			var vertex_pos = current + normal_dir * radius
			ring.append({"pos": vertex_pos, "normal": normal_dir})
		rings.append(ring)
	for i in range(rings.size() - 1):
		var r1 = rings[i]; var r2 = rings[i+1]
		for j in range(ROPE_RADIAL_STEPS):
			var nj = (j + 1) % ROPE_RADIAL_STEPS
			rope_mesh.surface_set_normal(r1[j].normal); rope_mesh.surface_add_vertex(r1[j].pos)
			rope_mesh.surface_set_normal(r1[nj].normal); rope_mesh.surface_add_vertex(r1[nj].pos)
			rope_mesh.surface_set_normal(r2[j].normal); rope_mesh.surface_add_vertex(r2[j].pos)
			rope_mesh.surface_set_normal(r1[nj].normal); rope_mesh.surface_add_vertex(r1[nj].pos)
			rope_mesh.surface_set_normal(r2[nj].normal); rope_mesh.surface_add_vertex(r2[nj].pos)
			rope_mesh.surface_set_normal(r2[j].normal); rope_mesh.surface_add_vertex(r2[j].pos)
	rope_mesh.surface_end()
