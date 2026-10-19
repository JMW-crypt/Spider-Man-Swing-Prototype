extends Node3D

const SwingTuningScript = preload("res://scripts/traversal/swing_tuning.gd")
const SwingSolverScript = preload("res://scripts/traversal/swing_solver.gd")
const LegacySpringSolverScript = preload("res://scripts/traversal/legacy_spring_solver.gd")
const TraversalMathScript = preload("res://scripts/traversal/traversal_math.gd")
const WallCrawlTuningScript = preload("res://scripts/traversal/wall_crawl_tuning.gd")
const WallCrawlControllerScript = preload("res://scripts/traversal/wall_crawl_controller.gd")
const WallCrawlMathScript = preload("res://scripts/traversal/wall_crawl_math.gd")
const REAR_WEB_SHOT_HALF_ANGLE_DEGREES := 60.0
const REAR_WEB_SHOT_VERTICAL_SLOPES := [0.25, 0.55, 0.9]

@export var swing_tuning: SwingTuningScript
@export var swing_solver: SwingSolverScript
@export var wall_crawl_tuning: WallCrawlTuningScript
@export var traversal_telemetry_enabled := false

enum TraversalState { GROUNDED, AIRBORNE, WALL_RUN, WALL_CRAWLING, WEB_ATTACHED }

var player: CharacterBody3D
# player.velocity is authoritative; visual animation is presentation-only.
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
var web_rear_shot_active := false
var web_anchor := Vector3.ZERO
var rope_length := 0.0
var web_target_available := false
var web_target_check_timer := 0.0
var preferred_web_anchor := Vector3.ZERO
var web_search_shape: SphereShape3D
var web_search_query: PhysicsShapeQueryParameters3D
var web_ray_query: PhysicsRayQueryParameters3D
var web_candidates: Array[Dictionary] = []
var jumps_remaining := 2
var camera_yaw: float = 0.0
var camera_follow_yaw: float = 0.0
var camera_orbit_offset: float = 0.0
var character_heading_yaw: float = 0.0
var camera_pitch: float = 0.0
var camera_bank: float = 0.0
var camera_position_initialized := false
var run_animation_phase: float = 0.0
var run_animation_weight: float = 0.0
var swing_pose_weight: float = 0.0
const CITY_EXTENT := 350
const BUILDING_SPACING := 48
var building_materials: Array[StandardMaterial3D] = []
var window_materials: Array[StandardMaterial3D] = []
var rooftop_cap_material: StandardMaterial3D
var wall_crawl_controller: WallCrawlControllerScript = WallCrawlControllerScript.new()
var wall_ray_query: PhysicsRayQueryParameters3D
var traversal_state: int = TraversalState.AIRBORNE
var previous_traversal_state: int = TraversalState.AIRBORNE
var last_transition_reason: String = "initialized"
var space_context_action: String = "none"
var wall_run_entry_eligible: bool = false
var wall_web_transition: String = "none"
var wall_detected: bool = false
var detected_wall_candidate: Dictionary = {}

var telemetry_label: Label
var telemetry_log_elapsed: float = 0.0
var telemetry_tick_index: int = 0
var telemetry_tick_steering_delta := Vector3.ZERO
var telemetry_tick_spring_delta := Vector3.ZERO
var telemetry_tick_correction_velocity_delta := Vector3.ZERO
var telemetry_tick_correction_position_delta := Vector3.ZERO
var telemetry_last_attach_impulse_delta := Vector3.ZERO
var telemetry_tick_climb_delta: float = 0.0
var telemetry_attach_velocity_before := Vector3.ZERO
var telemetry_attach_velocity_after := Vector3.ZERO
var telemetry_release_velocity := Vector3.ZERO
var telemetry_candidate_score: float = -1.0
var telemetry_radial_speed: float = 0.0
var telemetry_tangential_velocity := Vector3.ZERO
var telemetry_collision_count: int = 0
var telemetry_on_floor := false
var telemetry_on_wall := false
var telemetry_on_ceiling := false

func _ready():
	randomize()
	if swing_tuning == null:
		swing_tuning = SwingTuningScript.new()
	if swing_solver == null:
		swing_solver = LegacySpringSolverScript.new()
	if wall_crawl_tuning == null:
		wall_crawl_tuning = WallCrawlTuningScript.new()
	web_search_shape = SphereShape3D.new()
	web_search_shape.radius = swing_tuning.web_assist_radius
	web_search_query = PhysicsShapeQueryParameters3D.new()
	web_search_query.shape = web_search_shape
	web_search_query.collide_with_areas = false
	web_search_query.collide_with_bodies = true
	web_ray_query = PhysicsRayQueryParameters3D.new()
	web_ray_query.collide_with_areas = false
	web_ray_query.collide_with_bodies = true
	wall_ray_query = PhysicsRayQueryParameters3D.new()
	wall_ray_query.collide_with_areas = false
	wall_ray_query.collide_with_bodies = true
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
				attach_web(event.position, Input.is_action_pressed("rear_web_target"))
			else:
				release_web()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			release_web()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_orbit_offset += deg_to_rad(swing_tuning.camera_wheel_rotation_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_orbit_offset -= deg_to_rad(swing_tuning.camera_wheel_rotation_step)

	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.is_action_pressed("reset_player"):
			reset_player()
		elif event.is_action_pressed("traversal_telemetry"):
			traversal_telemetry_enabled = not traversal_telemetry_enabled
			if telemetry_label != null:
				telemetry_label.visible = traversal_telemetry_enabled

func _physics_process(delta):
	if player == null:
		return
	reset_traversal_tick_telemetry()
	wall_crawl_controller.advance_cooldown(delta)
	wall_detected = false
	detected_wall_candidate.clear()
	if Input.is_action_just_pressed("wall_traverse"):
		wall_run_entry_eligible = false
	update_web_target_indicator(delta)
	if (
		not web_active
		and not wall_crawl_controller.active
		and player.is_on_floor()
	):
		jumps_remaining = 2
	if web_active:
		var wall_candidate: Dictionary = {}
		if (
			wall_crawl_tuning.enabled
			and Input.is_action_just_pressed("wall_traverse")
			and not Input.is_action_pressed("ui_accept")
			and wall_crawl_controller.reacquisition_cooldown <= 0.0
		):
			wall_candidate = find_wall_candidate()
		if WallCrawlMathScript.can_enter_wall_traversal(
			wall_crawl_tuning.enabled,
			Input.is_action_just_pressed("wall_traverse"),
			wall_crawl_controller.reacquisition_cooldown,
			not wall_candidate.is_empty()
		):
			release_web(false)
			wall_web_transition = "web_to_wall"
			if enter_wall_traversal(
				wall_candidate,
				WallCrawlControllerScript.Mode.WALL_CRAWL
			):
				update_active_wall_traversal(delta, false)
			else:
				handle_player_movement(delta)
		else:
			handle_player_movement(delta)
			apply_web_physics(delta)
	elif wall_crawl_controller.active:
		if not update_active_wall_traversal(delta):
			handle_player_movement(delta)
	else:
		if not try_enter_wall_traversal():
			handle_player_movement(delta)
	player.move_and_slide()
	telemetry_collision_count = player.get_slide_collision_count()
	telemetry_on_floor = player.is_on_floor()
	telemetry_on_wall = player.is_on_wall()
	telemetry_on_ceiling = player.is_on_ceiling()
	if web_active:
		enforce_rope_constraint()
	update_traversal_state("physics_state_update")
	update_character_animation(delta)
	update_camera(delta)
	update_web_line()
	if player.global_position.y < -40.0:
		reset_player()
	update_traversal_telemetry(delta)

func update_traversal_state(reason: String):
	var wall_state: int = WallCrawlMathScript.STATE_AIRBORNE
	if wall_crawl_controller.mode == WallCrawlControllerScript.Mode.WALL_RUN:
		wall_state = WallCrawlMathScript.STATE_WALL_RUN
	elif wall_crawl_controller.mode == WallCrawlControllerScript.Mode.WALL_CRAWL:
		wall_state = WallCrawlMathScript.STATE_WALL_CRAWLING
	set_traversal_state(
		WallCrawlMathScript.resolve_traversal_state(
			web_active,
			wall_state,
			player.is_on_floor()
		),
		reason
	)

func set_traversal_state(next_state: int, reason: String):
	if traversal_state == next_state:
		return
	previous_traversal_state = traversal_state
	traversal_state = next_state
	last_transition_reason = reason

func wall_crawl_input_vector() -> Vector2:
	var crawl_input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_backward")
	)
	return WallCrawlMathScript.normalize_wall_input(crawl_input)

