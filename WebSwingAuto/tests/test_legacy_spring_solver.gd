extends SceneTree

const LegacySolver = preload("res://scripts/traversal/legacy_spring_solver.gd")
const SolverInterface = preload("res://scripts/traversal/swing_solver.gd")
const TuningResource = preload("res://scripts/traversal/swing_tuning.gd")

func _initialize():
	call_deferred("_run_tests")

func _run_tests():
	var solver: SolverInterface = LegacySolver.new()
	var tuning = TuningResource.new()
	var spring_delta: Vector3 = solver.calculate_spring_velocity_delta(
		Vector3(0.0, 2.0, 0.0),
		Vector3(0.0, 10.0, 0.0),
		8.0,
		0.1,
		tuning
	)
	if not spring_delta.is_equal_approx(Vector3(0.0, -5.0, 0.0)):
		_fail("Legacy spring solver changed the default force response")
		return

	var slack_delta: Vector3 = solver.calculate_spring_velocity_delta(
		Vector3.ZERO,
		Vector3(0.0, 5.0, 0.0),
		8.0,
		0.1,
		tuning
	)
	if not slack_delta.is_equal_approx(Vector3.ZERO):
		_fail("Legacy spring solver changed slack-rope behavior")
		return

	if not is_equal_approx(tuning.spring_strength, 20.0):
		_fail("Default spring strength")
		return
	if not is_equal_approx(tuning.web_attach_yank_impulse, 12.0):
		_fail("Default attach impulse")
		return

	var player := CharacterBody3D.new()
	root.add_child(player)
	player.position = Vector3(12.0, 0.0, 0.0)
	player.velocity = Vector3(5.0, 0.0, 0.0)
	solver.apply_post_move_constraint(
		player,
		Vector3.ZERO,
		player.global_position,
		10.0,
		tuning
	)
	if not player.global_position.is_equal_approx(Vector3(10.0, 0.0, 0.0)):
		_fail("Legacy rope positional correction")
		return
	if not player.velocity.is_equal_approx(Vector3.ZERO):
		_fail("Legacy rope radial velocity correction")
		return

	print("Legacy spring solver tests passed.")
	quit(0)

func _fail(test_name: String):
	push_error("Legacy spring solver test failed: " + test_name)
	quit(1)
