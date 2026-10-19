extends Node3D

var player: CharacterBody3D
var camera: Camera3D
var web_line: MeshInstance3D
var web_mesh: ImmediateMesh
var web_material: StandardMaterial3D
var web_target_indicator: ColorRect
var hero_root: Node3D
var upper_body: Node3D
var left_arm_pivot: Node3D
var right_arm_pivot: Node3D
var left_leg_pivot: Node3D
var right_leg_pivot: Node3D
var hand_attachment: Node3D
var web_active := false
var web_anchor := Vector3.ZERO
var rope_length := 0.0
var web_target_available := false
var web_target_check_timer := 0.0
var preferred_web_anchor := Vector3.ZERO
var web_search_shape: SphereShape3D
var web_search_query: PhysicsShapeQueryParameters3D
var web_ray_query: PhysicsRayQueryParameters3D
var web_candidates: Array[Dictionary] = []
var camera_panning_enabled := false
var jumps_remaining := 2
var camera_yaw: float = 0.0
var camera_pitch: float = 0.0
var camera_position_initialized := false
var run_animation_phase: float = 0.0
var run_animation_weight: float = 0.0
var swing_pose_weight: float = 0.0

const GROUND_SPEED := 24.0
const AIR_SPEED := 28.0
const GROUND_ACCELERATION := 60.0
const AIR_ACCELERATION := 14.0
const JUMP_FORCE := 26.0
const GRAVITY := 32.0
const WEB_RANGE := 300.0
const WEB_ASSIST_RADIUS := 110.0
const WEB_MIN_ANCHOR_HEIGHT := 5.0
const WEB_CANDIDATE_LIMIT := 24
const WEB_VISIBILITY_MARGIN := 0.25
const WEB_SCREEN_SAMPLE_RADIUS := 24.0
const WEB_TARGET_REFRESH_INTERVAL := 0.15
const SCORE_HEIGHT_WEIGHT := 0.20
const SCORE_FORWARD_WEIGHT := 0.20
const SCORE_MOMENTUM_WEIGHT := 0.40
const SCORE_DISTANCE_WEIGHT := 0.20
const WEB_CLIMB_SPEED := 22.0
const SPRING_STRENGTH := 20.0
const SPRING_DAMPING := 5.0
const MAX_SPRING_FORCE := 115.0
const ROPE_SAFETY_STRETCH := 1.5
const SWING_FORWARD_FORCE := 30.0
const SWING_SIDE_FORCE := 42.0
const SWING_REVERSE_FORCE := 24.0
const MAX_SWING_SPEED := 82.0
const WEB_ATTACH_YANK_IMPULSE := 12.0
const MIN_ROPE_LENGTH := 7.0
const MOUSE_SENSITIVITY := 0.003
const CAMERA_WHEEL_PAN_STEP := 0.12
const DEFAULT_CAMERA_DISTANCE: float = 14.0
const DEFAULT_CAMERA_HEIGHT: float = 3.5
const DEFAULT_CAMERA_PITCH: float = 0.0
const CAMERA_POSITION_SMOOTHING: float = 10.0
const CAMERA_COLLISION_MARGIN: float = 0.5
const CAMERA_MINIMUM_HEIGHT: float = 0.75
const CAMERA_LOOK_HEIGHT: float = 1.0
const CITY_EXTENT := 350
const BUILDING_SPACING := 48

func _ready():
	randomize()
	web_search_shape = SphereShape3D.new()
	web_search_shape.radius = WEB_ASSIST_RADIUS
	web_search_query = PhysicsShapeQueryParameters3D.new()
	web_search_query.shape = web_search_shape
	web_search_query.collide_with_areas = false
	web_search_query.collide_with_bodies = true
	web_ray_query = PhysicsRayQueryParameters3D.new()
	web_ray_query.collide_with_areas = false
	web_ray_query.collide_with_bodies = true
	create_floor()
	create_city()
	create_player()
	create_lighting()
	create_web_line()
	create_crosshair()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				camera_panning_enabled = true
				attach_web(event.position)
			else:
				camera_panning_enabled = false
				release_web()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			release_web()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_yaw -= CAMERA_WHEEL_PAN_STEP
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_yaw += CAMERA_WHEEL_PAN_STEP
	if event is InputEventMouseMotion:
		if camera_panning_enabled:
			camera_yaw += event.relative.x * MOUSE_SENSITIVITY

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			reset_player()

func _physics_process(delta):
	if player == null:
		return
	update_web_target_indicator(delta)
	if not web_active and player.is_on_floor():
		jumps_remaining = 2
	handle_player_movement(delta)
	if web_active:
		apply_web_physics(delta)
	player.move_and_slide()
	if web_active:
		enforce_rope_constraint()
	update_character_animation(delta)
	update_camera(delta)
	update_web_line()
	if player.global_position.y < -40.0:
		reset_player()