func enter_wall_traversal(candidate: Dictionary, mode: int) -> bool:
	if not wall_crawl_controller.enter(player, candidate, mode, wall_crawl_tuning):
		return false
	var next_state: int = (
		TraversalState.WALL_RUN
		if mode == WallCrawlControllerScript.Mode.WALL_RUN
		else TraversalState.WALL_CRAWLING
	)
	set_traversal_state(next_state, "wall_traversal_entered")
	return true

func try_enter_wall_traversal() -> bool:
	if (
		not wall_crawl_tuning.enabled
		or wall_crawl_controller.reacquisition_cooldown > 0.0
	):
		return false
	var candidate: Dictionary = find_wall_candidate()
	if wall_crawl_controller.should_ignore_detached_wall(candidate):
		return false
	if candidate.is_empty():
		return false
	if not WallCrawlMathScript.should_auto_acquire_wall(
		not player.is_on_floor(),
		player.is_on_wall(),
		player.velocity,
		candidate.get("normal", Vector3.ZERO),
		wall_crawl_tuning.minimum_wall_approach_speed
	):
		return false
	return enter_wall_traversal(candidate, WallCrawlControllerScript.Mode.WALL_CRAWL)

func update_active_wall_traversal(
	delta: float,
	allow_manual_detach: bool = true
) -> bool:
	if not wall_crawl_tuning.enabled:
		wall_crawl_controller.exit(player, wall_crawl_tuning, "disabled")
		set_traversal_state(TraversalState.AIRBORNE, "wall_traversal_disabled")
		return false
	var space_action: int = WallCrawlMathScript.resolve_space_action(
		false,
		true,
		player.is_on_floor(),
		jumps_remaining
	)
	if (
		Input.is_action_just_pressed("ui_accept")
		and space_action == WallCrawlMathScript.SPACE_ACTION_WALL_JUMP
	):
		wall_crawl_controller.exit(
			player,
			wall_crawl_tuning,
			"wall_jump",
			true,
			true
		)
		if not wall_crawl_tuning.preserve_double_jump_after_wall_jump and jumps_remaining > 0:
			jumps_remaining -= 1
		space_context_action = "wall_jump"
		set_traversal_state(TraversalState.AIRBORNE, "wall_jump")
		return true
	if allow_manual_detach and Input.is_action_just_pressed("wall_traverse"):
		wall_crawl_controller.exit(player, wall_crawl_tuning, "manual_detach")
		set_traversal_state(TraversalState.AIRBORNE, "wall_manual_detach")
		return false
	var crawl_input: Vector2 = wall_crawl_input_vector()
	var candidate: Dictionary = find_wall_candidate(wall_crawl_controller.wall_normal)
	if candidate.is_empty():
		wall_detected = false
		if wall_crawl_controller.update_without_contact(
			player,
			delta,
			wall_crawl_tuning,
			swing_tuning.gravity
		):
			return true
		wall_crawl_controller.exit(player, wall_crawl_tuning, "wall_lost")
		set_traversal_state(TraversalState.AIRBORNE, "wall_lost")
		return false
	if not wall_supports_step(crawl_input):
		wall_crawl_controller.exit(player, wall_crawl_tuning, "ledge")
		set_traversal_state(TraversalState.AIRBORNE, "ledge")
		return false
	if not wall_crawl_controller.update_motion(
		player,
		candidate,
		crawl_input,
		Input.is_action_pressed("wall_traverse"),
		delta,
		wall_crawl_tuning
	):
		wall_crawl_controller.exit(player, wall_crawl_tuning, "unsupported_corner")
		set_traversal_state(TraversalState.AIRBORNE, "unsupported_corner")
		return false
	if (
		wall_crawl_controller.mode == WallCrawlControllerScript.Mode.WALL_RUN
		and WallCrawlMathScript.wall_run_should_become_crawl(
			wall_crawl_controller.wall_run_hold_elapsed,
			wall_crawl_tuning.wall_run_to_crawl_hold_threshold
		)
	):
		wall_crawl_controller.run_to_crawl()
		set_traversal_state(TraversalState.WALL_CRAWLING, "wall_run_to_crawl")
	if (
		wall_crawl_controller.mode == WallCrawlControllerScript.Mode.WALL_RUN
		and WallCrawlMathScript.wall_run_duration_expired(
			wall_crawl_controller.wall_run_elapsed,
			wall_crawl_tuning.maximum_wall_run_duration
		)
	):
		wall_crawl_controller.exit(player, wall_crawl_tuning, "wall_run_timeout")
		set_traversal_state(TraversalState.AIRBORNE, "wall_run_timeout")
		return false
	return true

