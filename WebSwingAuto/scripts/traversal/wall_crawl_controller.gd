class_name WallCrawlController
extends RefCounted

const WallCrawlMathScript = preload("res://scripts/traversal/wall_crawl_math.gd")
const WallCrawlTuningScript = preload("res://scripts/traversal/wall_crawl_tuning.gd")

enum Mode { NONE, WALL_RUN, WALL_CRAWL }

# CharacterBody3D owns velocity; this controller only computes its traversal contribution.
var mode: int = Mode.NONE
var active: bool:
	get:
		return mode != Mode.NONE
var wall_normal: Vector3 = Vector3.ZERO
var wall_collider_id: int = 0
var wall_collision_layer: int = 0
var wall_distance: float = 0.0
var contact_error: float = 0.0
var tangent_velocity: Vector3 = Vector3.ZERO
var adhesion_correction: Vector3 = Vector3.ZERO
var desired_correction_velocity: float = 0.0
var applied_correction_velocity: float = 0.0
var wall_run_downward_velocity: Vector3 = Vector3.ZERO
var wall_run_entry_speed: float = 0.0
var wall_run_elapsed: float = 0.0
var wall_run_hold_elapsed: float = 0.0
var wall_lost_elapsed: float = 0.0
var last_wall_jump_velocity: Vector3 = Vector3.ZERO
var last_detach_reason: String = "none"
var reacquisition_cooldown: float = 0.0
var blocked_wall_collider_id: int = 0

func advance_cooldown(delta: float) -> void:
	reacquisition_cooldown = maxf(0.0, reacquisition_cooldown - delta)

func should_ignore_detached_wall(candidate: Dictionary) -> bool:
	if blocked_wall_collider_id == 0:
		return false
	if candidate.is_empty():
		blocked_wall_collider_id = 0
		return false
	var candidate_collider_id: int = int(candidate.get("collider_id", 0))
	if candidate_collider_id == blocked_wall_collider_id:
		return true
	blocked_wall_collider_id = 0
	return false

func enter(
	player: CharacterBody3D,
	candidate: Dictionary,
	start_mode: int,
	tuning: WallCrawlTuningScript
) -> bool:
	if active or candidate.is_empty() or start_mode == Mode.NONE:
		return false
	var candidate_normal: Vector3 = candidate.get("normal", Vector3.ZERO)
	if candidate_normal.length_squared() <= 0.000001:
		return false
	var incoming_speed: float = player.velocity.length()
	wall_normal = candidate_normal.normalized()
	tangent_velocity = WallCrawlMathScript.project_input_onto_wall_plane(
		player.velocity,
		wall_normal
	)
	if start_mode == Mode.WALL_RUN:
		wall_run_entry_speed = incoming_speed
		tangent_velocity = WallCrawlMathScript.project_wall_run_velocity(
			player.velocity,
			wall_normal,
			tuning.maximum_wall_run_speed
		)
		mode = Mode.WALL_RUN
	else:
		var maximum_entry_speed: float = Vector2(
			tuning.maximum_lateral_crawl_speed,
			tuning.maximum_vertical_crawl_speed
		).length()
		if tangent_velocity.length() > maximum_entry_speed:
			tangent_velocity = tangent_velocity.normalized() * maximum_entry_speed
		wall_run_entry_speed = 0.0
		mode = Mode.WALL_CRAWL
	player.velocity = tangent_velocity
	wall_collider_id = int(candidate.get("collider_id", 0))
	wall_collision_layer = int(candidate.get("collision_layer", 0))
	wall_distance = float(candidate.get("distance", tuning.wall_contact_distance))
	contact_error = WallCrawlMathScript.wall_contact_error(
		wall_distance,
		tuning.wall_contact_distance
	)
	adhesion_correction = Vector3.ZERO
	desired_correction_velocity = 0.0
	applied_correction_velocity = 0.0
	wall_run_downward_velocity = Vector3.ZERO
	wall_run_elapsed = 0.0
	wall_run_hold_elapsed = 0.0
	wall_lost_elapsed = 0.0
	last_wall_jump_velocity = Vector3.ZERO
	last_detach_reason = "none"
	return true