func handle_player_movement(delta: float):
	if web_active:
		player.velocity.y -= GRAVITY * delta
		return

	var input_vector := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		input_vector.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_vector.y += 1.0
	if Input.is_key_pressed(KEY_A):
		input_vector.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_vector.x += 1.0
	if input_vector.length() > 1.0:
		input_vector = input_vector.normalized()
	var camera_forward := -camera.global_transform.basis.z
	var camera_right := camera.global_transform.basis.x
	camera_forward.y = 0.0
	camera_right.y = 0.0
	camera_forward = camera_forward.normalized()
	camera_right = camera_right.normalized()
	var desired_direction := camera_right * input_vector.x + camera_forward * -input_vector.y
	if desired_direction.length() > 0.0:
		desired_direction = desired_direction.normalized()
	if player.is_on_floor():
		var target_velocity := desired_direction * GROUND_SPEED
		player.velocity.x = move_toward(player.velocity.x, target_velocity.x, GROUND_ACCELERATION * delta)
		player.velocity.z = move_toward(player.velocity.z, target_velocity.z, GROUND_ACCELERATION * delta)
	else:
		var target_air_velocity := desired_direction * AIR_SPEED
		player.velocity.x = move_toward(player.velocity.x, target_air_velocity.x, AIR_ACCELERATION * delta)
		player.velocity.z = move_toward(player.velocity.z, target_air_velocity.z, AIR_ACCELERATION * delta)
		player.velocity.y -= GRAVITY * delta
	if Input.is_action_just_pressed("ui_accept") and jumps_remaining > 0:
		player.velocity.y = JUMP_FORCE
		jumps_remaining -= 1

func attach_web(screen_position: Vector2):
	if camera == null or player == null:
		return
	var result := find_web_target(screen_position)
	if result.is_empty():
		return
	var hit_position: Vector3 = result["position"]
	web_anchor = hit_position
	rope_length = maxf(get_web_origin().distance_to(web_anchor), MIN_ROPE_LENGTH)
	web_active = true
	var direction_to_anchor: Vector3 = (
		web_anchor - get_web_origin()
	).normalized()
	player.velocity += (
		direction_to_anchor
		* WEB_ATTACH_YANK_IMPULSE
	)

func find_web_target(screen_position: Vector2) -> Dictionary:
	var origin := get_web_origin()
	web_candidates.clear()

	var direct_hit := raycast_web_target(screen_position)
	if not direct_hit.is_empty():
		add_web_candidate(direct_hit, true, origin)

	var half_radius := WEB_SCREEN_SAMPLE_RADIUS * 0.5
	var sample_offsets: Array[Vector2] = [
		Vector2(-half_radius, 0.0),
		Vector2(half_radius, 0.0),
		Vector2(0.0, -half_radius),
		Vector2(0.0, half_radius),
		Vector2(-half_radius, -half_radius),
		Vector2(half_radius, -half_radius),
		Vector2(-half_radius, half_radius),
		Vector2(half_radius, half_radius)
	]
	for offset in sample_offsets:
		if web_candidates.size() >= WEB_CANDIDATE_LIMIT:
			break
		var sampled_hit := raycast_web_target(screen_position + offset)
		if not sampled_hit.is_empty():
			add_web_candidate(sampled_hit, false, origin)

	web_search_query.transform = Transform3D(Basis.IDENTITY, origin)
	web_search_query.exclude = [player.get_rid()]
	var nearby_hits := get_world_3d().direct_space_state.intersect_shape(
		web_search_query,
		WEB_CANDIDATE_LIMIT
	)
	for nearby_hit in nearby_hits:
		if web_candidates.size() >= WEB_CANDIDATE_LIMIT:
			break
		var collider: Object = nearby_hit.get("collider")
		if not is_valid_web_body(collider):
			continue
		add_building_surface_candidates(collider, origin)

	var best_candidate: Dictionary = {}
	var best_assisted_score := -INF
	var best_direct_score := -INF
	var best_direct_candidate: Dictionary = {}
	for candidate in web_candidates:
		var anchor: Vector3 = candidate["position"]
		var body: StaticBody3D = candidate["body"]
		if not is_web_anchor_visible(origin, anchor, body):
			continue
		var score := score_web_candidate(anchor, origin)
		if candidate["direct"]:
			if score > best_direct_score:
				best_direct_score = score
				best_direct_candidate = candidate
		elif score > best_assisted_score:
			best_assisted_score = score
			best_candidate = candidate

	if not best_direct_candidate.is_empty() and (
		best_assisted_score == -INF or best_direct_score >= best_assisted_score - 0.08
	):
		preferred_web_anchor = best_direct_candidate["position"]
		return best_direct_candidate
	if not best_candidate.is_empty():
		preferred_web_anchor = best_candidate["position"]
		return best_candidate
	if not best_direct_candidate.is_empty():
		preferred_web_anchor = best_direct_candidate["position"]
		return best_direct_candidate
	preferred_web_anchor = Vector3.ZERO
	return {}