func wall_supports_step(crawl_input: Vector2) -> bool:
	if crawl_input.length_squared() <= 0.0001:
		return true
	var tangent_basis: Dictionary = WallCrawlMathScript.stable_wall_tangent_basis(
		wall_crawl_controller.wall_normal
	)
	var step_direction: Vector3 = (
		tangent_basis["right"] * crawl_input.x
		+ tangent_basis["up"] * crawl_input.y
	).normalized()
	var probe_origin: Vector3 = (
		player.global_position
		+ step_direction * wall_crawl_tuning.ledge_probe_distance
	)
	wall_ray_query.from = probe_origin
	wall_ray_query.to = (
		probe_origin
		- wall_crawl_controller.wall_normal * wall_crawl_tuning.wall_detection_distance
	)
	wall_ray_query.collision_mask = player.collision_mask & wall_crawl_tuning.wall_collision_mask
	wall_ray_query.exclude = [player.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(wall_ray_query)
	return is_valid_wall_hit(hit)

func find_wall_candidate(preferred_normal: Vector3 = Vector3.ZERO) -> Dictionary:
	if not wall_crawl_tuning.enabled or player == null:
		wall_detected = false
		return {}
	var base_origin: Vector3 = player.global_position
	var horizontal_reference := Vector3.FORWARD
	if camera != null:
		horizontal_reference = -camera.global_transform.basis.z
		horizontal_reference.y = 0.0
	if horizontal_reference.length_squared() <= 0.0001:
		horizontal_reference = Vector3.FORWARD
	horizontal_reference = horizontal_reference.normalized()
	var reference_right := Vector3.UP.cross(horizontal_reference).normalized()
	var collision_mask: int = player.collision_mask & wall_crawl_tuning.wall_collision_mask
	if collision_mask == 0:
		wall_detected = false
		return {}
	var ray_distance: float = maxf(
		wall_crawl_tuning.wall_detection_distance,
		wall_crawl_tuning.corner_probe_distance
	)
	var best_candidate: Dictionary = {}
	var best_score: float = -INF
	var vertical_offsets: Array[float] = [0.0]
	if preferred_normal.length_squared() <= 0.0001:
		vertical_offsets = [
			-wall_crawl_tuning.wall_probe_radius,
			0.0,
			wall_crawl_tuning.wall_probe_radius
		]
	for vertical_offset in vertical_offsets:
		var ray_origin: Vector3 = base_origin + Vector3.UP * vertical_offset
		for ray_index in range(8):
			var angle: float = TAU * float(ray_index) / 8.0
			var ray_direction: Vector3 = (
				horizontal_reference * cos(angle)
				+ reference_right * sin(angle)
			).normalized()
			wall_ray_query.from = ray_origin
			wall_ray_query.to = ray_origin + ray_direction * ray_distance
			wall_ray_query.collision_mask = collision_mask
			wall_ray_query.exclude = [player.get_rid()]
			var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(wall_ray_query)
			if hit.is_empty():
				continue
			var normal: Vector3 = hit.get("normal", Vector3.ZERO)
			if not is_valid_wall_hit(hit):
				continue
			var collider: StaticBody3D = hit.get("collider")
			var hit_position: Vector3 = hit.get("position", ray_origin)
			var distance: float = absf((base_origin - hit_position).dot(normal.normalized()))
			if (
				distance > wall_crawl_tuning.wall_detection_distance
				or not WallCrawlMathScript.is_safe_wall_distance(
					distance,
					wall_crawl_tuning.wall_contact_distance,
					wall_crawl_tuning.penetration_rejection_threshold
				)
			):
				continue
			var score: float = -distance
			if preferred_normal.length_squared() > 0.0001:
				score += preferred_normal.normalized().dot(normal.normalized()) * ray_distance
			if score > best_score:
				best_score = score
				best_candidate = {
					"normal": normal,
					"distance": distance,
					"collider_id": collider.get_instance_id(),
					"collision_layer": collider.collision_layer
				}
	wall_detected = not best_candidate.is_empty()
	detected_wall_candidate = best_candidate
	return best_candidate

func is_valid_wall_hit(hit: Dictionary) -> bool:
	var collider: Object = hit.get("collider")
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	return (
		collider is StaticBody3D
		and collider.is_in_group("traversal_walls")
		and WallCrawlMathScript.is_valid_wall_normal(
			normal,
			wall_crawl_tuning.minimum_wall_steepness_degrees,
			wall_crawl_tuning.maximum_wall_normal_vertical_component
		)
	)


func reset_traversal_tick_telemetry():
	telemetry_tick_index += 1
	telemetry_tick_steering_delta = Vector3.ZERO
	telemetry_tick_spring_delta = Vector3.ZERO
	telemetry_tick_correction_velocity_delta = Vector3.ZERO
	telemetry_tick_correction_position_delta = Vector3.ZERO
	telemetry_tick_climb_delta = 0.0
	telemetry_collision_count = 0
	telemetry_on_floor = false
	telemetry_on_wall = false
	telemetry_on_ceiling = false

func update_traversal_telemetry(delta: float):
	if not traversal_telemetry_enabled:
		return

	# Telemetry observes authoritative controller state and never feeds traversal.
	var anchor_distance: float = 0.0
	var rope_error: float = 0.0
	telemetry_radial_speed = 0.0
	telemetry_tangential_velocity = Vector3.ZERO
	if web_active:
		var anchor_to_origin: Vector3 = get_web_origin() - web_anchor
		anchor_distance = anchor_to_origin.length()
		rope_error = TraversalMathScript.rope_error(anchor_distance, rope_length)
		var components: Dictionary = TraversalMathScript.decompose_radial_tangential(
			player.velocity,
			anchor_to_origin
		)
		telemetry_radial_speed = components["radial_speed"]
		telemetry_tangential_velocity = components["tangential_velocity"]

	var wall_input_snapshot: Vector2 = wall_crawl_input_vector()
	var snapshot := {
		"tick": telemetry_tick_index,
		"velocity": vector_to_array(player.velocity),
		"speed": player.velocity.length(),
		"attached": web_active,
		"rear_web_shot": web_rear_shot_active,
		"anchor": vector_to_array(web_anchor) if web_active else [],
		"candidate_score": telemetry_candidate_score,
		"rope_length": rope_length if web_active else 0.0,
		"player_anchor_distance": anchor_distance,
		"rope_error": rope_error,
		"radial_speed": telemetry_radial_speed,
		"tangential_velocity": vector_to_array(telemetry_tangential_velocity),
		"attach_velocity_before": vector_to_array(telemetry_attach_velocity_before),
		"attach_velocity_after": vector_to_array(telemetry_attach_velocity_after),
		"release_velocity": vector_to_array(telemetry_release_velocity),
		"attach_impulse_delta": vector_to_array(telemetry_last_attach_impulse_delta),
		"steering_delta": vector_to_array(telemetry_tick_steering_delta),
		"climb_rope_delta": telemetry_tick_climb_delta,
		"spring_velocity_delta": vector_to_array(telemetry_tick_spring_delta),
		"correction_velocity_delta": vector_to_array(
			telemetry_tick_correction_velocity_delta
		),
		"correction_position_delta": vector_to_array(
			telemetry_tick_correction_position_delta
		),
		"collision_count": telemetry_collision_count,
		"collision_state": {
			"on_floor": telemetry_on_floor,
			"on_wall": telemetry_on_wall,
			"on_ceiling": telemetry_on_ceiling
		},
		"traversal_state": get_traversal_state_name(),
		"previous_traversal_state": get_traversal_state_name(previous_traversal_state),
		"transition_reason": last_transition_reason,
		"space_context_action": space_context_action,
		"space_input": {
			"pressed": Input.is_action_just_pressed("ui_accept"),
			"held": Input.is_action_pressed("ui_accept"),
			"released": Input.is_action_just_released("ui_accept")
		},
		"wall_input": {
			"pressed": Input.is_action_just_pressed("wall_traverse"),
			"held": Input.is_action_pressed("wall_traverse"),
			"released": Input.is_action_just_released("wall_traverse"),
			"vector": [wall_input_snapshot.x, wall_input_snapshot.y]
		},
		"input_actions": {
			"forward": "move_forward",
			"backward": "move_backward",
			"left": "move_left",
			"right": "move_right",
			"wall": "wall_traverse",
			"jump": "ui_accept"
		},
		"wall_crawl_enabled": wall_crawl_tuning.enabled,
		"wall_crawl_input": wall_crawl_controller.active,
		"wall_detected": wall_detected,
		"wall_eligible": wall_detected,
		"detected_wall_collider_id": int(detected_wall_candidate.get("collider_id", 0)),
		"detected_wall_normal": vector_to_array(detected_wall_candidate.get("normal", Vector3.ZERO)),
		"detected_wall_distance": float(detected_wall_candidate.get("distance", 0.0)),
		"wall_eligibility_result": "eligible" if wall_detected else "no_valid_wall",
		"wall_run_entry_eligible": wall_run_entry_eligible,
		"wall_web_transition": wall_web_transition,
		"wall_mode": get_wall_mode_name(),
		"wall_collider_id": wall_crawl_controller.wall_collider_id if wall_crawl_controller.active else 0,
		"wall_collision_layer": wall_crawl_controller.wall_collision_layer if wall_crawl_controller.active else int(detected_wall_candidate.get("collision_layer", 0)),
		"wall_normal": vector_to_array(wall_crawl_controller.wall_normal) if wall_crawl_controller.active else [],
		"wall_distance": wall_crawl_controller.wall_distance if wall_crawl_controller.active else 0.0,
		"wall_contact_error": wall_crawl_controller.contact_error if wall_crawl_controller.active else 0.0,
		"wall_tangent_velocity": vector_to_array(wall_crawl_controller.tangent_velocity),
		"wall_adhesion_correction": vector_to_array(wall_crawl_controller.adhesion_correction),
		"desired_adhesion_speed": wall_crawl_controller.desired_correction_velocity,
		"applied_adhesion_speed": wall_crawl_controller.applied_correction_velocity,
		"crawl_speed": wall_crawl_controller.tangent_velocity.length() if wall_crawl_controller.mode == WallCrawlControllerScript.Mode.WALL_CRAWL else 0.0,
		"wall_run_entry_speed": wall_crawl_controller.wall_run_entry_speed,
		"wall_run_elapsed": wall_crawl_controller.wall_run_elapsed,
		"wall_run_remaining": maxf(0.0, wall_crawl_tuning.maximum_wall_run_duration - wall_crawl_controller.wall_run_elapsed) if wall_crawl_controller.mode == WallCrawlControllerScript.Mode.WALL_RUN else 0.0,
		"wall_run_velocity": vector_to_array(wall_crawl_controller.tangent_velocity) if wall_crawl_controller.mode == WallCrawlControllerScript.Mode.WALL_RUN else [],
		"wall_run_downward_contribution": vector_to_array(wall_crawl_controller.wall_run_downward_velocity),
		"wall_jump_velocity": vector_to_array(wall_crawl_controller.last_wall_jump_velocity),
		"wall_detach_reason": wall_crawl_controller.last_detach_reason,
		"wall_lost_elapsed": wall_crawl_controller.wall_lost_elapsed,
		"wall_reacquisition_cooldown": wall_crawl_controller.reacquisition_cooldown
	}
	if telemetry_label != null:
		telemetry_label.text = JSON.stringify(snapshot, "  ")
	telemetry_log_elapsed += delta
	if telemetry_log_elapsed >= 1.0:
		telemetry_log_elapsed = fmod(telemetry_log_elapsed, 1.0)
		print("TRAVERSAL_TELEMETRY " + JSON.stringify(snapshot))

func vector_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func get_traversal_state_name(state: int = -1) -> String:
	if state < 0:
		state = traversal_state
	match state:
		TraversalState.GROUNDED:
			return "grounded"
		TraversalState.WALL_RUN:
			return "wall_run"
		TraversalState.WALL_CRAWLING:
			return "wall_crawling"
		TraversalState.WEB_ATTACHED:
			return "web_attached"
		_:
			return "airborne"

func get_wall_mode_name() -> String:
	match wall_crawl_controller.mode:
		WallCrawlControllerScript.Mode.WALL_RUN:
			return "wall_run"
		WallCrawlControllerScript.Mode.WALL_CRAWL:
			return "wall_crawl"
		_:
			return "none"

func handle_player_movement(delta: float, allow_jump: bool = true):
	if web_active:
		player.velocity.y -= swing_tuning.gravity * delta
		if (
			Input.is_action_pressed("ui_accept")
			and WallCrawlMathScript.resolve_space_action(
				true,
				false,
				player.is_on_floor(),
				jumps_remaining
			) == WallCrawlMathScript.SPACE_ACTION_WEB_CLIMB
		):
			space_context_action = "web_climb"
		return

	var movement_input: Vector2 = wall_crawl_input_vector()
	var camera_forward := Vector3(-sin(camera_yaw), 0.0, -cos(camera_yaw))
	var camera_right := Vector3(cos(camera_yaw), 0.0, -sin(camera_yaw))
	var desired_direction: Vector3 = (
		camera_right * movement_input.x
		+ camera_forward * movement_input.y
	)
	if desired_direction.length_squared() > 0.0001:
		desired_direction = desired_direction.normalized()
		if movement_input.y > 0.01:
			character_heading_yaw = atan2(-desired_direction.x, -desired_direction.z)

	if player.is_on_floor():
		var target_velocity: Vector3 = desired_direction * swing_tuning.ground_speed
		player.velocity.x = move_toward(player.velocity.x, target_velocity.x, swing_tuning.ground_acceleration * delta)
		player.velocity.z = move_toward(player.velocity.z, target_velocity.z, swing_tuning.ground_acceleration * delta)
	else:
		var target_air_velocity: Vector3 = desired_direction * swing_tuning.air_speed
		player.velocity.x = move_toward(player.velocity.x, target_air_velocity.x, swing_tuning.air_acceleration * delta)
		player.velocity.z = move_toward(player.velocity.z, target_air_velocity.z, swing_tuning.air_acceleration * delta)
		player.velocity.y -= swing_tuning.gravity * delta
	var space_action: int = WallCrawlMathScript.resolve_space_action(
		false,
		false,
		player.is_on_floor(),
		jumps_remaining
	)
	if (
		allow_jump
		and Input.is_action_just_pressed("ui_accept")
		and (
			space_action == WallCrawlMathScript.SPACE_ACTION_JUMP
			or space_action == WallCrawlMathScript.SPACE_ACTION_DOUBLE_JUMP
		)
	):
		space_context_action = (
			"jump" if player.is_on_floor() else "double_jump"
		)
		player.velocity.y = swing_tuning.jump_force
		jumps_remaining -= 1

func attach_web(screen_position: Vector2, rear_shot: bool = false):
	if camera == null or player == null:
		return
	var result := find_web_target(screen_position, rear_shot)
	if result.is_empty():
		return
	var overrode_wall_traversal: bool = wall_crawl_controller.active
	if wall_crawl_controller.active:
		wall_crawl_controller.exit(
			player,
			wall_crawl_tuning,
			"web_attached",
			false,
			false
		)
		wall_web_transition = "wall_to_web"
	var hit_position: Vector3 = result["position"]
	telemetry_attach_velocity_before = player.velocity
	web_anchor = hit_position
	web_rear_shot_active = rear_shot
	rope_length = maxf(get_web_origin().distance_to(web_anchor), swing_tuning.min_rope_length)
	web_active = true
	var direction_to_anchor: Vector3 = (
		web_anchor - get_web_origin()
	).normalized()
	player.velocity += (
		direction_to_anchor
		* swing_tuning.web_attach_yank_impulse
	)
	telemetry_attach_velocity_after = player.velocity
	telemetry_last_attach_impulse_delta = player.velocity - telemetry_attach_velocity_before
	telemetry_candidate_score = float(result.get("score", -1.0))
	set_traversal_state(
		TraversalState.WEB_ATTACHED,
		"web_attach_overrode_wall" if overrode_wall_traversal else "web_attached"
	)

func find_web_target(screen_position: Vector2, rear_shot: bool = false) -> Dictionary:
	var origin := get_web_origin()
	if rear_shot:
		return find_rear_web_target(origin)
	web_candidates.clear()

	var direct_hit := raycast_web_target(screen_position)
	if not direct_hit.is_empty():
		add_web_candidate(direct_hit, true, origin)

	var half_radius := swing_tuning.web_screen_sample_radius * 0.5
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
		if web_candidates.size() >= swing_tuning.web_candidate_limit:
			break
		var sampled_hit := raycast_web_target(screen_position + offset)
		if not sampled_hit.is_empty():
			add_web_candidate(sampled_hit, false, origin)

	web_search_query.transform = Transform3D(Basis.IDENTITY, origin)
	web_search_query.exclude = [player.get_rid()]
	var nearby_hits := get_world_3d().direct_space_state.intersect_shape(
		web_search_query,
		swing_tuning.web_candidate_limit
	)
	for nearby_hit in nearby_hits:
		if web_candidates.size() >= swing_tuning.web_candidate_limit:
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
		best_assisted_score == -INF
		or best_direct_score >= best_assisted_score - swing_tuning.direct_aim_score_tolerance
	):
		best_direct_candidate["score"] = best_direct_score
		preferred_web_anchor = best_direct_candidate["position"]
		telemetry_candidate_score = best_direct_score
		return best_direct_candidate
	if not best_candidate.is_empty():
		best_candidate["score"] = best_assisted_score
		preferred_web_anchor = best_candidate["position"]
		telemetry_candidate_score = best_assisted_score
		return best_candidate
	if not best_direct_candidate.is_empty():
		best_direct_candidate["score"] = best_direct_score
		preferred_web_anchor = best_direct_candidate["position"]
		telemetry_candidate_score = best_direct_score
		return best_direct_candidate
	preferred_web_anchor = Vector3.ZERO
	telemetry_candidate_score = -1.0
	return {}

