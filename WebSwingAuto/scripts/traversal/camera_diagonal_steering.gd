extends RefCounted

static func requested_yaw_direction(
	action_strengths: Vector4,
	minimum_forward_input: float,
	minimum_lateral_input: float
) -> float:
	if (
		action_strengths.x < minimum_forward_input
		or action_strengths.y >= minimum_forward_input
		or (
			action_strengths.z >= minimum_lateral_input
			and action_strengths.w >= minimum_lateral_input
		)
		or (
			action_strengths.z < minimum_lateral_input
			and action_strengths.w < minimum_lateral_input
		)
	):
		return 0.0
	if action_strengths.z >= minimum_lateral_input:
		return 1.0
	if action_strengths.w >= minimum_lateral_input:
		return -1.0
	return 0.0

static func target_yaw_velocity(
	direction: float,
	enabled: bool,
	state_allowed: bool,
	speed_degrees: float,
	maximum_speed_degrees: float
) -> float:
	if not enabled or not state_allowed:
		return 0.0
	var maximum_speed: float = deg_to_rad(maxf(maximum_speed_degrees, 0.0))
	var requested_speed: float = deg_to_rad(maxf(speed_degrees, 0.0))
	return clampf(direction * requested_speed, -maximum_speed, maximum_speed)

static func approach_yaw_velocity(
	current_velocity: float,
	target_velocity: float,
	acceleration_degrees: float,
	deceleration_degrees: float,
	maximum_speed_degrees: float,
	delta: float
) -> float:
	var acceleration: float = deg_to_rad(
		deceleration_degrees
		if is_zero_approx(target_velocity)
		else acceleration_degrees
	)
	var maximum_speed: float = deg_to_rad(maxf(maximum_speed_degrees, 0.0))
	return clampf(
		move_toward(
			clampf(current_velocity, -maximum_speed, maximum_speed),
			clampf(target_velocity, -maximum_speed, maximum_speed),
			maxf(acceleration, 0.0) * maxf(delta, 0.0)
		),
		-maximum_speed,
		maximum_speed
	)
