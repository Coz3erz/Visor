extends CharacterBody3D

# ============================================================================
# NODE LINKS
# ============================================================================
@export_category("Node Links")
@export var head: Node3D
@export var camera: Camera3D
@export var collision_shape: CollisionShape3D

# ============================================================================
# MOVEMENT
# ============================================================================
@export_category("Movement")
@export var move_speed: float = 13.0
@export var jump_velocity: float = 8.0
@export var mouse_sensitivity: float = 0.002
@export var gravity: float = 22.0
@export var ground_friction: float = 12.0

# ============================================================================
# SLIDE
# ============================================================================
@export_category("Slide")
@export var slide_speed_boost: float = 12.0
@export var slide_steer_speed: float = 2.5
@export var slide_speed_decay: float = 1.0
@export var slide_min_speed: float = 14.0
@export var slide_camera_drop: float = 0.4
@export var slide_tilt_amount: float = 0.35
@export var slide_camera_lerp: float = 0.4
@export var air_tilt_reduction: float = 0.0

# ============================================================================
# AIR CONTROL
# ============================================================================
@export_category("Air Control")
@export var air_acceleration: float = 20.0
@export var max_air_speed: float = 25.0
@export var air_slide_gravity_mult: float = 0.4

# ============================================================================
# DASH
# ============================================================================
@export_category("Dash")
@export var dash_speed: float = 35.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 1.0

# ============================================================================
# WALL JUMPS
# ============================================================================
@export_category("Wall Jumps")
@export var wall_jump_pushback: float = 14.0

# ============================================================================
# CAMERA SHAKE (smooth spring-based, not random jitter)
# ============================================================================
@export_category("Camera Shake")
@export var shake_stiffness: float = 140.0
@export var shake_damping: float = 14.0
@export var shake_impulse_max: float = 0.4

# ============================================================================
# GROUND SLAM
# ============================================================================
@export_category("Ground Slam")
@export var slam_down_speed: float = 40.0
@export var slam_landing_boost: float = 15.0

# ============================================================================
# FOV
# ============================================================================
@export_category("Camera FOV")
@export var base_fov: float = 75.0
@export var max_fov_boost: float = 15.0
@export var fov_change_speed: float = 8.0

# ============================================================================
# STATE
# ============================================================================
var is_sliding: bool = false
var is_air_sliding: bool = false
var is_ground_slamming: bool = false
var slide_exit_timer: float = 0.0
var slide_exit_start_speed: float = 0.0
var wall_jumps_done: int = 0
var base_camera_y: float = 0.0

var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO

# Grapple state from HookController signals
var is_grappling: bool = false
var hook_controller: Node = null

# Smooth camera shake spring
var shake_offset := Vector2.ZERO
var shake_velocity := Vector2.ZERO

# ============================================================================
# INIT
# ============================================================================
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	base_camera_y = head.position.y
	camera.fov = base_fov

	var hc = get_node_or_null("HookController")
	if hc:
		hook_controller = hc
		hc.hook_attached.connect(_on_hook_attached)
		hc.hook_detached.connect(_on_hook_detached)

func _on_hook_attached(_body):
	is_grappling = true

func _on_hook_detached():
	is_grappling = false

# ============================================================================
# INPUT
# ============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, -PI/2, PI/2)

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		SceneManager.change_scene("res://scenes/main/main_menu.tscn")
	if event.is_action_pressed("ui_fullscreen"):
		_toggle_fullscreen()

func _toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

# ============================================================================
# MAIN PHYSICS LOOP
# ============================================================================
func _physics_process(delta: float) -> void:
	# Timers
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta

	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false

	if slide_exit_timer > 0:
		slide_exit_timer -= delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var wish_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Dash
	if Input.is_action_just_pressed("dash") and not is_dashing and dash_cooldown_timer <= 0:
		_start_dash(wish_dir)

	if is_dashing:
		velocity = dash_direction * dash_speed
		move_and_slide()
		_update_fov(delta)
		return

	# Ground slam – allows horizontal movement while slamming down
	if is_ground_slamming:
		_update_ground_slam(wish_dir, delta)
		_update_fov(delta)
		return

	# Start ground slam (fresh crouch press in air, not while air sliding)
	if not is_on_floor() and Input.is_action_just_pressed("crouch") and not is_air_sliding and not is_sliding:
		_start_ground_slam()
		# Continue into same frame with slam state
		_update_ground_slam(wish_dir, delta)
		_update_fov(delta)
		return

	handle_slide_state(wish_dir, delta)
	handle_jumping(wish_dir)
	handle_camera_tilt(delta)
	handle_camera_shake(delta)

	if not is_on_floor():
		if is_air_sliding:
			velocity.y -= gravity * air_slide_gravity_mult * delta
		else:
			velocity.y -= gravity * delta

	apply_movement(wish_dir, delta)
	move_and_slide()

	# Landing shake
	if is_on_floor() and velocity.y < -12.0:
		add_camera_shake(0.3)

	_update_fov(delta)

