class_name LegacySpringSolver
extends "res://scripts/traversal/swing_solver.gd"

const TraversalMathScript = preload("res://scripts/traversal/traversal_math.gd")

func calculate_spring_velocity_delta(
	velocity: Vector3,
	anchor_to_origin: Vector3,
	rope_length: float,
	delta: float,
	tuning: SwingTuningScript
) -> Vector3:
	var distance: float = anchor_to_origin.length()
	if distance <= 0.01:
		return Vector3.ZERO
	var stretch: float = TraversalMathScript.rope_error(distance, rope_length)
	if stretch <= 0.0:
		return Vector3.ZERO

	var outward_direction: Vector3 = anchor_to_origin / distance
	var outward_speed: float = velocity.dot(outward_direction)
	var spring_force: float = clampf(
		stretch * tuning.spring_strength + outward_speed * tuning.spring_damping,
		0.0,
		tuning.max_spring_force
	)
	return -outward_direction * spring_force * delta

func apply_post_move_constraint(
	player: CharacterBody3D,
	anchor: Vector3,
	rope_origin: Vector3,
	rope_length: float,
	tuning: SwingTuningScript
) -> void:
	var anchor_to_player: Vector3 = rope_origin - anchor
	var current_distance: float = anchor_to_player.length()
	var rope_error: float = TraversalMathScript.rope_error(current_distance, rope_length)
	if rope_error <= tuning.rope_safety_stretch or current_distance <= 0.01:
		return

	var outward_direction: Vector3 = anchor_to_player / current_distance
	var outward_speed: float = player.velocity.dot(outward_direction)
	if outward_speed > 0.0:
		player.velocity -= outward_direction * outward_speed
	player.global_position -= outward_direction * rope_error