func is_valid_web_body(collider: Object) -> bool:
	return collider is StaticBody3D and collider.name != "CityGround"

func add_web_candidate(hit: Dictionary, direct_aim: bool, origin: Vector3):
	if web_candidates.size() >= WEB_CANDIDATE_LIMIT:
		return
	var collider: Object = hit.get("collider")
	if not is_valid_web_body(collider):
		return
	var anchor: Vector3 = hit["position"]
	if not is_valid_web_anchor(anchor, origin):
		return
	for existing in web_candidates:
		var existing_position: Vector3 = existing["position"]
		if existing_position.distance_squared_to(anchor) < 1.0:
			if direct_aim:
				existing["direct"] = true
			return
	web_candidates.append({
		"position": anchor,
		"body": collider,
		"direct": direct_aim
	})

func add_building_surface_candidates(body: Object, origin: Vector3):
	var building := body as StaticBody3D
	for child in building.get_children():
		if web_candidates.size() >= WEB_CANDIDATE_LIMIT:
			return
		if not child is CollisionShape3D:
			continue
		var collision_shape := child as CollisionShape3D
		if not collision_shape.shape is BoxShape3D:
			continue
		var box_shape := collision_shape.shape as BoxShape3D
		var half_size: Vector3 = box_shape.size * 0.5
		var shape_transform := collision_shape.global_transform
		var center: Vector3 = shape_transform.origin
		var axis_x: Vector3 = shape_transform.basis.x.normalized()
		var axis_y: Vector3 = shape_transform.basis.y.normalized()
		var axis_z: Vector3 = shape_transform.basis.z.normalized()
		var surface_points: Array[Vector3] = [
			center + axis_y * half_size.y,
			center + axis_x * half_size.x,
			center - axis_x * half_size.x,
			center + axis_z * half_size.z,
			center - axis_z * half_size.z
		]
		for point in surface_points:
			if web_candidates.size() >= WEB_CANDIDATE_LIMIT:
				return
			if not is_valid_web_anchor(point, origin):
				continue
			var hit := {"position": point, "collider": building}
			add_web_candidate(hit, false, origin)

func is_valid_web_anchor(anchor: Vector3, origin: Vector3) -> bool:
	var height_above_player: float = anchor.y - player.global_position.y
	var distance: float = origin.distance_to(anchor)
	return (
		anchor.y >= 0.0
		and height_above_player >= WEB_MIN_ANCHOR_HEIGHT
		and distance <= WEB_ASSIST_RADIUS
		and distance <= WEB_RANGE
	)

func is_web_anchor_visible(origin: Vector3, anchor: Vector3, target: StaticBody3D) -> bool:
	var to_anchor: Vector3 = anchor - origin
	var distance: float = to_anchor.length()
	if distance <= WEB_VISIBILITY_MARGIN:
		return false
	var ray_end: Vector3 = anchor - to_anchor / distance * WEB_VISIBILITY_MARGIN
	web_ray_query.from = origin
	web_ray_query.to = ray_end
	web_ray_query.exclude = [player.get_rid()]
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(web_ray_query)
	if result.is_empty():
		return true
	return (
		result.get("collider") == target
		and Vector3(result["position"]).distance_to(anchor)
			<= WEB_VISIBILITY_MARGIN * 2.0
	)