# ============================================================================
# DASH
# ============================================================================
func _start_dash(wish_dir: Vector3) -> void:
	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	dash_direction = wish_dir if wish_dir.length() > 0.1 else -transform.basis.z
	add_camera_shake(0.2)

# ============================================================================
# GROUND SLAM (horizontal control preserved, stops early if rope taut)
# ============================================================================
func _start_ground_slam() -> void:
	is_ground_slamming = true
	velocity.y = -slam_down_speed
	add_camera_shake(0.3)

func _update_ground_slam(wish_dir: Vector3, delta: float) -> void:
	if hook_controller and hook_controller.has_method("is_rope_taut") and hook_controller.is_rope_taut():
		is_ground_slamming = false
		return

	# Fixed downward speed
	velocity.y = -slam_down_speed

	# Horizontal air control (preserve momentum, allow steering)
	var cur_hvel := Vector3(velocity.x, 0, velocity.z)
	var wish_hvel := wish_dir * move_speed
	var add := (wish_hvel - cur_hvel).limit_length(air_acceleration * delta)
	velocity += add

	# Cap horizontal speed to max_air_speed to avoid extreme strafing
	var hspeed := Vector3(velocity.x, 0, velocity.z).length()
	if hspeed > max_air_speed:
		velocity.x *= max_air_speed / hspeed
		velocity.z *= max_air_speed / hspeed

	move_and_slide()

	if is_on_floor():
		is_ground_slamming = false
		velocity.y = 0.0
		velocity += -transform.basis.z * slam_landing_boost
		add_camera_shake(0.5)

# ============================================================================
# SLIDE STATE MACHINE
# ============================================================================
func handle_slide_state(_wish_dir: Vector3, _delta: float) -> void:
	var crouch_pressed = Input.is_action_pressed("crouch")
	var on_floor = is_on_floor()

	if crouch_pressed and slide_exit_timer > 0:
		is_sliding = true
		slide_exit_timer = 0.0
		head.position.y = lerp(head.position.y, base_camera_y - slide_camera_drop, slide_camera_lerp)
		collision_shape.shape.height = lerp(collision_shape.shape.height, 1.0, slide_camera_lerp)
		return

	if on_floor and crouch_pressed:
		if not is_sliding and velocity.length() > 5.0:
			is_sliding = true
			velocity += -transform.basis.z * slide_speed_boost
			slide_exit_timer = 0.0
			add_camera_shake(0.15)
		if is_sliding:
			head.position.y = lerp(head.position.y, base_camera_y - slide_camera_drop, slide_camera_lerp)
			collision_shape.shape.height = lerp(collision_shape.shape.height, 1.0, slide_camera_lerp)
		return

	if not on_floor and is_sliding and crouch_pressed:
		is_air_sliding = true
		is_sliding = false
		head.position.y = lerp(head.position.y, base_camera_y - slide_camera_drop, slide_camera_lerp)
		collision_shape.shape.height = lerp(collision_shape.shape.height, 1.0, slide_camera_lerp)
		return

	if is_air_sliding:
		if crouch_pressed:
			head.position.y = lerp(head.position.y, base_camera_y - slide_camera_drop, slide_camera_lerp)
			collision_shape.shape.height = lerp(collision_shape.shape.height, 1.0, slide_camera_lerp)
		else:
			is_air_sliding = false
			_start_slide_exit()
			head.position.y = lerp(head.position.y, base_camera_y, slide_camera_lerp * 1.5)
			collision_shape.shape.height = lerp(collision_shape.shape.height, 2.0, slide_camera_lerp * 1.5)
		return

	if not crouch_pressed and is_sliding:
		is_sliding = false
		_start_slide_exit()
		head.position.y = lerp(head.position.y, base_camera_y, slide_camera_lerp * 1.5)
		collision_shape.shape.height = lerp(collision_shape.shape.height, 2.0, slide_camera_lerp * 1.5)
		return

	if not is_sliding and not is_air_sliding:
		head.position.y = lerp(head.position.y, base_camera_y, slide_camera_lerp)
		collision_shape.shape.height = lerp(collision_shape.shape.height, 2.0, slide_camera_lerp)

func _start_slide_exit() -> void:
	slide_exit_start_speed = Vector2(velocity.x, velocity.z).length()
	slide_exit_timer = 1.5

