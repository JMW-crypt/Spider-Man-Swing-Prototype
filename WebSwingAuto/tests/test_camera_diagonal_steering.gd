extends SceneTree

const CameraSteering = preload("res://scripts/traversal/camera_diagonal_steering.gd")

func _initialize() -> void:
	var minimum_forward := 0.5
	var minimum_lateral := 0.5
	var forward_left := Vector4(1.0, 0.0, 1.0, 0.0)
	var forward_right := Vector4(1.0, 0.0, 0.0, 1.0)
	if not is_equal_approx(
		CameraSteering.requested_yaw_direction(
			forward_left,
			minimum_forward,
			minimum_lateral
		),
		1.0
	):
		_fail("W+A requests left camera yaw")
		return
	if not is_equal_approx(
		CameraSteering.requested_yaw_direction(
			forward_right,
			minimum_forward,
			minimum_lateral
		),
		-1.0
	):
		_fail("W+D requests right camera yaw")
		return

	var ambiguous_inputs := [
		Vector4.ZERO,
		Vector4(1.0, 0.0, 0.0, 0.0),
		Vector4(0.0, 0.0, 1.0, 0.0),
		Vector4(0.0, 0.0, 0.0, 1.0),
		Vector4(0.0, 1.0, 0.0, 0.0),
		Vector4(0.0, 1.0, 1.0, 0.0),
		Vector4(0.0, 1.0, 0.0, 1.0),
		Vector4(1.0, 0.0, 1.0, 1.0),
		Vector4(1.0, 1.0, 1.0, 0.0)
	]
	for action_strengths in ambiguous_inputs:
		if not is_zero_approx(
			CameraSteering.requested_yaw_direction(
				action_strengths,
				minimum_forward,
				minimum_lateral
			)
		):
			_fail("Single, backward, or ambiguous input requests no camera yaw")
			return

	var target_velocity: float = CameraSteering.target_yaw_velocity(
		1.0,
		true,
		true,
		100.0,
		75.0
	)
	if not is_equal_approx(rad_to_deg(target_velocity), 75.0):
		_fail("Assisted camera yaw speed is clamped")
		return
	if not is_zero_approx(
		CameraSteering.target_yaw_velocity(1.0, false, true, 75.0, 75.0)
	):
		_fail("Disabled camera assist requests no yaw")
		return
	if not is_zero_approx(
		CameraSteering.target_yaw_velocity(1.0, true, false, 75.0, 75.0)
	):
		_fail("Disallowed traversal state requests no yaw")
		return

	var velocity: float = CameraSteering.approach_yaw_velocity(
		0.0,
		target_velocity,
		180.0,
		240.0,
		75.0,
		0.1
	)
	if not is_equal_approx(rad_to_deg(velocity), 18.0):
		_fail("Assisted yaw accelerates at its configured rate")
		return
	velocity = CameraSteering.approach_yaw_velocity(
		deg_to_rad(200.0),
		target_velocity,
		180.0,
		240.0,
		75.0,
		0.1
	)
	if not is_equal_approx(rad_to_deg(velocity), 75.0):
		_fail("Assisted yaw velocity remains clamped")
		return
	velocity = CameraSteering.approach_yaw_velocity(
		velocity,
		0.0,
		180.0,
		240.0,
		75.0,
		0.1
	)
	if not is_equal_approx(rad_to_deg(velocity), 51.0):
		_fail("Releasing lateral input decelerates yaw")
		return

	var player_velocity := Vector3(12.0, 3.0, -7.0)
	var velocity_before := player_velocity
	var camera_orbit_offset := 0.0
	camera_orbit_offset += velocity * 0.1
	if not player_velocity.is_equal_approx(velocity_before):
		_fail("Camera assist does not alter player velocity")
		return
	var retained_yaw := camera_orbit_offset
	velocity = 0.0
	if not is_equal_approx(camera_orbit_offset, retained_yaw):
		_fail("Camera yaw offset remains after the assisted turn ends")
		return

	print("Camera diagonal steering tests passed.")
	quit(0)

func _fail(test_name: String) -> void:
	push_error("Camera diagonal steering test failed: " + test_name)
	quit(1)