func score_web_candidate(anchor: Vector3, origin: Vector3) -> float:
	var to_anchor: Vector3 = anchor - origin
	var distance: float = to_anchor.length()
	var direction: Vector3 = to_anchor / maxf(distance, 0.001)
	var height_delta: float = anchor.y - player.global_position.y
	var preferred_height: float = WEB_ASSIST_RADIUS * 0.45
	var height_score: float = clampf(
		1.0 - absf(height_delta - preferred_height) / preferred_height,
		0.0,
		1.0
	)

	var camera_forward: Vector3 = -camera.global_transform.basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()
	var horizontal_direction := Vector3(direction.x, 0.0, direction.z)
	var forward_score := 0.5
	if horizontal_direction.length_squared() > 0.0001:
		forward_score = clampf(
			(horizontal_direction.normalized().dot(camera_forward) + 1.0) * 0.5,
			0.0,
			1.0
		)

	var speed: float = player.velocity.length()
	var momentum_score := 0.5
	if speed > 0.1:
		var velocity_direction: Vector3 = player.velocity / speed
		var radial_speed: float = player.velocity.dot(direction)
		var tangential_velocity: Vector3 = player.velocity - direction * radial_speed
		var tangent_score: float = tangential_velocity.length() / speed
		var alignment: float = velocity_direction.dot(direction)
		var tractor_penalty: float = maxf(alignment, 0.0) * 0.25
		var reversal_penalty: float = maxf(-alignment, 0.0) * 0.35
		momentum_score = clampf(
			tangent_score - tractor_penalty - reversal_penalty,
			0.0,
			1.0
		)

		var camera_right: Vector3 = camera.global_transform.basis.x
		camera_right.y = 0.0
		camera_right = camera_right.normalized()
		var lateral_speed: float = Vector3(
			player.velocity.x,
			0.0,
			player.velocity.z
		).dot(camera_right)
		if absf(lateral_speed) > 0.1 and horizontal_direction.length_squared() > 0.0001:
			var side_alignment: float = horizontal_direction.normalized().dot(camera_right)
			if lateral_speed < 0.0:
				side_alignment = -side_alignment
			var side_score: float = clampf((side_alignment + 1.0) * 0.5, 0.0, 1.0)
			momentum_score = lerpf(momentum_score, side_score, 0.2)

	var preferred_distance: float = WEB_ASSIST_RADIUS * 0.58
	var distance_score: float = clampf(
		1.0 - absf(distance - preferred_distance) / preferred_distance,
		0.0,
		1.0
	)
	return (
		height_score * SCORE_HEIGHT_WEIGHT
		+ forward_score * SCORE_FORWARD_WEIGHT
		+ momentum_score * SCORE_MOMENTUM_WEIGHT
		+ distance_score * SCORE_DISTANCE_WEIGHT
	)

func raycast_web_target(screen_position: Vector2) -> Dictionary:
	var ray_start := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var ray_end := ray_start + ray_direction * WEB_RANGE
	web_ray_query.from = ray_start
	web_ray_query.to = ray_end
	web_ray_query.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(web_ray_query)

func update_web_target_indicator(delta: float):
	if web_target_indicator == null:
		return
	web_target_check_timer -= delta
	if not web_active and web_target_check_timer <= 0.0:
		web_target_check_timer = WEB_TARGET_REFRESH_INTERVAL
		var target := find_web_target(
			get_viewport().get_mouse_position()
		)
		web_target_available = not target.is_empty()

	web_target_indicator.position = get_viewport().get_mouse_position() + Vector2(14.0, -4.0)
	if web_active:
		web_target_indicator.color = Color(1.0, 0.72, 0.18, 1.0)
	elif web_target_available:
		web_target_indicator.color = Color(0.15, 0.95, 0.78, 1.0)
	else:
		web_target_indicator.color = Color(0.38, 0.42, 0.48, 0.75)

func release_web():
	if web_active:
		jumps_remaining = 2
	web_active = false
	if web_mesh != null:
		web_mesh.clear_surfaces()

func apply_web_physics(delta: float):
	var anchor_to_player: Vector3 = get_web_origin() - web_anchor
	var distance: float = anchor_to_player.length()
	if distance > 0.01:
		var outward_direction: Vector3 = anchor_to_player / distance
		var stretch: float = distance - rope_length
		if stretch > 0.0:
			var outward_speed: float = player.velocity.dot(outward_direction)
			var spring_force: float = clampf(
				stretch * SPRING_STRENGTH + outward_speed * SPRING_DAMPING,
				0.0,
				MAX_SPRING_FORCE
			)
			player.velocity -= outward_direction * spring_force * delta
	apply_omnidirectional_swing_control(delta)
	if Input.is_action_pressed("ui_accept"):
		rope_length = maxf(
			MIN_ROPE_LENGTH,
			rope_length - WEB_CLIMB_SPEED * delta
		)
	if player.velocity.length() > MAX_SWING_SPEED:
		player.velocity = player.velocity.normalized() * MAX_SWING_SPEED

func apply_omnidirectional_swing_control(delta: float):
	var forward_input: float = 0.0
	var side_input: float = 0.0
	if Input.is_key_pressed(KEY_W):
		forward_input += 1.0
	if Input.is_key_pressed(KEY_S):
		forward_input -= 1.0
	if Input.is_key_pressed(KEY_A):
		side_input -= 1.0
	if Input.is_key_pressed(KEY_D):
		side_input += 1.0
	var input_vector: Vector2 = Vector2(side_input, forward_input)
	if input_vector.length() > 1.0:
		input_vector = input_vector.normalized()
	if input_vector == Vector2.ZERO:
		return
	side_input = input_vector.x
	forward_input = input_vector.y

	var forward: Vector3 = project_onto_swing_plane(-camera.global_transform.basis.z)
	var right: Vector3 = project_onto_swing_plane(camera.global_transform.basis.x)
	var forward_force: float = SWING_FORWARD_FORCE if forward_input >= 0.0 else SWING_REVERSE_FORCE
	player.velocity += (
		forward * forward_input * forward_force
		+ right * side_input * SWING_SIDE_FORCE
	) * delta