func find_rear_web_target(origin: Vector3) -> Dictionary:
	web_candidates.clear()
	var rear_direction: Vector3 = get_rear_web_direction()
	if rear_direction.length_squared() <= 0.0001:
		return {}
	var side_direction: Vector3 = Vector3.UP.cross(rear_direction).normalized()
	for ray_index in range(7):
		if web_candidates.size() >= swing_tuning.web_candidate_limit:
			break
		var yaw_ratio: float = float(ray_index) / 6.0
		var yaw_degrees: float = lerpf(
			-REAR_WEB_SHOT_HALF_ANGLE_DEGREES,
			REAR_WEB_SHOT_HALF_ANGLE_DEGREES,
			yaw_ratio
		)
		var yaw_radians: float = deg_to_rad(yaw_degrees)
		var horizontal_direction: Vector3 = (
			rear_direction * cos(yaw_radians)
			+ side_direction * sin(yaw_radians)
		).normalized()
		for vertical_slope in REAR_WEB_SHOT_VERTICAL_SLOPES:
			if web_candidates.size() >= swing_tuning.web_candidate_limit:
				break
			var ray_direction: Vector3 = (
				horizontal_direction + Vector3.UP * vertical_slope
			).normalized()
			web_ray_query.from = origin
			web_ray_query.to = origin + ray_direction * swing_tuning.web_range
			web_ray_query.exclude = [player.get_rid()]
			var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(web_ray_query)
			add_rear_web_candidate(hit, origin, rear_direction)

	var best_candidate: Dictionary = {}
	var best_score: float = -INF
	for candidate in web_candidates:
		var anchor: Vector3 = candidate["position"]
		var body: StaticBody3D = candidate["body"]
		if not is_web_anchor_visible(origin, anchor, body):
			continue
		var score: float = score_rear_web_candidate(anchor, origin, rear_direction)
		if score > best_score:
			best_score = score
			best_candidate = candidate
	if best_candidate.is_empty():
		preferred_web_anchor = Vector3.ZERO
		telemetry_candidate_score = -1.0
		return {}
	best_candidate["score"] = best_score
	preferred_web_anchor = best_candidate["position"]
	telemetry_candidate_score = best_score
	return best_candidate

