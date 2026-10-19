@abstract
class_name SwingSolver
extends Resource

const SwingTuningScript = preload("res://scripts/traversal/swing_tuning.gd")

# The CharacterBody3D remains the sole owner of authoritative velocity.
@abstract
func calculate_spring_velocity_delta(
	velocity: Vector3,
	anchor_to_origin: Vector3,
	rope_length: float,
	delta: float,
	tuning: SwingTuningScript
) -> Vector3

@abstract
func apply_post_move_constraint(
	player: CharacterBody3D,
	anchor: Vector3,
	rope_origin: Vector3,
	rope_length: float,
	tuning: SwingTuningScript
) -> void