func project_onto_swing_plane(direction: Vector3) -> Vector3:
	var anchor_to_player: Vector3 = get_web_origin() - web_anchor
	if anchor_to_player.length_squared() <= 0.0001:
		return Vector3.ZERO
	var rope_direction: Vector3 = anchor_to_player.normalized()
	var projected_direction: Vector3 = direction - rope_direction * direction.dot(rope_direction)
	if projected_direction.length_squared() <= 0.0001:
		return Vector3.ZERO
	return projected_direction.normalized()

func enforce_rope_constraint():
	var anchor_to_player: Vector3 = get_web_origin() - web_anchor
	var current_distance: float = anchor_to_player.length()
	if current_distance <= rope_length + ROPE_SAFETY_STRETCH or current_distance <= 0.01:
		return
	var outward_direction: Vector3 = anchor_to_player / current_distance
	var outward_speed: float = player.velocity.dot(outward_direction)
	if outward_speed > 0.0:
		player.velocity -= outward_direction * outward_speed
	player.global_position -= outward_direction * (current_distance - rope_length)

func get_web_origin() -> Vector3:
	if hand_attachment != null:
		return hand_attachment.global_position
	return player.global_position + Vector3(0.0, 0.75, 0.0)

func update_character_animation(delta: float):
	if hero_root == null:
		return

	var horizontal_velocity := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var horizontal_speed := horizontal_velocity.length()
	var target_run_weight := 0.0
	if player.is_on_floor() and not web_active:
		target_run_weight = clampf(horizontal_speed / GROUND_SPEED, 0.0, 1.0)
	var blend := 1.0 - exp(-8.0 * delta)
	run_animation_weight = lerpf(run_animation_weight, target_run_weight, blend)
	swing_pose_weight = lerpf(swing_pose_weight, 1.0 if web_active else 0.0, blend)

	if target_run_weight > 0.01:
		run_animation_phase += delta * lerpf(4.0, 10.0, target_run_weight)

	if horizontal_speed > 0.25:
		var facing_yaw := atan2(-horizontal_velocity.x, -horizontal_velocity.z)
		hero_root.rotation.y = lerp_angle(hero_root.rotation.y, facing_yaw, blend)

	var local_velocity := hero_root.global_transform.basis.inverse() * player.velocity
	var forward_speed := clampf(-local_velocity.z / AIR_SPEED, -1.0, 1.0)
	var side_speed := clampf(local_velocity.x / AIR_SPEED, -1.0, 1.0)
	upper_body.rotation.x = lerp_angle(
		upper_body.rotation.x,
		-0.12 * forward_speed * swing_pose_weight,
		blend
	)
	upper_body.rotation.z = lerp_angle(
		upper_body.rotation.z,
		-0.10 * side_speed * swing_pose_weight,
		blend
	)

	var stride := sin(run_animation_phase) * run_animation_weight
	var trail := clampf(
		player.velocity.length() / MAX_SWING_SPEED,
		0.0,
		1.0
	) * swing_pose_weight
	left_leg_pivot.rotation.x = lerpf(
		left_leg_pivot.rotation.x,
		stride * 0.65 - trail * 0.55,
		blend
	)
	right_leg_pivot.rotation.x = lerpf(
		right_leg_pivot.rotation.x,
		-stride * 0.65 - trail * 0.55,
		blend
	)
	left_arm_pivot.rotation.x = lerpf(
		left_arm_pivot.rotation.x,
		-stride * 0.5 + trail * 0.18,
		blend
	)

	var run_arm_rotation := Quaternion(Vector3.RIGHT, stride * 0.5)
	var target_right_arm_rotation := run_arm_rotation
	if web_active:
		var anchor_direction: Vector3 = (
			upper_body.global_transform.basis.inverse()
			* (web_anchor - right_arm_pivot.global_position)
		)
		if anchor_direction.length_squared() > 0.0001:
			var web_arm_rotation := Quaternion(
				Vector3.DOWN,
				anchor_direction.normalized()
			)
			target_right_arm_rotation = run_arm_rotation.slerp(
				web_arm_rotation,
				swing_pose_weight
			)
	right_arm_pivot.quaternion = right_arm_pivot.quaternion.slerp(
		target_right_arm_rotation,
		blend
	)

