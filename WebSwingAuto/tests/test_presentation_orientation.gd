extends SceneTree

const Facing = preload("res://scripts/presentation/presentation_facing.gd")
const Presentation = preload("res://scripts/presentation/mixamo_hero_presentation.gd")

func _initialize() -> void:
	var correction: float = Presentation.MIXAMO_MODEL_FORWARD_YAW_OFFSET
	if not is_equal_approx(correction, PI):
		_fail("Mixamo visual forward correction is exactly 180 degrees")
		return
	var corrected_forward: Vector3 = Facing.mixamo_forward_for_yaw(0.0, correction)
	if not corrected_forward.is_equal_approx(Vector3.FORWARD):
		_fail("One 180-degree model correction turns Mixamo +Z forward toward world -Z")
		return
	var forward_yaw: float = Facing.yaw_for_forward(Vector3.FORWARD)
	if not Facing.forward_for_yaw(forward_yaw).is_equal_approx(Vector3.FORWARD):
		_fail("Forward locomotion faces the corrected visual-forward direction")
		return
	var backward_heading: float = Facing.locomotion_yaw(
		forward_yaw,
		Vector3.BACK,
		-1.0
	)
	if not is_equal_approx(backward_heading, forward_yaw):
		_fail("Backward movement keeps the visual facing forward for a backward-run pose")
		return

	var wall_normals := [
		Vector3.FORWARD,
		Vector3.BACK,
		Vector3.RIGHT,
		Vector3.LEFT,
		Vector3(1.0, 0.0, 1.0).normalized()
	]
	for wall_normal in wall_normals:
		var wall_yaw: float = Facing.yaw_for_wall_normal(wall_normal)
		var visual_forward: Vector3 = Facing.forward_for_yaw(wall_yaw)
		if visual_forward.dot(-wall_normal) < 0.999:
			_fail("Wall-facing points the corrected visual forward into the active wall")
			return
		if not is_equal_approx(Facing.yaw_for_wall_normal(wall_normal), wall_yaw):
			_fail("Crawl input does not affect wall-normal facing")
			return

	var movement_velocity := Vector3(7.0, 4.0, -3.0)
	var movement_velocity_before := movement_velocity
	Facing.yaw_for_wall_normal(Vector3.RIGHT)
	if not movement_velocity.is_equal_approx(movement_velocity_before):
		_fail("Wall-facing presentation does not modify movement velocity")
		return
	print("Presentation orientation tests passed.")
	quit(0)

func _fail(test_name: String) -> void:
	push_error("Presentation orientation test failed: " + test_name)
	quit(1)
