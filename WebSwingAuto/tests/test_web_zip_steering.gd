extends SceneTree

const WebZipSteering = preload("res://scripts/traversal/web_zip_steering.gd")

func _initialize() -> void:
	var current_velocity := Vector3(10.0, 0.0, 5.0)
	var accelerated_velocity: Vector3 = WebZipSteering.approach_anchor_velocity(
		current_velocity,
		Vector3.RIGHT,
		70.0,
		80.0,
		0.1,
		100.0,
		2.0
	)
	if not accelerated_velocity.is_equal_approx(Vector3(18.0, 0.0, 5.0)):
		_fail("Webzip accelerates toward the anchor and preserves lateral momentum")
		return

	var reversing_velocity: Vector3 = WebZipSteering.approach_anchor_velocity(
		Vector3(-10.0, 3.0, 0.0),
		Vector3.RIGHT,
		70.0,
		80.0,
		0.1,
		100.0,
		2.0
	)
	if not reversing_velocity.is_equal_approx(Vector3(-2.0, 3.0, 0.0)):
		_fail("Webzip accelerates toward the anchor when moving away")
		return

	var capped_velocity: Vector3 = WebZipSteering.approach_anchor_velocity(
		Vector3(100.0, 0.0, 0.0),
		Vector3.RIGHT,
		70.0,
		500.0,
		0.1,
		1000.0,
		2.0
	)
	if not is_equal_approx(capped_velocity.x, 70.0):
		_fail("Webzip caps velocity toward the anchor")
		return

	if not WebZipSteering.approach_anchor_velocity(
		current_velocity,
		Vector3.ZERO,
		70.0,
		80.0,
		0.1,
		100.0,
		2.0
	).is_equal_approx(current_velocity):
		_fail("Webzip safely handles a zero-length target direction")
		return
	if not WebZipSteering.has_arrived(1.5, 2.0):
		_fail("Webzip recognizes arrival inside its distance threshold")
		return
	if WebZipSteering.has_arrived(2.5, 2.0):
		_fail("Webzip does not release before reaching its distance threshold")
		return
	var braking_velocity: Vector3 = WebZipSteering.approach_anchor_velocity(
		Vector3.ZERO,
		Vector3.RIGHT,
		70.0,
		80.0,
		0.1,
		3.0,
		2.0
	)
	if braking_velocity.x >= 70.0 or braking_velocity.x < 0.0:
		_fail("Webzip reduces acceleration near the target")
		return

	print("Webzip steering tests passed.")
	quit(0)

func _fail(test_name: String) -> void:
	push_error("Webzip steering test failed: " + test_name)
	quit(1)
