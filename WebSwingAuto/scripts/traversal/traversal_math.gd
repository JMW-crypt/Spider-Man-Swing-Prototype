class_name TraversalMath
extends RefCounted

static func decompose_radial_tangential(
	velocity: Vector3,
	radial_direction: Vector3
) -> Dictionary:
	if radial_direction.length_squared() <= 0.000001:
		return {
			"radial_speed": 0.0,
			"tangential_velocity": velocity
		}
	var radial_unit: Vector3 = radial_direction.normalized()
	var radial_speed: float = velocity.dot(radial_unit)
	return {
		"radial_speed": radial_speed,
		"tangential_velocity": velocity - radial_unit * radial_speed
	}

static func rope_error(distance: float, rope_length: float) -> float:
	return distance - rope_length