func get_rear_web_direction() -> Vector3:
	var horizontal_velocity := Vector3(player.velocity.x, 0.0, player.velocity.z)
	if horizontal_velocity.length_squared() > 4.0:
		return -horizontal_velocity.normalized()
	if hero_root != null:
		var character_rear: Vector3 = hero_root.global_transform.basis.z
		character_rear.y = 0.0
		if character_rear.length_squared() > 0.0001:
			return character_rear.normalized()
	return Vector3(sin(character_heading_yaw), 0.0, cos(character_heading_yaw)).normalized()

func add_rear_web_candidate(hit: Dictionary, origin: Vector3, rear_direction: Vector3):
	if hit.is_empty() or web_candidates.size() >= swing_tuning.web_candidate_limit:
		return
	var collider: Object = hit.get("collider")
	if not (collider is StaticBody3D and collider.is_in_group("traversal_walls")):
		return
	var anchor: Vector3 = hit.get("position", origin)
	var to_anchor: Vector3 = anchor - origin
	var horizontal_to_anchor := Vector3(to_anchor.x, 0.0, to_anchor.z)
	if (
		anchor.y < 0.0
		or anchor.y - player.global_position.y < swing_tuning.web_min_anchor_height
		or to_anchor.length() > swing_tuning.web_range
		or horizontal_to_anchor.length_squared() <= 0.0001
		or horizontal_to_anchor.normalized().dot(rear_direction) < 0.25
	):
		return
	for existing in web_candidates:
		var existing_position: Vector3 = existing["position"]
		if existing_position.distance_squared_to(anchor) < 1.0:
			return
	web_candidates.append({
		"position": anchor,
		"body": collider,
		"direct": false
	})

func score_rear_web_candidate(anchor: Vector3, origin: Vector3, rear_direction: Vector3) -> float:
	var to_anchor: Vector3 = anchor - origin
	var distance: float = to_anchor.length()
	var horizontal_direction := Vector3(to_anchor.x, 0.0, to_anchor.z).normalized()
	var alignment: float = clampf(
		(horizontal_direction.dot(rear_direction) - 0.25) / 0.75,
		0.0,
		1.0
	)
	var height_delta: float = anchor.y - player.global_position.y
	var preferred_height: float = swing_tuning.web_assist_radius * 0.45
	var height_score: float = clampf(
		1.0 - absf(height_delta - preferred_height) / preferred_height,
		0.0,
		1.0
	)
	var preferred_distance: float = swing_tuning.web_assist_radius * 0.58
	var distance_score: float = clampf(
		1.0 - absf(distance - preferred_distance) / preferred_distance,
		0.0,
		1.0
	)
	return (
		alignment * 0.55
		+ height_score * swing_tuning.score_height_weight
		+ distance_score * swing_tuning.score_distance_weight
	)