func update_motion(
	player: CharacterBody3D,
	candidate: Dictionary,
	input: Vector2,
	wall_input_held: bool,
	delta: float,
	tuning: WallCrawlTuningScript
) -> bool:
	if not active or candidate.is_empty():
		return false
	var candidate_normal: Vector3 = candidate.get("normal", Vector3.ZERO)
	if candidate_normal.length_squared() <= 0.000001:
		return false
	var angle_to_candidate: float = rad_to_deg(
		acos(clampf(wall_normal.dot(candidate_normal.normalized()), -1.0, 1.0))
	)
	if angle_to_candidate > tuning.maximum_corner_transition_degrees:
		return false

	var normal_blend: float = 1.0 - exp(-tuning.wall_normal_smoothing * delta)
	wall_normal = wall_normal.slerp(candidate_normal.normalized(), normal_blend).normalized()
	wall_collider_id = int(candidate.get("collider_id", wall_collider_id))
	wall_distance = float(candidate.get("distance", wall_distance))
	contact_error = WallCrawlMathScript.wall_contact_error(
		wall_distance,
		tuning.wall_contact_distance
	)
	wall_lost_elapsed = 0.0
	var normalized_input: Vector2 = WallCrawlMathScript.normalize_wall_input(input)
	if mode == Mode.WALL_RUN:
		_update_wall_run(player, normalized_input, wall_input_held, delta, tuning)
	else:
		_update_wall_crawl(player, normalized_input, delta, tuning)
	_apply_contact_correction(player, normalized_input, delta, tuning)
	return true

func _update_wall_crawl(
	player: CharacterBody3D,
	normalized_input: Vector2,
	delta: float,
	tuning: WallCrawlTuningScript
) -> void:
	var tangent_basis: Dictionary = WallCrawlMathScript.stable_wall_tangent_basis(wall_normal)
	var desired_velocity: Vector3 = (
		tangent_basis["right"] * normalized_input.x * tuning.maximum_lateral_crawl_speed
		+ tangent_basis["up"] * normalized_input.y * tuning.maximum_vertical_crawl_speed
	)
	var current_tangent_velocity: Vector3 = WallCrawlMathScript.project_input_onto_wall_plane(
		player.velocity,
		wall_normal
	)
	var acceleration: float = (
		tuning.crawl_acceleration
		if normalized_input.length_squared() > 0.0001
		else tuning.crawl_deceleration
	)
	tangent_velocity = current_tangent_velocity.move_toward(
		desired_velocity,
		acceleration * delta
	)
	wall_run_downward_velocity = Vector3.ZERO

func _update_wall_run(
	player: CharacterBody3D,
	normalized_input: Vector2,
	wall_input_held: bool,
	delta: float,
	tuning: WallCrawlTuningScript
) -> void:
	wall_run_elapsed += delta
	if wall_input_held:
		wall_run_hold_elapsed += delta
	else:
		wall_run_hold_elapsed = 0.0
	var tangent_basis: Dictionary = WallCrawlMathScript.stable_wall_tangent_basis(wall_normal)
	var desired_direction: Vector3 = (
		tangent_basis["right"] * normalized_input.x
		+ tangent_basis["up"] * normalized_input.y
	)
	var current_tangent_velocity: Vector3 = WallCrawlMathScript.project_input_onto_wall_plane(
		player.velocity,
		wall_normal
	)
	if desired_direction.length_squared() > 0.0001:
		var current_direction: Vector3 = (
			current_tangent_velocity.normalized()
			if current_tangent_velocity.length_squared() > 0.0001
			else desired_direction
		)
		var steered_direction: Vector3 = current_direction.lerp(
			desired_direction.normalized(),
			clampf(tuning.wall_run_steering_influence * delta, 0.0, 1.0)
		).normalized()
		var desired_speed: float = minf(
			current_tangent_velocity.length(),
			tuning.maximum_wall_run_speed
		)
		var steering_weight: float = clampf(
			tuning.wall_run_steering_influence * delta / maxf(desired_speed, 0.01),
			0.0,
			1.0
		)
		current_tangent_velocity = current_tangent_velocity.lerp(
			steered_direction * desired_speed,
			steering_weight
		)
	var speed_retention: float = pow(tuning.wall_run_tangential_speed_retention, delta)
	tangent_velocity = current_tangent_velocity * speed_retention
	if tangent_velocity.length() > tuning.maximum_wall_run_speed:
		tangent_velocity = tangent_velocity.normalized() * tuning.maximum_wall_run_speed
	wall_run_downward_velocity = WallCrawlMathScript.project_input_onto_wall_plane(
		Vector3.DOWN,
		wall_normal
	) * tuning.wall_run_downward_acceleration * delta
	tangent_velocity += wall_run_downward_velocity
	tangent_velocity = WallCrawlMathScript.project_input_onto_wall_plane(
		tangent_velocity,
		wall_normal
	)
	if tangent_velocity.length() > tuning.maximum_wall_run_speed:
		tangent_velocity = tangent_velocity.normalized() * tuning.maximum_wall_run_speed

