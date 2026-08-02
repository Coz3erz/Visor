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
# SLIDE – now with acceleration over time
# ============================================================================
@export_category("Slide")
@export var slide_speed_boost: float = 12.0       # initial burst when sliding starts
@export var slide_steer_speed: float = 2.5         # turning responsiveness
@export var slide_acceleration: float = 10.0       # how fast the slide gains speed
@export var slide_max_speed: float = 35.0          # top speed while sliding
@export var slide_min_speed: float = 14.0          # minimum (ignored with acceleration, kept for compatibility)
@export var slide_camera_drop: float = 0.4
@export var slide_tilt_amount: float = 0.35
@export var slide_camera_lerp: float = 0.4

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
# STATE
# ============================================================================
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

# ============================================================================
# INITIALIZATION
# ============================================================================
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	base_camera_y = head.position.y
	camera.fov = 75.0

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

# ============================================================================
# MAIN PHYSICS LOOP
# ============================================================================
func _physics_process(delta: float) -> void:
	# Timers
	if dash_cooldown_timer > 0: dash_cooldown_timer -= delta
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0: is_dashing = false
	if slide_exit_timer > 0: slide_exit_timer -= delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var wish_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Dash
	if Input.is_action_just_pressed("dash") and not is_dashing and dash_cooldown_timer <= 0:
		_start_dash(wish_dir)
	if is_dashing:
		velocity = dash_direction * dash_speed
		move_and_slide()
		return

	# State machines
	handle_slide_state(wish_dir, delta)
	handle_jumping(wish_dir)
	handle_camera_tilt(delta)

	# Gravity (reduced during air slide)
	if not is_on_floor():
		if is_air_sliding:
			velocity.y -= gravity * air_slide_gravity_mult * delta
		else:
			velocity.y -= gravity * delta

	# Final movement
	apply_movement(wish_dir, delta)
	move_and_slide()

# ============================================================================
# DASH
# ============================================================================
func _start_dash(wish_dir: Vector3) -> void:
	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	dash_direction = wish_dir if wish_dir.length() > 0.1 else -transform.basis.z

# ============================================================================
# SLIDE STATE MACHINE (no jitter, now with acceleration)
# ============================================================================
func handle_slide_state(wish_dir: Vector3, delta: float) -> void:
	var crouch_pressed = Input.is_action_pressed("crouch")
	var on_floor = is_on_floor()
	var horizontal_speed = Vector3(velocity.x, 0.0, velocity.z).length()

	# Instant resume from exit blend
	if crouch_pressed and slide_exit_timer > 0.0:
		slide_exit_timer = 0.0
		if on_floor:
			is_sliding = true
			is_air_sliding = false
		else:
			is_air_sliding = true
			is_sliding = false
		_update_slide_camera(delta, base_camera_y - slide_camera_drop, 1.0)
		return

	# Ground slide
	if is_sliding:
		if not crouch_pressed:
			is_sliding = false
			_start_slide_exit()
			_update_slide_camera(delta, base_camera_y, 2.0, 1.5)
			return
		if not on_floor:
			is_sliding = false
			is_air_sliding = true
			_update_slide_camera(delta, base_camera_y - slide_camera_drop, 1.0)
			return
		_update_slide_camera(delta, base_camera_y - slide_camera_drop, 1.0)
		return

	# Air slide
	if is_air_sliding:
		if not crouch_pressed:
			is_air_sliding = false
			_start_slide_exit()
			_update_slide_camera(delta, base_camera_y, 2.0, 1.5)
			return
		if on_floor:
			is_air_sliding = false
			is_sliding = true
			_update_slide_camera(delta, base_camera_y - slide_camera_drop, 1.0)
			return
		_update_slide_camera(delta, base_camera_y - slide_camera_drop, 1.0)
		return

	# Start a fresh slide
	if on_floor and crouch_pressed and horizontal_speed > 5.0:
		is_sliding = true
		velocity += -transform.basis.z * slide_speed_boost
		slide_exit_timer = 0.0
		_update_slide_camera(delta, base_camera_y - slide_camera_drop, 1.0)
		return

	# Idle / exit blend – ease camera back to standing
	_update_slide_camera(delta, base_camera_y, 2.0)

func _update_slide_camera(delta: float, target_y: float, target_height: float, speed_mult: float = 1.0) -> void:
	var t = clamp(slide_camera_lerp * speed_mult * 60.0 * delta, 0.0, 1.0)
	head.position.y = lerp(head.position.y, target_y, t)
	collision_shape.shape.height = lerp(collision_shape.shape.height, target_height, t)

func _start_slide_exit() -> void:
	slide_exit_start_speed = Vector2(velocity.x, velocity.z).length()
	slide_exit_timer = 1.5

# ============================================================================
# JUMPING
# ============================================================================
func handle_jumping(wish_dir: Vector3) -> void:
	if not Input.is_action_just_pressed("jump"): return
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
			if Input.is_action_pressed("crouch"): is_air_sliding = true
			return
		velocity.y = jump_velocity
		return
	if is_on_wall_only():
		wall_jumps_done += 1
		var n = get_wall_normal()
		velocity = n * wall_jump_pushback
		velocity.y = jump_velocity * 1.3

# ============================================================================
# CAMERA TILT (slide drift only)
# ============================================================================
func handle_camera_tilt(delta: float) -> void:
	var target_tilt = 0.0
	if is_sliding or is_air_sliding:
		var hvel = Vector3(velocity.x, 0, velocity.z)
		if hvel.length() > 1.0: target_tilt = transform.basis.x.dot(hvel.normalized()) * slide_tilt_amount
	camera.rotation.z = lerp(camera.rotation.z, target_tilt, 12.0 * delta)

# ============================================================================
# MOVEMENT (slide acceleration, drift steering, normal)
# ============================================================================
func apply_movement(wish_dir: Vector3, delta: float) -> void:
	if is_sliding or is_air_sliding:
		# Drift steering with speed **increase** over time
		var hvel = Vector3(velocity.x, 0, velocity.z)
		var speed = hvel.length()

		# Accelerate while sliding (capped)
		speed = min(speed + slide_acceleration * delta, slide_max_speed)

		var cur = hvel.normalized() if hvel.length() > 0.1 else -transform.basis.z
		var new_dir = lerp(cur, wish_dir, slide_steer_speed * delta).normalized()
		velocity.x = new_dir.x * speed
		velocity.z = new_dir.z * speed
		return

	# Slide exit blend – smoothly reduce speed over 1.5 seconds
	if slide_exit_timer > 0:
		var t = 1.0 - (slide_exit_timer / 1.5)
		var target_speed = lerp(slide_exit_start_speed, move_speed, t)
		var cur2 = Vector2(velocity.x, velocity.z)
		var des = Vector2(wish_dir.x, wish_dir.z) * target_speed
		var new2 = cur2.lerp(des, 4.0 * delta)
		velocity.x = new2.x
		velocity.z = new2.y
		return

	# Normal air movement
	if not is_on_floor():
		var cur_hvel = Vector3(velocity.x, 0, velocity.z)
		var wish_hvel = wish_dir * move_speed
		var add = (wish_hvel - cur_hvel).limit_length(air_acceleration * delta)
		velocity += add
		var hspeed = Vector3(velocity.x, 0, velocity.z).length()
		if hspeed > max_air_speed: velocity.x *= max_air_speed / hspeed; velocity.z *= max_air_speed / hspeed
		return

	# Normal ground movement
	velocity.x = lerp(velocity.x, wish_dir.x * move_speed, ground_friction * delta)
	velocity.z = lerp(velocity.z, wish_dir.z * move_speed, ground_friction * delta)
