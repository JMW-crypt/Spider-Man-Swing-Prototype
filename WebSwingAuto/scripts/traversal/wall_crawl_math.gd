class_name WallCrawlMath
extends RefCounted

const STATE_GROUNDED := 0
const STATE_AIRBORNE := 1
const STATE_WALL_RUN := 2
const STATE_WALL_CRAWLING := 3
const STATE_WEB_ATTACHED := 4

const SPACE_ACTION_NONE := 0
const SPACE_ACTION_JUMP := 1
const SPACE_ACTION_DOUBLE_JUMP := 2
const SPACE_ACTION_WALL_JUMP := 3
const SPACE_ACTION_WEB_CLIMB := 4

static func resolve_traversal_state(
	web_attached: bool,
	wall_state: int,
	grounded: bool
) -> int:
	if web_attached:
		return STATE_WEB_ATTACHED
	if wall_state == STATE_WALL_RUN:
		return STATE_WALL_RUN
	if wall_state == STATE_WALL_CRAWLING:
		return STATE_WALL_CRAWLING
	if grounded:
		return STATE_GROUNDED
	return STATE_AIRBORNE

static func resolve_space_action(
	web_attached: bool,
	wall_traversal_active: bool,
	grounded: bool,
	jumps_remaining: int
) -> int:
	if web_attached:
		return SPACE_ACTION_WEB_CLIMB
	if wall_traversal_active:
		return SPACE_ACTION_WALL_JUMP
	if grounded:
		return SPACE_ACTION_JUMP
	if jumps_remaining > 0:
		return SPACE_ACTION_DOUBLE_JUMP
	return SPACE_ACTION_NONE

static func can_enter_wall_traversal(
	enabled: bool,
	input_held: bool,
	cooldown: float,
	wall_available: bool
) -> bool:
	return enabled and input_held and cooldown <= 0.0 and wall_available

static func should_auto_acquire_wall(
	airborne: bool,
	collided_with_wall: bool,
	velocity: Vector3,
	wall_normal: Vector3,
	minimum_approach_speed: float
) -> bool:
	if wall_normal.length_squared() <= 0.000001:
		return false
	return (
		airborne
		or collided_with_wall
		or velocity.dot(wall_normal.normalized()) <= -minimum_approach_speed
	)

static func is_valid_wall_normal(
	normal: Vector3,
	minimum_steepness_degrees: float,
	maximum_vertical_component: float
) -> bool:
	if normal.length_squared() <= 0.000001:
		return false
	var unit_normal: Vector3 = normal.normalized()
	var vertical_component: float = absf(unit_normal.dot(Vector3.UP))
	var steepness: float = rad_to_deg(acos(clampf(vertical_component, 0.0, 1.0)))
	return (
		steepness >= minimum_steepness_degrees
		and vertical_component <= maximum_vertical_component
	)

static func project_input_onto_wall_plane(
	input_direction: Vector3,
	wall_normal: Vector3
) -> Vector3:
	if wall_normal.length_squared() <= 0.000001:
		return Vector3.ZERO
	var unit_normal: Vector3 = wall_normal.normalized()
	return input_direction - unit_normal * input_direction.dot(unit_normal)

static func stable_wall_tangent_basis(wall_normal: Vector3) -> Dictionary:
	if wall_normal.length_squared() <= 0.000001:
		return {"right": Vector3.ZERO, "up": Vector3.UP}
	var unit_normal: Vector3 = wall_normal.normalized()
	var wall_up: Vector3 = project_input_onto_wall_plane(Vector3.UP, unit_normal)
	if wall_up.length_squared() <= 0.000001:
		wall_up = Vector3.FORWARD
	else:
		wall_up = wall_up.normalized()
	var wall_right: Vector3 = wall_up.cross(unit_normal).normalized()
	return {"right": wall_right, "up": wall_up}

static func normalize_wall_input(input: Vector2) -> Vector2:
	if input.length_squared() <= 1.0:
		return input
	return input.normalized()

static func wall_contact_error(distance_to_wall: float, contact_distance: float) -> float:
	return distance_to_wall - contact_distance

static func is_safe_wall_distance(
	distance_to_wall: float,
	contact_distance: float,
	penetration_rejection_threshold: float
) -> bool:
	return distance_to_wall >= contact_distance - penetration_rejection_threshold

static func calculate_adhesion_correction(
	contact_error: float,
	adhesion_strength: float,
	delta: float,
	maximum_correction: float
) -> float:
	return clampf(
		-contact_error * adhesion_strength * delta,
		-maximum_correction,
		maximum_correction
	)

static func calculate_adhesion_velocity(
	contact_error: float,
	normal_velocity: float,
	correction_strength: float,
	maximum_correction_speed: float
) -> float:
	return clampf(
		calculate_unclamped_adhesion_velocity(
			contact_error,
			normal_velocity,
			correction_strength
		),
		-maximum_correction_speed,
		maximum_correction_speed
	)

static func calculate_unclamped_adhesion_velocity(
	contact_error: float,
	normal_velocity: float,
	correction_strength: float
) -> float:
	if absf(contact_error) <= 0.015:
		return -normal_velocity
	return -contact_error * correction_strength - normal_velocity * 0.65

static func is_wall_run_entry_eligible(
	velocity: Vector3,
	wall_normal: Vector3,
	minimum_speed: float,
	maximum_speed_away_from_wall: float = 2.0
) -> bool:
	if wall_normal.length_squared() <= 0.000001 or velocity.length() < minimum_speed:
		return false
	var normal_speed: float = velocity.dot(wall_normal.normalized())
	return normal_speed <= maximum_speed_away_from_wall

static func project_wall_run_velocity(
	velocity: Vector3,
	wall_normal: Vector3,
	maximum_speed: float
) -> Vector3:
	var tangent_velocity: Vector3 = project_input_onto_wall_plane(velocity, wall_normal)
	if tangent_velocity.length() > maximum_speed:
		return tangent_velocity.normalized() * maximum_speed
	return tangent_velocity

static func wall_run_should_become_crawl(
	wall_run_hold_duration: float,
	transition_threshold: float
) -> bool:
	return wall_run_hold_duration >= transition_threshold

static func wall_run_duration_expired(
	wall_run_duration: float,
	maximum_duration: float
) -> bool:
	return wall_run_duration >= maximum_duration

static func calculate_wall_jump_velocity(
	tangential_velocity: Vector3,
	wall_normal: Vector3,
	outward_speed: float,
	upward_speed: float,
	tangential_momentum_retention: float = 1.0
) -> Vector3:
	if wall_normal.length_squared() <= 0.000001:
		return Vector3(
			tangential_velocity.x,
			maxf(tangential_velocity.y, upward_speed),
			tangential_velocity.z
		)
	var unit_normal: Vector3 = wall_normal.normalized()
	var tangent: Vector3 = project_input_onto_wall_plane(tangential_velocity, unit_normal)
	return (
		tangent * tangential_momentum_retention
		+ unit_normal * outward_speed
		+ Vector3.UP * upward_speed
	)
