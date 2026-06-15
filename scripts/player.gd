extends CharacterBody3D

const SPEED = 12.0
const ACCEL = 6.0
const DECEL = 8.0
const JUMP_VELOCITY = 6.5
const MOUSE_SENSITIVITY = 0.003
const ROPE_SEGMENTS = 16

@onready var neck = $Neck
@onready var camera = $Neck/Camera
@onready var raycast = $Neck/Camera/RayCast3D
@onready var rope_mesh = $GrappleRope

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_grappling = false
var grapple_point = Vector3.ZERO
var max_rope_length = 0.0
var rope_extending = 0.0
var rope_sag_velocity = 0.0
var rope_sag_amount = 0.0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_setup_rope_material()

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		neck.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-85), deg_to_rad(85))
	
	if event.is_action_pressed("ui_fullscreen") or (event is InputEventKey and event.keycode == KEY_F11 and event.pressed):
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	if Input.is_action_just_pressed("grapple"):
		if raycast.is_colliding():
			grapple_point = raycast.get_collision_point()
			is_grappling = true
			max_rope_length = global_position.distance_to(grapple_point)
			rope_extending = 0.0
			rope_sag_amount = 0.0
			rope_sag_velocity = 0.0

	if Input.is_action_just_released("grapple"):
		is_grappling = false
		rope_extending = 0.0

	if is_grappling:
		var current_dist = global_position.distance_to(grapple_point)
		var grapple_dir = (grapple_point - global_position).normalized()
		
		if current_dist > max_rope_length:
			var extension = clamp(current_dist - max_rope_length, 0.0, 5.0)
			var spring_k = 65.0
			var damping_c = 10.0
			
			var spring_force = extension * spring_k
			var vel_outward = velocity.dot(grapple_dir)
			var damping_force = vel_outward * damping_c
			
			velocity += grapple_dir * (spring_force - damping_force) * delta
			
		_draw_environmental_rope()
	else:
		if rope_mesh.mesh:
			rope_mesh.mesh.clear_surfaces()

	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = (neck.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		if is_grappling:
			var grapple_dir = (grapple_point - global_position).normalized()
			var wish_dir = direction - grapple_dir * direction.dot(grapple_dir)
			velocity.x = lerp(velocity.x, wish_dir.x * SPEED, ACCEL * delta)
			velocity.z = lerp(velocity.z, wish_dir.z * SPEED, ACCEL * delta)
		else:
			velocity.x = lerp(velocity.x, direction.x * SPEED, ACCEL * delta)
			velocity.z = lerp(velocity.z, direction.z * SPEED, ACCEL * delta)
	else:
		if is_grappling:
			velocity.x = lerp(velocity.x, 0.0, 1.0 * delta)
			velocity.z = lerp(velocity.z, 0.0, 1.0 * delta)
		else:
			velocity.x = lerp(velocity.x, 0.0, DECEL * delta)
			velocity.z = lerp(velocity.z, 0.0, DECEL * delta)

	move_and_slide()

func _setup_rope_material():
	rope_mesh.mesh = ImmediateMesh.new()

	var base_mat = StandardMaterial3D.new()
	base_mat.shading_mode = StandardMaterial3D.SHADING_MODE_PER_PIXEL
	base_mat.albedo_color = Color(0.0, 0.4, 1.0, 1.0)
	base_mat.emission_enabled = true
	base_mat.emission = Color(0.0, 0.6, 1.0, 1.0)
	base_mat.emission_energy_multiplier = 4.0
	
	var outline_mat = StandardMaterial3D.new()
	outline_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	outline_mat.cull_mode = StandardMaterial3D.CULL_FRONT
	outline_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	outline_mat.grow = true
	outline_mat.grow_amount = 0.02
	
	base_mat.next_pass = outline_mat
	rope_mesh.material_override = base_mat

func _draw_environmental_rope():
	var t_mesh: ImmediateMesh = rope_mesh.mesh
	if not t_mesh: return
	
	var start_pos = camera.global_position + (camera.global_transform.basis.z * -0.3) + (camera.global_transform.basis.x * 0.6) + (camera.global_transform.basis.y * -0.7)
	
	var delta = get_process_delta_time()
	rope_extending = move_toward(rope_extending, 1.0, delta * 9.0)
	var current_end = start_pos.lerp(grapple_point, rope_extending)
	
	var time_passed = Time.get_ticks_msec() / 1000.0
	
	if rope_extending >= 1.0:
		var target_sag = 0.15
		if velocity.length() > 5.0:
			target_sag = 0.03
		rope_sag_velocity += (target_sag - rope_sag_amount) * 12.0 * delta
		rope_sag_velocity *= 0.88
		rope_sag_amount += rope_sag_velocity * delta
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(start_pos, current_end)
	var result = space_state.intersect_ray(query)
	
	var visual_midpoint = start_pos.lerp(current_end, 0.5)
	if result and result.position.distance_to(current_end) > 0.3:
		var push_dir = result.normal
		if push_dir.length_squared() < 0.01:
			push_dir = Vector3.UP
		visual_midpoint = result.position + (push_dir * 0.25)
		
	var path_points = []
	for i in range(ROPE_SEGMENTS + 1):
		var t = float(i) / float(ROPE_SEGMENTS)
		var p = Vector3.ZERO
		
		if t < 0.5:
			p = start_pos.lerp(visual_midpoint, t * 2.0)
		else:
			p = visual_midpoint.lerp(current_end, (t - 0.5) * 2.0)
			
		if rope_extending < 1.0:
			var wave = sin(t * PI * 4.0 - time_passed * 40.0) * 0.1 * (1.0 - rope_extending)
			p += camera.global_transform.basis.y * wave
		else:
			var sag_offset = sin(t * PI) * -rope_sag_amount
			p += Vector3.UP * sag_offset
			
			var vibrate = sin(t * PI) * sin(time_passed * 60.0) * 0.015 * exp(-(time_passed - (time_passed - 0.1)) * 6.0)
			p += camera.global_transform.basis.y * vibrate
			
		var wall_check = PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 0.5)
		var wall_res = space_state.intersect_ray(wall_check)
		if wall_res and p.distance_to(wall_res.position) < 0.15:
			p += wall_res.normal * 0.12
			
		path_points.append(p)
		
	t_mesh.clear_surfaces()
	t_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var radius = 0.025
	var radial_segments = 6
	var rings = []
	
	for i in range(path_points.size()):
		var current = path_points[i]
		var forward = Vector3.ZERO
		if i == 0:
			forward = (path_points[i+1] - current).normalized()
		elif i == path_points.size() - 1:
			forward = (current - path_points[i-1]).normalized()
		else:
			forward = (path_points[i+1] - path_points[i-1]).normalized()
			
		var up = Vector3.UP
		if abs(forward.dot(up)) > 0.99:
			up = Vector3.FORWARD
		var right = forward.cross(up).normalized()
		var ortho_up = right.cross(forward).normalized()
		
		var ring = []
		for j in range(radial_segments):
			var angle = float(j) * 2.0 * PI / float(radial_segments)
			var normal_dir = (right * cos(angle) + ortho_up * sin(angle)).normalized()
			var vertex_pos = current + normal_dir * radius
			ring.append({"pos": rope_mesh.to_local(vertex_pos), "normal": normal_dir})
		rings.append(ring)
		
	for i in range(rings.size() - 1):
		var ring1 = rings[i]
		var ring2 = rings[i+1]
		for j in range(radial_segments):
			var next_j = (j + 1) % radial_segments
			
			t_mesh.surface_set_normal(ring1[j].normal)
			t_mesh.surface_add_vertex(ring1[j].pos)
			t_mesh.surface_set_normal(ring1[next_j].normal)
			t_mesh.surface_add_vertex(ring1[next_j].pos)
			t_mesh.surface_set_normal(ring2[j].normal)
			t_mesh.surface_add_vertex(ring2[j].pos)
			
			t_mesh.surface_set_normal(ring1[next_j].normal)
			t_mesh.surface_add_vertex(ring1[next_j].pos)
			t_mesh.surface_set_normal(ring2[next_j].normal)
			t_mesh.surface_add_vertex(ring2[next_j].pos)
			t_mesh.surface_set_normal(ring2[j].normal)
			t_mesh.surface_add_vertex(ring2[j].pos)
			
	t_mesh.surface_end()