func _apply_contact_correction(
	player: CharacterBody3D,
	normalized_input: Vector2,
	delta: float,
	tuning: WallCrawlTuningScript
) -> void:
	var current_normal_velocity: float = player.velocity.dot(wall_normal)
	var correction_strength: float = (
		tuning.stationary_adhesion_strength
		if normalized_input.length_squared() <= 0.0001 and mode == Mode.WALL_CRAWL
		else tuning.contact_correction_strength
	)
	var tick_speed_limit: float = (
		tuning.maximum_adhesion_correction_per_physics_tick / maxf(delta, 0.0001)
	)
	desired_correction_velocity = WallCrawlMathScript.calculate_unclamped_adhesion_velocity(
		contact_error,
		current_normal_velocity,
		correction_strength
	)
	applied_correction_velocity = clampf(
		desired_correction_velocity,
		-minf(tuning.maximum_contact_correction_speed, tick_speed_limit),
		minf(tuning.maximum_contact_correction_speed, tick_speed_limit)
	)
	adhesion_correction = wall_normal * applied_correction_velocity
	player.velocity = tangent_velocity + adhesion_correction

func update_without_contact(
	player: CharacterBody3D,
	delta: float,
	tuning: WallCrawlTuningScript,
	gravity: float
) -> bool:
	if not active:
		return false
	wall_lost_elapsed += delta
	if wall_lost_elapsed > tuning.wall_lost_grace_duration:
		return false
	if mode == Mode.WALL_RUN:
		wall_run_elapsed += delta
		wall_run_downward_velocity = WallCrawlMathScript.project_input_onto_wall_plane(
			Vector3.DOWN,
			wall_normal
		) * tuning.wall_run_downward_acceleration * delta
		tangent_velocity += wall_run_downward_velocity
	else:
		tangent_velocity = tangent_velocity.move_toward(
			Vector3.ZERO,
			tuning.crawl_deceleration * delta
		)
		wall_run_downward_velocity = Vector3.DOWN * gravity * delta
		tangent_velocity += wall_run_downward_velocity
	if mode == Mode.WALL_RUN and tangent_velocity.length() > tuning.maximum_wall_run_speed:
		tangent_velocity = tangent_velocity.normalized() * tuning.maximum_wall_run_speed
	adhesion_correction = Vector3.ZERO
	desired_correction_velocity = 0.0
	applied_correction_velocity = 0.0
	player.velocity = tangent_velocity
	return true

func run_to_crawl() -> void:
	if mode == Mode.WALL_RUN:
		mode = Mode.WALL_CRAWL
		wall_run_hold_elapsed = 0.0
		tangent_velocity = WallCrawlMathScript.project_input_onto_wall_plane(
			tangent_velocity,
			wall_normal
		)

func exit(
	player: CharacterBody3D,
	tuning: WallCrawlTuningScript,
	reason: String,
	apply_clearance: bool = true,
	wall_jump: bool = false
) -> void:
	if not active:
		return
	last_detach_reason = reason
	blocked_wall_collider_id = wall_collider_id
	var retained_tangent: Vector3 = WallCrawlMathScript.project_input_onto_wall_plane(
		player.velocity,
		wall_normal
	)
	if wall_jump:
		last_wall_jump_velocity = WallCrawlMathScript.calculate_wall_jump_velocity(
			retained_tangent,
			wall_normal,
			tuning.wall_jump_outward_speed,
			tuning.wall_jump_upward_speed,
			tuning.wall_jump_tangential_momentum_retention
		)
		player.velocity = last_wall_jump_velocity
	else:
		last_wall_jump_velocity = Vector3.ZERO
		player.velocity = retained_tangent
	mode = Mode.NONE
	var exit_cooldown: float = tuning.wall_exit_reacquisition_cooldown
	if wall_jump:
		exit_cooldown = tuning.wall_reacquisition_cooldown
	reacquisition_cooldown = maxf(reacquisition_cooldown, exit_cooldown)
	adhesion_correction = Vector3.ZERO
	desired_correction_velocity = 0.0
	applied_correction_velocity = 0.0
	wall_run_downward_velocity = Vector3.ZERO
	if apply_clearance and tuning.detach_clearance > 0.0:
		player.move_and_collide(wall_normal * tuning.detach_clearance)

func reset() -> void:
	mode = Mode.NONE
	wall_normal = Vector3.ZERO
	wall_collider_id = 0
	wall_collision_layer = 0
	wall_distance = 0.0
	contact_error = 0.0
	tangent_velocity = Vector3.ZERO
	adhesion_correction = Vector3.ZERO
	desired_correction_velocity = 0.0
	applied_correction_velocity = 0.0
	wall_run_downward_velocity = Vector3.ZERO
	wall_run_entry_speed = 0.0
	wall_run_elapsed = 0.0
	wall_run_hold_elapsed = 0.0
	wall_lost_elapsed = 0.0
	last_wall_jump_velocity = Vector3.ZERO
	last_detach_reason = "reset"
	reacquisition_cooldown = 0.0
	blocked_wall_collider_id = 0