func is_valid_web_body(collider: Object) -> bool:
	return collider is StaticBody3D and collider.name != "CityGround"

func add_web_candidate(hit: Dictionary, direct_aim: bool, origin: Vector3):
	if web_candidates.size() >= swing_tuning.web_candidate_limit:
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
		if web_candidates.size() >= swing_tuning.web_candidate_limit:
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
			if web_candidates.size() >= swing_tuning.web_candidate_limit:
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
		and height_above_player >= swing_tuning.web_min_anchor_height
		and distance <= swing_tuning.web_assist_radius
		and distance <= swing_tuning.web_range
	)

func is_web_anchor_visible(origin: Vector3, anchor: Vector3, target: StaticBody3D) -> bool:
	var to_anchor: Vector3 = anchor - origin
	var distance: float = to_anchor.length()
	if distance <= swing_tuning.web_visibility_margin:
		return false
	var ray_end: Vector3 = anchor - to_anchor / distance * swing_tuning.web_visibility_margin
	web_ray_query.from = origin
	web_ray_query.to = ray_end
	web_ray_query.exclude = [player.get_rid()]
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(web_ray_query)
	if result.is_empty():
		return true
	return (
		result.get("collider") == target
		and Vector3(result["position"]).distance_to(anchor)
			<= swing_tuning.web_visibility_margin * 2.0
	)

func score_web_candidate(anchor: Vector3, origin: Vector3) -> float:
	var to_anchor: Vector3 = anchor - origin
	var distance: float = to_anchor.length()
	var direction: Vector3 = to_anchor / maxf(distance, 0.001)
	var height_delta: float = anchor.y - player.global_position.y
	var preferred_height: float = swing_tuning.web_assist_radius * 0.45
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

	var preferred_distance: float = swing_tuning.web_assist_radius * 0.58
	var distance_score: float = clampf(
		1.0 - absf(distance - preferred_distance) / preferred_distance,
		0.0,
		1.0
	)
	return (
		height_score * swing_tuning.score_height_weight
		+ forward_score * swing_tuning.score_forward_weight
		+ momentum_score * swing_tuning.score_momentum_weight
		+ distance_score * swing_tuning.score_distance_weight
	)

func raycast_web_target(screen_position: Vector2) -> Dictionary:
	var ray_start := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var ray_end := ray_start + ray_direction * swing_tuning.web_range
	web_ray_query.from = ray_start
	web_ray_query.to = ray_end
	web_ray_query.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(web_ray_query)

func update_web_target_indicator(delta: float):
	if web_target_indicator == null:
		return
	web_target_check_timer -= delta
	if not web_active and web_target_check_timer <= 0.0:
		web_target_check_timer = swing_tuning.web_target_refresh_interval
		var target := find_web_target(
			get_viewport().get_mouse_position(),
			Input.is_action_pressed("rear_web_target")
		)
		web_target_available = not target.is_empty()

	web_target_indicator.position = get_viewport().get_mouse_position() + Vector2(14.0, -4.0)
	if web_active:
		web_target_indicator.color = Color(1.0, 0.72, 0.18, 1.0)
	elif web_target_available:
		web_target_indicator.color = (
			Color(1.0, 0.48, 0.14, 1.0)
			if Input.is_action_pressed("rear_web_target")
			else Color(0.15, 0.95, 0.78, 1.0)
		)
	else:
		web_target_indicator.color = Color(0.38, 0.42, 0.48, 0.75)

func release_web(update_traversal_state: bool = true):
	if web_active:
		telemetry_release_velocity = player.velocity
		jumps_remaining = 2
	web_active = false
	web_rear_shot_active = false
	if update_traversal_state and traversal_state == TraversalState.WEB_ATTACHED:
		set_traversal_state(TraversalState.AIRBORNE, "web_released")
	if web_mesh != null:
		web_mesh.clear_surfaces()

func apply_web_physics(delta: float):
	var anchor_to_player: Vector3 = get_web_origin() - web_anchor
	var spring_delta := swing_solver.calculate_spring_velocity_delta(
		player.velocity,
		anchor_to_player,
		rope_length,
		delta,
		swing_tuning
	)
	player.velocity += spring_delta
	telemetry_tick_spring_delta = spring_delta
	apply_omnidirectional_swing_control(delta)
	if Input.is_action_pressed("ui_accept"):
		var previous_rope_length: float = rope_length
		rope_length = maxf(
			swing_tuning.min_rope_length,
			rope_length - swing_tuning.web_climb_speed * delta
		)
		telemetry_tick_climb_delta = rope_length - previous_rope_length
	if player.velocity.length() > swing_tuning.max_swing_speed:
		player.velocity = player.velocity.normalized() * swing_tuning.max_swing_speed