func update_camera(delta: float):
	if player == null or camera == null:
		return
	camera_pitch = DEFAULT_CAMERA_PITCH

	var horizontal_distance: float = cos(camera_pitch) * DEFAULT_CAMERA_DISTANCE
	var camera_offset: Vector3 = Vector3(
		sin(camera_yaw) * horizontal_distance,
		DEFAULT_CAMERA_HEIGHT + sin(camera_pitch) * DEFAULT_CAMERA_DISTANCE,
		cos(camera_yaw) * horizontal_distance
	)
	var look_target: Vector3 = player.global_position + Vector3(0.0, CAMERA_LOOK_HEIGHT, 0.0)
	var desired_position: Vector3 = resolve_camera_position(look_target, player.global_position + camera_offset)
	if not camera_position_initialized:
		camera.global_position = desired_position
		camera_position_initialized = true
	else:
		var smoothing_weight: float = 1.0 - exp(-CAMERA_POSITION_SMOOTHING * delta)
		var smoothed_position: Vector3 = camera.global_position.lerp(desired_position, smoothing_weight)
		camera.global_position = resolve_camera_position(look_target, smoothed_position)
	camera.look_at(look_target, Vector3.UP)

func resolve_camera_position(look_target: Vector3, desired_position: Vector3) -> Vector3:
	var ray: Vector3 = desired_position - look_target
	var ray_length: float = ray.length()
	if ray_length > 0.01:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			look_target,
			desired_position
		)
		query.exclude = [player.get_rid()]
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not result.is_empty():
			var collision_position: Vector3 = result["position"]
			desired_position = collision_position - ray / ray_length * CAMERA_COLLISION_MARGIN
	desired_position.y = maxf(desired_position.y, CAMERA_MINIMUM_HEIGHT)
	return desired_position

func create_web_line():
	web_mesh = ImmediateMesh.new()
	web_material = StandardMaterial3D.new()
	web_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	web_material.albedo_color = Color(0.95, 0.97, 1.0, 1.0)
	web_line = MeshInstance3D.new()
	web_line.name = "VisibleWeb"
	web_line.mesh = web_mesh
	web_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(web_line)

func update_web_line():
	if web_mesh == null:
		return
	web_mesh.clear_surfaces()
	if not web_active:
		return
	web_mesh.surface_begin(Mesh.PRIMITIVE_LINES, web_material)
	web_mesh.surface_add_vertex(get_web_origin())
	web_mesh.surface_add_vertex(web_anchor)
	web_mesh.surface_end()

func create_floor():
	var ground := StaticBody3D.new()
	ground.name = "CityGround"

	var ground_mesh := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(900.0, 1.0, 900.0)
	ground_mesh.mesh = mesh

	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color(0.035, 0.045, 0.060)
	asphalt.metallic = 0.05
	asphalt.roughness = 0.88
	ground_mesh.material_override = asphalt

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(900.0, 1.0, 900.0)
	collision.shape = shape

	ground.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(ground_mesh)
	ground.add_child(collision)
	add_child(ground)

	create_plaza()
	create_road_markings()

func create_plaza():
	var plaza := MeshInstance3D.new()
	var plaza_mesh := BoxMesh.new()
	plaza_mesh.size = Vector3(132.0, 0.12, 132.0)
	plaza.mesh = plaza_mesh
	plaza.position = Vector3(0.0, 0.07, 0.0)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.23, 0.25, 0.29)
	stone.roughness = 0.93
	plaza.material_override = stone
	add_child(plaza)

func create_road_markings():
	var line_material := StandardMaterial3D.new()
	line_material.albedo_color = Color(0.95, 0.68, 0.13)
	line_material.emission_enabled = true
	line_material.emission = Color(0.36, 0.18, 0.02)
	line_material.emission_energy_multiplier = 0.35

	for offset in [-72.0, 72.0]:
		var stripe_x := MeshInstance3D.new()
		var stripe_x_mesh := BoxMesh.new()
		stripe_x_mesh.size = Vector3(900.0, 0.03, 0.28)
		stripe_x.mesh = stripe_x_mesh
		stripe_x.position = Vector3(0.0, 0.03, offset)
		stripe_x.material_override = line_material
		add_child(stripe_x)

		var stripe_z := MeshInstance3D.new()
		var stripe_z_mesh := BoxMesh.new()
		stripe_z_mesh.size = Vector3(0.28, 0.03, 900.0)
		stripe_z.mesh = stripe_z_mesh
		stripe_z.position = Vector3(offset, 0.03, 0.0)
		stripe_z.material_override = line_material
		add_child(stripe_z)

