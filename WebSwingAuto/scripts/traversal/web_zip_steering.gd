extends RefCounted

static func approach_anchor_velocity(
	current_velocity: Vector3,
	direction_to_anchor: Vector3,
	maximum_speed: float,
	acceleration: float,
	delta: float,
	target_distance: float = INF,
	arrival_distance: float = 0.0
) -> Vector3:
	if direction_to_anchor.length_squared() <= 0.0001:
		return current_velocity
	var direction := direction_to_anchor.normalized()
	var current_anchor_speed: float = current_velocity.dot(direction)
	var target_anchor_speed: float = maxf(maximum_speed, 0.0)
	var safe_acceleration: float = maxf(acceleration, 0.0)
	if is_finite(target_distance) and safe_acceleration > 0.0:
		var remaining_distance: float = maxf(
			target_distance - maxf(arrival_distance, 0.0),
			0.0
		)
		var stopping_speed: float = sqrt(2.0 * safe_acceleration * remaining_distance)
		target_anchor_speed = minf(target_anchor_speed, stopping_speed)
	var next_anchor_speed: float = move_toward(
		current_anchor_speed,
		target_anchor_speed,
		safe_acceleration * maxf(delta, 0.0)
	)
	return current_velocity + direction * (next_anchor_speed - current_anchor_speed)

static func has_arrived(distance: float, arrival_distance: float) -> bool:
	return distance <= maxf(arrival_distance, 0.0)