func apply_omnidirectional_swing_control(delta: float):
	var input_vector: Vector2 = wall_crawl_input_vector()
	if input_vector == Vector2.ZERO:
		return
	var side_input: float = input_vector.x
	var forward_input: float = input_vector.y

	var forward: Vector3 = project_onto_swing_plane(-camera.global_transform.basis.z)
	var right: Vector3 = project_onto_swing_plane(camera.global_transform.basis.x)
	var forward_force: float = swing_tuning.swing_forward_force if forward_input >= 0.0 else swing_tuning.swing_reverse_force
	var velocity_before: Vector3 = player.velocity
	player.velocity += (
		forward * forward_input * forward_force
		+ right * side_input * swing_tuning.swing_side_force
	) * delta
	telemetry_tick_steering_delta = player.velocity - velocity_before

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
	var velocity_before: Vector3 = player.velocity
	var position_before: Vector3 = player.global_position
	var rope_origin: Vector3 = get_web_origin()
	swing_solver.apply_post_move_constraint(
		player,
		web_anchor,
		rope_origin,
		rope_length,
		swing_tuning
	)
	telemetry_tick_correction_velocity_delta += player.velocity - velocity_before
	telemetry_tick_correction_position_delta += player.global_position - position_before

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
	var wall_running: bool = (
		wall_crawl_controller.mode == WallCrawlControllerScript.Mode.WALL_RUN
	)
	var wall_crawling: bool = (
		wall_crawl_controller.mode == WallCrawlControllerScript.Mode.WALL_CRAWL
	)
	if wall_running:
		target_run_weight = clampf(
			wall_crawl_controller.tangent_velocity.length()
			/ maxf(wall_crawl_tuning.maximum_wall_run_speed, 0.01),
			0.0,
			1.0
		)
		run_animation_phase += delta * wall_crawl_controller.tangent_velocity.length() * 1.2
	elif wall_crawling:
		var crawl_speed: float = wall_crawl_controller.tangent_velocity.length()
		if crawl_speed > 0.15:
			run_animation_phase += delta * crawl_speed * 1.2
	elif player.is_on_floor() and not web_active:
		target_run_weight = clampf(horizontal_speed / swing_tuning.ground_speed, 0.0, 1.0)
	var blend := 1.0 - exp(-8.0 * delta)
	var wall_pose_weight: float = 1.0 - exp(-wall_crawl_tuning.orientation_smoothing * delta)
	run_animation_weight = lerpf(run_animation_weight, target_run_weight, blend)
	swing_pose_weight = lerpf(swing_pose_weight, 1.0 if web_active else 0.0, blend)
	var target_visual_offset := Vector3.ZERO
	if wall_crawl_controller.active:
		target_visual_offset = player.global_transform.basis.inverse() * (
			-wall_crawl_controller.wall_normal * 0.12
		)
	hero_root.position = hero_root.position.lerp(
		target_visual_offset,
		wall_pose_weight if wall_crawl_controller.active else blend
	)

	if target_run_weight > 0.01:
		run_animation_phase += delta * lerpf(4.0, 10.0, target_run_weight)

	var facing_yaw := character_heading_yaw
	if wall_crawl_controller.active:
		facing_yaw = atan2(
			wall_crawl_controller.wall_normal.x,
			wall_crawl_controller.wall_normal.z
		)
	elif web_active and horizontal_speed > 0.5:
		facing_yaw = atan2(-horizontal_velocity.x, -horizontal_velocity.z)
	hero_root.rotation.y = lerp_angle(
		hero_root.rotation.y,
		facing_yaw,
		wall_pose_weight if wall_crawl_controller.active else blend
	)

	var local_velocity := hero_root.global_transform.basis.inverse() * player.velocity
	var forward_speed := clampf(-local_velocity.z / swing_tuning.air_speed, -1.0, 1.0)
	var side_speed := clampf(local_velocity.x / swing_tuning.air_speed, -1.0, 1.0)
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
	if wall_running:
		var local_run_velocity: Vector3 = (
			hero_root.global_transform.basis.inverse()
			* wall_crawl_controller.tangent_velocity
		)
		upper_body.rotation.x = lerp_angle(
			upper_body.rotation.x,
			-0.12,
			wall_pose_weight
		)
		upper_body.rotation.z = lerp_angle(
			upper_body.rotation.z,
			clampf(local_run_velocity.x / maxf(wall_crawl_tuning.maximum_wall_run_speed, 0.01), -1.0, 1.0) * 0.16,
			wall_pose_weight
		)

	var crawl_stride: float = sin(run_animation_phase) * clampf(
		wall_crawl_controller.tangent_velocity.length()
			/ maxf(
				maxf(
					wall_crawl_tuning.maximum_vertical_crawl_speed,
					wall_crawl_tuning.maximum_lateral_crawl_speed
				),
				0.01
			),
		0.0,
		1.0
	)
	var stride := sin(run_animation_phase) * run_animation_weight
	var trail := clampf(
		player.velocity.length() / swing_tuning.max_swing_speed,
		0.0,
		1.0
	) * swing_pose_weight
	var left_leg_target: float = stride * 0.65 - trail * 0.55
	var right_leg_target: float = -stride * 0.65 - trail * 0.55
	var left_arm_target: float = -stride * 0.5 + trail * 0.18
	var right_arm_target: float = 0.0
	if wall_crawling:
		left_leg_target = -0.20 + crawl_stride * 0.38
		right_leg_target = -0.20 - crawl_stride * 0.38
		left_arm_target = 0.68 - crawl_stride * 0.35
		right_arm_target = 0.68 + crawl_stride * 0.35
	left_leg_pivot.rotation.x = lerpf(
		left_leg_pivot.rotation.x,
		left_leg_target,
		wall_pose_weight if wall_crawl_controller.active else blend
	)
	right_leg_pivot.rotation.x = lerpf(
		right_leg_pivot.rotation.x,
		right_leg_target,
		wall_pose_weight if wall_crawl_controller.active else blend
	)
	left_arm_pivot.rotation.x = lerpf(
		left_arm_pivot.rotation.x,
		left_arm_target,
		wall_pose_weight if wall_crawl_controller.active else blend
	)

	var run_arm_rotation := Quaternion(Vector3.RIGHT, stride * 0.5)
	var target_right_arm_rotation := run_arm_rotation
	if wall_crawling:
		target_right_arm_rotation = Quaternion(
			Vector3.RIGHT,
			right_arm_target
		)
	elif web_active:
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
		wall_pose_weight if wall_crawl_controller.active else blend
	)

func update_camera(delta: float):
	if player == null or camera == null:
		return
	camera_pitch = swing_tuning.default_camera_pitch
	var previous_follow_yaw: float = camera_follow_yaw
	camera_follow_yaw = character_heading_yaw
	if wall_crawl_controller.active:
		camera_follow_yaw = atan2(
			wall_crawl_controller.wall_normal.x,
			wall_crawl_controller.wall_normal.z
		)
	elif web_active:
		var horizontal_velocity := Vector2(player.velocity.x, player.velocity.z)
		if horizontal_velocity.length() > 0.5:
			camera_follow_yaw = atan2(-horizontal_velocity.x, -horizontal_velocity.y)
	var follow_turn_rate: float = 0.0
	if camera_position_initialized and delta > 0.0001:
		follow_turn_rate = wrapf(
			camera_follow_yaw - previous_follow_yaw,
			-PI,
			PI
		) / delta

	var camera_right := Vector3(cos(camera_follow_yaw), 0.0, -sin(camera_follow_yaw))
	var swing_bank: float = 0.0
	if web_active:
		swing_bank = (
			player.velocity.dot(camera_right)
			/ maxf(swing_tuning.max_swing_speed, 0.01)
			* deg_to_rad(swing_tuning.camera_bank_max_degrees)
			* swing_tuning.camera_bank_swing_weight
		)
	var maximum_bank: float = deg_to_rad(swing_tuning.camera_bank_max_degrees)
	var target_bank: float = clampf(
		-follow_turn_rate * swing_tuning.camera_bank_turn_rate_scale + swing_bank,
		-maximum_bank,
		maximum_bank
	)
	if wall_crawl_controller.active:
		target_bank *= (
			0.32
			if wall_crawl_controller.mode == WallCrawlControllerScript.Mode.WALL_RUN
			else 0.2
		)
	var bank_blend: float = 1.0 - exp(-swing_tuning.camera_bank_smoothing * delta)
	camera_bank = lerpf(camera_bank, target_bank, bank_blend)

	var target_camera_yaw := camera_follow_yaw + camera_orbit_offset
	var yaw_blend := 1.0 - exp(-swing_tuning.camera_yaw_follow_smoothing * delta)
	camera_yaw = lerp_angle(camera_yaw, target_camera_yaw, yaw_blend)

	var speed_ratio: float = clampf(
		player.velocity.length() / maxf(swing_tuning.camera_fov_full_speed, 0.01),
		0.0,
		1.0
	)
	var target_fov: float = (
		swing_tuning.camera_base_fov
		+ swing_tuning.camera_speed_fov_increase * speed_ratio
	)
	var fov_blend: float = 1.0 - exp(-swing_tuning.camera_fov_smoothing * delta)
	camera.fov = lerpf(camera.fov, target_fov, fov_blend)

	var horizontal_distance: float = cos(camera_pitch) * swing_tuning.default_camera_distance
	var camera_offset: Vector3 = Vector3(
		sin(camera_yaw) * horizontal_distance,
		swing_tuning.default_camera_height + sin(camera_pitch) * swing_tuning.default_camera_distance,
		cos(camera_yaw) * horizontal_distance
	)
	var look_ahead_velocity: Vector3 = (
		wall_crawl_controller.tangent_velocity
		if wall_crawl_controller.active
		else player.velocity
	)
	var look_ahead: Vector3 = look_ahead_velocity * swing_tuning.camera_look_ahead_time
	if look_ahead.length() > swing_tuning.camera_look_ahead_max_distance:
		look_ahead = look_ahead.normalized() * swing_tuning.camera_look_ahead_max_distance
	var look_target: Vector3 = (
		player.global_position
		+ Vector3(0.0, swing_tuning.camera_look_height, 0.0)
		+ look_ahead
	)
	var desired_position: Vector3 = resolve_camera_position(look_target, player.global_position + camera_offset)
	if not camera_position_initialized:
		camera.global_position = desired_position
		camera_position_initialized = true
	else:
		var smoothing_weight: float = 1.0 - exp(-swing_tuning.camera_position_smoothing * delta)
		var smoothed_position: Vector3 = camera.global_position.lerp(desired_position, smoothing_weight)
		camera.global_position = resolve_camera_position(look_target, smoothed_position)
	camera.look_at(look_target, Vector3.UP)
	camera.rotate_object_local(Vector3.FORWARD, camera_bank)

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
			desired_position = collision_position - ray / ray_length * swing_tuning.camera_collision_margin
	desired_position.y = maxf(desired_position.y, swing_tuning.camera_minimum_height)
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
	camera.fov = swing_tuning.camera_base_fov
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
	sun.light_color = Color(1.0, 0.84, 0.70)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 260.0
	add_child(sun)

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.075, 0.19, 0.38)
	sky_material.sky_horizon_color = Color(0.88, 0.56, 0.39)
	sky_material.sky_curve = 0.18
	sky_material.sky_energy_multiplier = 1.05
	sky_material.ground_bottom_color = Color(0.025, 0.035, 0.07)
	sky_material.ground_horizon_color = Color(0.47, 0.34, 0.31)
	sky_material.ground_curve = 0.12
	sky_material.sun_angle_max = 14.0
	sky_material.sun_curve = 0.08

	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.85
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.02
	environment.adjustment_contrast = 1.08
	environment.adjustment_saturation = 1.12
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.58, 0.62, 0.76)
	environment.fog_light_energy = 0.72
	environment.fog_density = 0.0012
	environment.fog_height = 12.0
	environment.fog_height_density = 0.026
	environment.fog_sun_scatter = 0.32
	environment.glow_enabled = true
	environment.glow_intensity = 0.32
	environment.glow_bloom = 0.08
	environment.glow_hdr_threshold = 0.9

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