func create_player():
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(0.0, 4.0, 0.0)
	player.floor_snap_length = 0.3

	var collision := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.65
	capsule_shape.height = 2.4
	collision.shape = capsule_shape
	player.add_child(collision)

	hero_root = Node3D.new()
	hero_root.name = "StylizedHero"
	player.add_child(hero_root)
	upper_body = Node3D.new()
	upper_body.name = "UpperBody"
	hero_root.add_child(upper_body)

	var suit_blue := StandardMaterial3D.new()
	suit_blue.albedo_color = Color(0.035, 0.10, 0.42)
	suit_blue.metallic = 0.22
	suit_blue.roughness = 0.42

	var suit_red := StandardMaterial3D.new()
	suit_red.albedo_color = Color(0.72, 0.025, 0.045)
	suit_red.metallic = 0.12
	suit_red.roughness = 0.38

	var eye_white := StandardMaterial3D.new()
	eye_white.albedo_color = Color(0.92, 0.98, 1.0)
	eye_white.emission_enabled = true
	eye_white.emission = Color(0.25, 0.42, 0.60)
	eye_white.emission_energy_multiplier = 1.8

	add_hero_part(upper_body, "Torso", Vector3(0.85, 1.0, 0.46), Vector3(0.0, 0.34, 0.0), suit_blue)
	add_hero_part(upper_body, "Chest", Vector3(0.91, 0.39, 0.50), Vector3(0.0, 0.58, -0.01), suit_red)
	left_leg_pivot = create_limb_pivot(
		hero_root,
		"LeftLeg",
		Vector3(-0.22, -0.16, 0.0),
		Vector3(0.29, 0.92, 0.31),
		suit_blue
	)
	right_leg_pivot = create_limb_pivot(
		hero_root,
		"RightLeg",
		Vector3(0.22, -0.16, 0.0),
		Vector3(0.29, 0.92, 0.31),
		suit_blue
	)
	left_arm_pivot = create_limb_pivot(
		upper_body,
		"LeftArm",
		Vector3(-0.57, 0.71, 0.0),
		Vector3(0.25, 0.92, 0.27),
		suit_red
	)
	right_arm_pivot = create_limb_pivot(
		upper_body,
		"RightArm",
		Vector3(0.57, 0.71, 0.0),
		Vector3(0.25, 0.92, 0.27),
		suit_red
	)
	hand_attachment = Node3D.new()
	hand_attachment.name = "WebHandAttachment"
	hand_attachment.position = Vector3(0.0, -0.92, 0.0)
	right_arm_pivot.add_child(hand_attachment)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.34
	head_mesh.height = 0.68
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.05, 0.0)
	head.material_override = suit_red
	upper_body.add_child(head)

	add_hero_part(upper_body, "LeftEye", Vector3(0.14, 0.22, 0.035), Vector3(-0.12, 1.10, -0.31), eye_white)
	add_hero_part(upper_body, "RightEye", Vector3(0.14, 0.22, 0.035), Vector3(0.12, 1.10, -0.31), eye_white)

	add_child(player)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.current = true
	camera.fov = 82.0
	add_child(camera)
	update_camera(0.0)

func add_hero_part(parent: Node3D, part_name: String, size: Vector3, part_position: Vector3, material: Material):
	var part := MeshInstance3D.new()
	part.name = part_name
	var part_mesh := BoxMesh.new()
	part_mesh.size = size
	part.mesh = part_mesh
	part.position = part_position
	part.material_override = material
	parent.add_child(part)

func create_limb_pivot(
	parent: Node3D,
	part_name: String,
	pivot_position: Vector3,
	size: Vector3,
	material: Material
) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = part_name + "Pivot"
	pivot.position = pivot_position
	var part := MeshInstance3D.new()
	part.name = part_name
	var part_mesh := BoxMesh.new()
	part_mesh.size = size
	part.mesh = part_mesh
	part.position = Vector3(0.0, -size.y / 2.0, 0.0)
	part.material_override = material
	pivot.add_child(part)
	parent.add_child(pivot)
	return pivot

func create_lighting():
	var sun := DirectionalLight3D.new()
	sun.name = "GoldenSun"
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_color = Color(1.0, 0.82, 0.62)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 260.0
	add_child(sun)

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.06, 0.18, 0.42)
	sky_material.sky_horizon_color = Color(0.78, 0.48, 0.30)
	sky_material.ground_bottom_color = Color(0.03, 0.04, 0.08)
	sky_material.ground_horizon_color = Color(0.42, 0.30, 0.28)
	sky_material.sun_angle_max = 18.0
	sky_material.sun_curve = 0.12

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.72
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.04
	environment.adjustment_contrast = 1.12
	environment.adjustment_saturation = 1.18
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.48, 0.54, 0.68)
	environment.fog_light_energy = 0.55
	environment.fog_density = 0.0018
	environment.fog_height = 22.0
	environment.fog_height_density = 0.018
	environment.fog_sun_scatter = 0.22

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

func create_city():
	for x in range(-CITY_EXTENT, CITY_EXTENT + 1, BUILDING_SPACING):
		for z in range(-CITY_EXTENT, CITY_EXTENT + 1, BUILDING_SPACING):
			if abs(x) < 70 and abs(z) < 70:
				continue
			var width := randf_range(16.0, 25.0)
			var depth := randf_range(16.0, 25.0)
			var height := randf_range(35.0, 120.0)
			var building_position := Vector3(float(x) + randf_range(-4.0, 4.0), height / 2.0, float(z) + randf_range(-4.0, 4.0))
			create_building(building_position, Vector3(width, height, depth))

