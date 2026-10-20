extends RefCounted

static func yaw_for_forward(forward: Vector3) -> float:
	var horizontal_forward := Vector3(forward.x, 0.0, forward.z)
	if horizontal_forward.length_squared() <= 0.0001:
		return 0.0
	horizontal_forward = horizontal_forward.normalized()
	return atan2(-horizontal_forward.x, -horizontal_forward.z)

static func locomotion_yaw(
	current_yaw: float,
	movement_direction: Vector3,
	forward_input: float
) -> float:
	if forward_input <= 0.01:
		return current_yaw
	return yaw_for_forward(movement_direction)

static func yaw_for_wall_normal(wall_normal: Vector3) -> float:
	return yaw_for_forward(-wall_normal)

static func forward_for_yaw(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

static func mixamo_forward_for_yaw(yaw: float, model_forward_correction: float) -> Vector3:
	return Basis(Vector3.UP, yaw + model_forward_correction) * Vector3.BACK