# ============================================================================
# JUMPING
# ============================================================================
func handle_jumping(wish_dir: Vector3) -> void:
	if not Input.is_action_just_pressed("jump"):
		return

	if is_on_floor():
		if is_air_sliding:
			is_air_sliding = false
			velocity.y = jump_velocity * 1.4
			velocity += (-transform.basis.z if wish_dir.length() < 0.1 else wish_dir) * slide_speed_boost * 1.2
			head.position.y = base_camera_y
			collision_shape.shape.height = 2.0
			slide_exit_timer = 0.0
			return

		if is_sliding:
			velocity.y = jump_velocity
			velocity += -transform.basis.z * slide_speed_boost
			is_sliding = false
			head.position.y = base_camera_y
			collision_shape.shape.height = 2.0
			slide_exit_timer = 0.0
			if Input.is_action_pressed("crouch"):
				is_air_sliding = true
			return

		velocity.y = jump_velocity
		return

	if is_on_wall_only():
		wall_jumps_done += 1
		var n = get_wall_normal()
		velocity = n * wall_jump_pushback
		velocity.y = jump_velocity * 1.3
		add_camera_shake(0.15)

# ============================================================================
# CAMERA TILT
# ============================================================================
func handle_camera_tilt(delta: float) -> void:
	var target_tilt = 0.0

	if is_sliding:
		var hvel = Vector3(velocity.x, 0, velocity.z)
		if hvel.length() > 1.0:
			target_tilt = transform.basis.x.dot(hvel.normalized()) * slide_tilt_amount
	elif is_air_sliding:
		var hvel = Vector3(velocity.x, 0, velocity.z)
		if hvel.length() > 1.0:
			target_tilt = transform.basis.x.dot(hvel.normalized()) * slide_tilt_amount * air_tilt_reduction

	camera.rotation.z = lerp(camera.rotation.z, target_tilt, 12.0 * delta)

# ============================================================================
# SMOOTH SPRING CAMERA SHAKE
# ============================================================================
func add_camera_shake(amount: float) -> void:
	# Apply random impulse scaled by amount
	shake_velocity.x += randf_range(-1.0, 1.0) * amount
	shake_velocity.y += randf_range(-1.0, 1.0) * amount
	shake_velocity = shake_velocity.limit_length(shake_impulse_max)

func handle_camera_shake(delta: float) -> void:
	# Spring-damper simulation for smooth decay
	var force := -shake_stiffness * shake_offset - shake_damping * shake_velocity
	shake_velocity += force * delta
	shake_offset += shake_velocity * delta

	# Apply to camera offsets
	camera.h_offset = shake_offset.x
	camera.v_offset = shake_offset.y

	# Reset if very small to avoid drift
	if shake_offset.length() < 0.001 and shake_velocity.length() < 0.001:
		shake_offset = Vector2.ZERO
		shake_velocity = Vector2.ZERO

# ============================================================================
# DYNAMIC FOV
# ============================================================================
func _update_fov(delta: float) -> void:
	var hspeed = Vector2(velocity.x, velocity.z).length()
	var speed_factor = clamp(hspeed / max_air_speed, 0.0, 1.0)
	var target_fov = base_fov + speed_factor * max_fov_boost
	camera.fov = lerp(camera.fov, target_fov, fov_change_speed * delta)

# ============================================================================
# NORMAL MOVEMENT
# ============================================================================
func apply_movement(wish_dir: Vector3, delta: float) -> void:
	if is_sliding or is_air_sliding:
		var hvel = Vector3(velocity.x, 0, velocity.z)
		var speed = max(hvel.length(), slide_min_speed)
		speed = max(speed - slide_speed_decay * delta, slide_min_speed)
		var cur = hvel.normalized() if hvel.length() > 0.1 else -transform.basis.z
		var new_dir = lerp(cur, wish_dir, slide_steer_speed * delta).normalized()
		velocity.x = new_dir.x * speed
		velocity.z = new_dir.z * speed
		return

	if slide_exit_timer > 0:
		var t = 1.0 - (slide_exit_timer / 1.5)
		var target_speed = lerp(slide_exit_start_speed, move_speed, t)
		var cur2 = Vector2(velocity.x, velocity.z)
		var des = Vector2(wish_dir.x, wish_dir.z) * target_speed
		var new2 = cur2.lerp(des, 4.0 * delta)
		velocity.x = new2.x
		velocity.z = new2.y
		return

	if not is_on_floor():
		if is_grappling:
			return

		var cur_hvel = Vector3(velocity.x, 0, velocity.z)
		var wish_hvel = wish_dir * move_speed
		var add = (wish_hvel - cur_hvel).limit_length(air_acceleration * delta)
		velocity += add
		var hspeed = Vector3(velocity.x, 0, velocity.z).length()
		if hspeed > max_air_speed:
			velocity.x *= max_air_speed / hspeed
			velocity.z *= max_air_speed / hspeed
		return

	velocity.x = lerp(velocity.x, wish_dir.x * move_speed, ground_friction * delta)
	velocity.z = lerp(velocity.z, wish_dir.z * move_speed, ground_friction * delta)