func create_building(building_position: Vector3, building_size: Vector3):
	var building := StaticBody3D.new()
	building.name = "Building"
	building.position = building_position

	var building_mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = building_size
	building_mesh.mesh = box_mesh

	var palette := [
		Color(0.46, 0.24, 0.18),
		Color(0.54, 0.39, 0.25),
		Color(0.24, 0.31, 0.42),
		Color(0.37, 0.39, 0.43),
		Color(0.28, 0.22, 0.32),
		Color(0.52, 0.48, 0.38)
	]

	var facade := StandardMaterial3D.new()
	facade.albedo_color = palette[randi() % palette.size()]
	facade.roughness = 0.72
	building_mesh.material_override = facade

	var building_collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = building_size
	building_collision.shape = box_shape

	building.add_child(building_mesh)
	building.add_child(building_collision)
	add_child(building)

	add_rooftop_cap(building, building_size)
	add_window_bands(building, building_size)

	if randf() > 0.62:
		add_rooftop_unit(building, building_size)

func add_rooftop_cap(building: StaticBody3D, building_size: Vector3):
	var cap := MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(building_size.x + 1.0, 0.65, building_size.z + 1.0)
	cap.mesh = cap_mesh
	cap.position = Vector3(0.0, building_size.y / 2.0 + 0.33, 0.0)
	var cap_material := StandardMaterial3D.new()
	cap_material.albedo_color = Color(0.08, 0.09, 0.12)
	cap_material.metallic = 0.35
	cap_material.roughness = 0.48
	cap.material_override = cap_material
	building.add_child(cap)

func add_window_bands(building: StaticBody3D, building_size: Vector3):
	var window_material := StandardMaterial3D.new()
	window_material.albedo_color = Color(0.08, 0.16, 0.25)
	window_material.metallic = 0.55
	window_material.roughness = 0.24
	window_material.emission_enabled = true
	window_material.emission = Color(0.12, 0.20, 0.28)
	window_material.emission_energy_multiplier = 0.48

	var band_count := clampi(int(building_size.y / 16.0), 2, 6)
	for band_index in range(band_count):
		var y_position := -building_size.y / 2.0 + 8.0 + band_index * ((building_size.y - 12.0) / float(band_count))

		var front_band := MeshInstance3D.new()
		var front_mesh := BoxMesh.new()
		front_mesh.size = Vector3(building_size.x * 0.74, 1.35, 0.12)
		front_band.mesh = front_mesh
		front_band.position = Vector3(0.0, y_position, -building_size.z / 2.0 - 0.07)
		front_band.material_override = window_material
		building.add_child(front_band)

		var side_band := MeshInstance3D.new()
		var side_mesh := BoxMesh.new()
		side_mesh.size = Vector3(0.12, 1.35, building_size.z * 0.74)
		side_band.mesh = side_mesh
		side_band.position = Vector3(building_size.x / 2.0 + 0.07, y_position, 0.0)
		side_band.material_override = window_material
		building.add_child(side_band)

func add_rooftop_unit(building: StaticBody3D, building_size: Vector3):
	var unit := MeshInstance3D.new()
	var unit_mesh := BoxMesh.new()
	unit_mesh.size = Vector3(3.8, 2.2, 3.8)
	unit.mesh = unit_mesh
	unit.position = Vector3(building_size.x * 0.18, building_size.y / 2.0 + 1.45, building_size.z * 0.16)
	var unit_material := StandardMaterial3D.new()
	unit_material.albedo_color = Color(0.12, 0.15, 0.18)
	unit_material.metallic = 0.58
	unit_material.roughness = 0.46
	unit.material_override = unit_material
	building.add_child(unit)

func create_crosshair():
	var canvas := CanvasLayer.new()
	canvas.name = "Interface"
	var help := Label.new()
	help.text = "WASD: move and steer | Space: jump/double jump, or climb while attached\nHold left mouse: attach and pan horizontally | Release left mouse: detach and lock camera perspective\nRight mouse: emergency release | R: reset"
	help.position = Vector2(14.0, 12.0)
	help.add_theme_font_size_override("font_size", 16)
	canvas.add_child(help)
	web_target_indicator = ColorRect.new()
	web_target_indicator.name = "WebTargetIndicator"
	web_target_indicator.size = Vector2(8.0, 8.0)
	web_target_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(web_target_indicator)
	add_child(canvas)

func reset_player():
	release_web()
	player.global_position = Vector3(0.0, 5.0, 0.0)
	player.velocity = Vector3.ZERO
