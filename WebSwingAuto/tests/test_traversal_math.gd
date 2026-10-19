extends SceneTree

const MathHelpers = preload("res://scripts/traversal/traversal_math.gd")

func _initialize():
	var decomposition: Dictionary = MathHelpers.decompose_radial_tangential(
		Vector3(3.0, 4.0, 0.0),
		Vector3.UP
	)
	if not is_equal_approx(decomposition["radial_speed"], 4.0):
		_fail("Radial speed decomposition")
		return
	if not decomposition["tangential_velocity"].is_equal_approx(Vector3(3.0, 0.0, 0.0)):
		_fail("Tangential velocity decomposition")
		return

	var zero_direction: Dictionary = MathHelpers.decompose_radial_tangential(
		Vector3(3.0, 4.0, 0.0),
		Vector3.ZERO
	)
	if not zero_direction["tangential_velocity"].is_equal_approx(Vector3(3.0, 4.0, 0.0)):
		_fail("Zero radial direction handling")
		return

	if not is_equal_approx(MathHelpers.rope_error(12.0, 8.0), 4.0):
		_fail("Positive rope error")
		return
	if not is_equal_approx(MathHelpers.rope_error(6.0, 8.0), -2.0):
		_fail("Negative rope error")
		return

	print("Traversal math tests passed.")
	quit(0)

func _fail(test_name: String):
	push_error("Traversal math test failed: " + test_name)
	quit(1)