func create_city():
	create_city_materials()
	for x in range(-CITY_EXTENT, CITY_EXTENT + 1, BUILDING_SPACING):
		for z in range(-CITY_EXTENT, CITY_EXTENT + 1, BUILDING_SPACING):
			if abs(x) < 70 and abs(z) < 70:
				continue
			var width := randf_range(16.0, 25.0)
			var depth := randf_range(16.0, 25.0)
			var height := randf_range(35.0, 120.0)
			var building_position := Vector3(float(x) + randf_range(-4.0, 4.0), height / 2.0, float(z) + randf_range(-4.0, 4.0))
			create_building(building_position, Vector3(width, height, depth))

func create_city_materials():
	var facade_colors: Array[Color] = [
		Color(0.50, 0.27, 0.22),
		Color(0.59, 0.43, 0.31),
		Color(0.26, 0.36, 0.47),
		Color(0.40, 0.43, 0.48),
		Color(0.34, 0.27, 0.39),
		Color(0.58, 0.53, 0.43),
		Color(0.25, 0.39, 0.39),
		Color(0.52, 0.34, 0.39)
	]
	for color in facade_colors:
		var facade := StandardMaterial3D.new()
		facade.albedo_color = color
		facade.metallic = 0.08
		facade.roughness = 0.76
		building_materials.append(facade)

	var dark_windows := StandardMaterial3D.new()
	dark_windows.albedo_color = Color(0.035, 0.075, 0.12)
	dark_windows.metallic = 0.42
	dark_windows.roughness = 0.28
	window_materials.append(dark_windows)
	window_materials.append(create_emissive_window_material(
		Color(0.95, 0.50, 0.20),
		Color(0.85, 0.33, 0.09),
		0.9
	))
	window_materials.append(create_emissive_window_material(
		Color(0.38, 0.68, 1.0),
		Color(0.18, 0.42, 0.95),
		0.8
	))
	window_materials.append(create_emissive_window_material(
		Color(1.0, 0.73, 0.42),
		Color(0.95, 0.54, 0.22),
		0.72
	))

	rooftop_cap_material = StandardMaterial3D.new()
	rooftop_cap_material.albedo_color = Color(0.075, 0.085, 0.12)
	rooftop_cap_material.metallic = 0.32
	rooftop_cap_material.roughness = 0.52

func create_emissive_window_material(
	window_color: Color,
	emission_color: Color,
	emission_energy: float
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = window_color
	material.metallic = 0.38
	material.roughness = 0.26
	material.emission_enabled = true
	material.emission = emission_color
	material.emission_energy_multiplier = emission_energy
	return material

func create_building(building_position: Vector3, building_size: Vector3):
	var building := StaticBody3D.new()
	building.name = "Building"
	building.add_to_group("traversal_walls")
	building.position = building_position

	var building_mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = building_size
	building_mesh.mesh = box_mesh
	building_mesh.material_override = building_materials[randi() % building_materials.size()]

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
	cap.material_override = rooftop_cap_material
	building.add_child(cap)

func add_window_bands(building: StaticBody3D, building_size: Vector3):
	var band_count := clampi(int(building_size.y / 16.0), 2, 6)
	for band_index in range(band_count):
		var y_position := -building_size.y / 2.0 + 8.0 + band_index * ((building_size.y - 12.0) / float(band_count))
		var window_material_index: int = 0
		if randf() > 0.42:
			window_material_index = randi_range(1, window_materials.size() - 1)
		var window_material: StandardMaterial3D = window_materials[window_material_index]

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
	help.text = "WASD: move, steer, swing, or crawl on a wall | Space: jump/double jump, climb on web, or wall jump\nAirborne or moving into a wall: automatic wall grab | Tap F: detach from a wall\nHold/release left mouse: attach/detach web | Q + left mouse: shoot web behind | Mouse wheel: orbit camera\nRight mouse: emergency web release | R: reset | F3: telemetry"
	help.position = Vector2(14.0, 12.0)
	help.add_theme_font_size_override("font_size", 16)
	canvas.add_child(help)
	telemetry_label = Label.new()
	telemetry_label.name = "TraversalTelemetry"
	telemetry_label.position = Vector2(14.0, 150.0)
	telemetry_label.add_theme_font_size_override("font_size", 12)
	telemetry_label.visible = traversal_telemetry_enabled
	canvas.add_child(telemetry_label)
	web_target_indicator = ColorRect.new()
	web_target_indicator.name = "WebTargetIndicator"
	web_target_indicator.size = Vector2(8.0, 8.0)
	web_target_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(web_target_indicator)
	add_child(canvas)

func reset_player():
	wall_crawl_controller.reset()
	release_web()
	player.global_position = Vector3(0.0, 5.0, 0.0)
	player.velocity = Vector3.ZERO
