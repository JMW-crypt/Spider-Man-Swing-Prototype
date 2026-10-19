extends SceneTree

const WallTraversalMath = preload("res://scripts/traversal/wall_crawl_math.gd")
const WallTraversalController = preload("res://scripts/traversal/wall_crawl_controller.gd")
const WallTraversalTuning = preload("res://scripts/traversal/wall_crawl_tuning.gd")

func _initialize():
	if not _action_has_key("move_forward", KEY_W, true):
		_fail("Forward movement is mapped to W")
		return
	if not _action_has_key("move_backward", KEY_S, true):
		_fail("Backward movement is mapped to S")
		return
	if not _action_has_key("move_left", KEY_A, true):
		_fail("Left movement is mapped to A")
		return
	if not _action_has_key("move_right", KEY_D, true):
		_fail("Right movement is mapped to D")
		return
	if not _action_has_key("wall_traverse", KEY_F, true):
		_fail("Wall traversal is mapped to F")
		return
	if not _action_has_key("rear_web_target", KEY_Q, true):
		_fail("Rear web target modifier is mapped to Q")
		return
	if not _action_has_key("reset_player", KEY_R, true):
		_fail("Reset is mapped to R")
		return
	if not _action_has_key("traversal_telemetry", KEY_F3, false):
		_fail("Telemetry is mapped to F3")
		return

	var wall_normal := Vector3(0.0, 0.0, 1.0)
	var projected: Vector3 = WallTraversalMath.project_input_onto_wall_plane(
		Vector3(2.0, 3.0, 4.0),
		wall_normal
	)
	if not projected.is_equal_approx(Vector3(2.0, 3.0, 0.0)):
		_fail("Input projection onto wall plane")
		return
	if not is_zero_approx(projected.dot(wall_normal)):
		_fail("Projected direction remains tangent to the wall")
		return

	var tangent_basis: Dictionary = WallTraversalMath.stable_wall_tangent_basis(wall_normal)
	if not tangent_basis["right"].is_equal_approx(Vector3.RIGHT):
		_fail("Stable wall tangent basis")
		return
	if not tangent_basis["up"].is_equal_approx(Vector3.UP):
		_fail("Wall-up basis follows world up")
		return

	if not WallTraversalMath.is_valid_wall_normal(Vector3.RIGHT, 55.0, 0.55):
		_fail("Vertical wall normal is eligible")
		return
	if WallTraversalMath.is_valid_wall_normal(Vector3.UP, 55.0, 0.55):
		_fail("Floor-like surface is rejected")
		return
	if WallTraversalMath.is_valid_wall_normal(Vector3.DOWN, 55.0, 0.55):
		_fail("Ceiling-like surface is rejected")
		return
	if WallTraversalMath.is_valid_wall_normal(Vector3(1.0, 0.8, 0.0), 55.0, 0.55):
		_fail("Wall normal outside slope limits is rejected")
		return

	if not is_equal_approx(WallTraversalMath.wall_contact_error(1.0, 0.75), 0.25):
		_fail("Positive contact error means too far from the wall")
		return
	if not is_equal_approx(WallTraversalMath.wall_contact_error(0.5, 0.75), -0.25):
		_fail("Negative contact error means too close to the wall")
		return
	if not WallTraversalMath.is_safe_wall_distance(0.5, 0.75, 0.25):
		_fail("Contact within penetration tolerance is accepted")
		return
	if WallTraversalMath.is_safe_wall_distance(0.48, 0.75, 0.25):
		_fail("Excessive wall penetration is rejected")
		return

	var inward_correction: float = WallTraversalMath.calculate_adhesion_correction(
		0.5,
		8.0,
		0.1,
		0.06
	)
	if not is_equal_approx(inward_correction, -0.06):
		_fail("Adhesion displacement is clamped toward the wall")
		return
	var outward_correction: float = WallTraversalMath.calculate_adhesion_correction(
		-0.5,
		8.0,
		0.1,
		0.06
	)
	if not is_equal_approx(outward_correction, 0.06):
		_fail("Adhesion displacement is clamped away from the wall")
		return
	if not is_equal_approx(
		WallTraversalMath.calculate_adhesion_velocity(0.5, 0.0, 8.0, 1.2),
		-1.2
	):
		_fail("Adhesion velocity is clamped and cannot add tangent speed")
		return
	if not is_equal_approx(
		WallTraversalMath.calculate_unclamped_adhesion_velocity(0.5, 0.0, 8.0),
		-4.0
	):
		_fail("Desired adhesion remains observable before correction clamping")
		return

	if not WallTraversalMath.normalize_wall_input(Vector2.ZERO).is_equal_approx(Vector2.ZERO):
		_fail("Zero wall input")
		return
	var diagonal: Vector2 = WallTraversalMath.normalize_wall_input(Vector2(1.0, 1.0))
	if not is_equal_approx(diagonal.length(), 1.0):
		_fail("Diagonal input is normalized")
		return

	if not WallTraversalMath.is_wall_run_entry_eligible(
		Vector3(-12.0, 0.0, 0.0),
		Vector3.RIGHT,
		11.0
	):
		_fail("Sufficient approach speed allows a wall run")
		return
	if WallTraversalMath.is_wall_run_entry_eligible(
		Vector3(4.0, 0.0, 0.0),
		Vector3.RIGHT,
		11.0
	):
		_fail("Low speed cannot enter a wall run")
		return
	if WallTraversalMath.is_wall_run_entry_eligible(
		Vector3(14.0, 0.0, 0.0),
		Vector3.RIGHT,
		11.0
	):
		_fail("Moving decisively away from a wall cannot enter a wall run")
		return
	if not WallTraversalMath.project_wall_run_velocity(
		Vector3.ZERO,
		Vector3.RIGHT,
		30.0
	).is_equal_approx(Vector3.ZERO):
		_fail("Wall-run projection does not generate speed from rest")
		return
	var projected_run_velocity: Vector3 = WallTraversalMath.project_wall_run_velocity(
		Vector3(3.0, 4.0, 5.0),
		Vector3.FORWARD,
		4.0
	)
	if not is_equal_approx(projected_run_velocity.length(), 4.0):
		_fail("Wall-run velocity is tangent and capped")
		return
	if not is_zero_approx(projected_run_velocity.z):
		_fail("Wall-run velocity removes the wall-normal component")
		return
	if WallTraversalMath.wall_run_should_become_crawl(0.21, 0.22):
		_fail("Wall-run hold threshold does not transition early")
		return
	if not WallTraversalMath.wall_run_should_become_crawl(0.22, 0.22):
		_fail("Holding wall traversal transitions the run to crawl")
		return
	if not WallTraversalMath.wall_run_duration_expired(0.9, 0.9):
		_fail("Wall run exits at its maximum duration")
		return

	var jump_velocity: Vector3 = WallTraversalMath.calculate_wall_jump_velocity(
		Vector3(2.0, 3.0, 4.0),
		wall_normal,
		9.0,
		8.0,
		0.5
	)
	if not is_equal_approx(jump_velocity.dot(wall_normal), 9.0):
		_fail("Wall jump moves outward")
		return
	if not is_equal_approx(jump_velocity.y, 9.5):
		_fail("Wall jump adds configured lift and retains tangent momentum")
		return

	if WallTraversalMath.resolve_traversal_state(false, WallTraversalMath.STATE_AIRBORNE, false) != WallTraversalMath.STATE_AIRBORNE:
		_fail("Airborne state resolution")
		return
	if WallTraversalMath.resolve_traversal_state(false, WallTraversalMath.STATE_WALL_RUN, true) != WallTraversalMath.STATE_WALL_RUN:
		_fail("Wall-run state takes priority over grounded state")
		return
	if WallTraversalMath.resolve_traversal_state(false, WallTraversalMath.STATE_WALL_CRAWLING, true) != WallTraversalMath.STATE_WALL_CRAWLING:
		_fail("Wall-crawl state takes priority over grounded state")
		return
	if WallTraversalMath.resolve_traversal_state(true, WallTraversalMath.STATE_WALL_RUN, true) != WallTraversalMath.STATE_WEB_ATTACHED:
		_fail("Web attachment takes priority over wall traversal")
		return
	if not WallTraversalMath.can_enter_wall_traversal(true, true, 0.0, true):
		_fail("Enabled wall traversal can enter with intent and a valid wall")
		return
	if WallTraversalMath.can_enter_wall_traversal(false, true, 0.0, true):
		_fail("Disabled wall traversal leaves existing movement unchanged")
		return
	if WallTraversalMath.can_enter_wall_traversal(true, true, 0.1, true):
		_fail("Reacquisition cooldown blocks wall traversal")
		return
	if WallTraversalMath.can_enter_wall_traversal(true, true, 0.0, false):
		_fail("Missing wall does not alter movement")
		return
	if not WallTraversalMath.should_auto_acquire_wall(
		true,
		false,
		Vector3.ZERO,
		Vector3.RIGHT,
		0.25
	):
		_fail("Airborne players automatically acquire a nearby wall")
		return
	if not WallTraversalMath.should_auto_acquire_wall(
		false,
		true,
		Vector3.ZERO,
		Vector3.RIGHT,
		0.25
	):
		_fail("Wall collision automatically acquires the surface")
		return
	if not WallTraversalMath.should_auto_acquire_wall(
		false,
		false,
		Vector3(-1.0, 0.0, 0.0),
		Vector3.RIGHT,
		0.25
	):
		_fail("Grounded approach momentum automatically acquires the wall")
		return
	if WallTraversalMath.should_auto_acquire_wall(
		false,
		false,
		Vector3.RIGHT,
		Vector3.RIGHT,
		0.25
	):
		_fail("Grounded movement away from a wall does not auto-acquire it")
		return

	if WallTraversalMath.resolve_space_action(true, true, true, 2) != WallTraversalMath.SPACE_ACTION_WEB_CLIMB:
		_fail("Space while web-attached remains web climbing")
		return
	if WallTraversalMath.resolve_space_action(false, true, true, 2) != WallTraversalMath.SPACE_ACTION_WALL_JUMP:
		_fail("Space during wall traversal becomes a wall jump")
		return
	if WallTraversalMath.resolve_space_action(false, false, true, 2) != WallTraversalMath.SPACE_ACTION_JUMP:
		_fail("Space while grounded remains a jump")
		return
	if WallTraversalMath.resolve_space_action(false, false, false, 1) != WallTraversalMath.SPACE_ACTION_DOUBLE_JUMP:
		_fail("Space while airborne remains a double jump")
		return

	var assisted_controller = WallTraversalController.new()
	var assisted_tuning = WallTraversalTuning.new()
	var assisted_player := CharacterBody3D.new()
	root.add_child(assisted_player)
	assisted_player.velocity = Vector3(-40.0, 20.0, 0.0)
	var assisted_wall_candidate := {
		"normal": Vector3.RIGHT,
		"distance": assisted_tuning.wall_contact_distance,
		"collider_id": 2,
		"collision_layer": 1
	}
	if not assisted_controller.enter(
		assisted_player,
		assisted_wall_candidate,
		WallTraversalController.Mode.WALL_CRAWL,
		assisted_tuning
	):
		_fail("Automatic wall-crawl entry accepts a valid wall")
		return
	if not is_zero_approx(assisted_player.velocity.dot(Vector3.RIGHT)):
		_fail("Wall entry removes all incoming normal momentum")
		return
	var maximum_entry_speed: float = Vector2(
		assisted_tuning.maximum_lateral_crawl_speed,
		assisted_tuning.maximum_vertical_crawl_speed
	).length()
	if assisted_player.velocity.length() > maximum_entry_speed:
		_fail("Wall entry caps excessive tangential momentum")
		return
	assisted_controller.exit(assisted_player, assisted_tuning, "test_reentry", false)
	if not assisted_controller.should_ignore_detached_wall(assisted_wall_candidate):
		_fail("Detached wall is ignored to prevent immediate auto-reattachment")
		return
	if assisted_controller.should_ignore_detached_wall({}):
		_fail("Leaving wall detection clears the reattachment block")
		return
	assisted_player.velocity = Vector3(40.0, 0.0, 0.0)
	if not assisted_controller.enter(
		assisted_player,
		assisted_wall_candidate,
		WallTraversalController.Mode.WALL_CRAWL,
		assisted_tuning
	):
		_fail("Wall controller can re-enter after exiting")
		return
	if not is_zero_approx(assisted_player.velocity.dot(Vector3.RIGHT)):
		_fail("Wall entry also discards outgoing bounce momentum")
		return
	assisted_wall_candidate["distance"] = assisted_tuning.wall_contact_distance + 0.5
	if not assisted_controller.update_motion(
		assisted_player,
		assisted_wall_candidate,
		Vector2.ZERO,
		false,
		1.0 / 60.0,
		assisted_tuning
	):
		_fail("Assisted wall controller corrects contact distance")
		return
	if not is_equal_approx(
		assisted_controller.applied_correction_velocity,
		-0.18 / (1.0 / 60.0)
	):
		_fail("Contact correction is strong but clamped per tick")
		return
	assisted_player.velocity = Vector3.ZERO
	assisted_wall_candidate["distance"] = assisted_tuning.wall_contact_distance
	if not assisted_controller.update_motion(
		assisted_player,
		assisted_wall_candidate,
		Vector2(0.0, 1.0),
		false,
		0.1,
		assisted_tuning
	):
		_fail("Wall crawl accepts directional input")
		return
	if assisted_controller.tangent_velocity.y < 6.9:
		_fail("Retuned upward crawl accelerates to a responsive speed")
		return
	assisted_controller.exit(assisted_player, assisted_tuning, "test_cleanup", false)
	if assisted_controller.should_ignore_detached_wall({}):
		_fail("A lost wall clears the detached-wall reattachment block")
		return
	assisted_player.queue_free()

	var controller = WallTraversalController.new()
	var tuning = WallTraversalTuning.new()
	var player := CharacterBody3D.new()
	root.add_child(player)
	player.velocity = Vector3(-12.0, 0.0, 0.0)
	var wall_candidate := {
		"normal": Vector3.RIGHT,
		"distance": tuning.wall_contact_distance,
		"collider_id": 1,
		"collision_layer": 1
	}
	if not controller.enter(
		player,
		wall_candidate,
		WallTraversalController.Mode.WALL_RUN,
		tuning
	):
		_fail("Wall-run state enters on a valid candidate")
		return
	if controller.mode != WallTraversalController.Mode.WALL_RUN:
		_fail("Controller records wall-run ownership")
		return
	if not is_equal_approx(controller.wall_run_entry_speed, 12.0):
		_fail("Wall-run entry telemetry retains incoming speed")
		return
	if not is_zero_approx(player.velocity.dot(Vector3.RIGHT)):
		_fail("Wall-run entry removes only the velocity into the wall")
		return
	if not controller.update_motion(player, wall_candidate, Vector2.ZERO, true, 0.1, tuning):
		_fail("Wall-run controller updates with valid wall contact")
		return
	if not controller.update_motion(player, wall_candidate, Vector2.ZERO, true, 0.12, tuning):
		_fail("Wall-run controller updates through the hold threshold")
		return
	if not WallTraversalMath.wall_run_should_become_crawl(
		controller.wall_run_hold_elapsed,
		tuning.wall_run_to_crawl_hold_threshold
	):
		_fail("Controller measures a sustained F hold")
		return
	controller.run_to_crawl()
	if controller.mode != WallTraversalController.Mode.WALL_CRAWL:
		_fail("Held wall run transitions to crawl")
		return
	if not controller.update_motion(player, wall_candidate, Vector2.ZERO, true, 0.1, tuning):
		_fail("Wall crawl remains stable with zero input")
		return
	if absf(player.velocity.dot(Vector3.RIGHT)) > tuning.maximum_contact_correction_speed:
		_fail("Stationary adhesion remains bounded along the wall normal")
		return
	controller.exit(player, tuning, "test_wall_jump", false, true)
	if controller.active or controller.last_detach_reason != "test_wall_jump":
		_fail("Wall jump exits the active wall state with a reason")
		return
	if not is_equal_approx(controller.last_wall_jump_velocity.dot(Vector3.RIGHT), tuning.wall_jump_outward_speed):
		_fail("Controller applies the configured wall-jump outward speed")
		return
	if not is_equal_approx(controller.reacquisition_cooldown, tuning.wall_reacquisition_cooldown):
		_fail("Wall jump starts the reacquisition cooldown")
		return
	player.queue_free()

	print("Wall traversal and controls tests passed.")
	quit(0)

func _action_has_key(action_name: String, keycode: int, physical: bool) -> bool:
	if not InputMap.has_action(action_name):
		return false
	for input_event in InputMap.action_get_events(action_name):
		var key_event: InputEventKey = input_event as InputEventKey
		if key_event == null:
			continue
		var mapped_key: int = key_event.physical_keycode if physical else key_event.keycode
		if mapped_key == keycode:
			return true
	return false

func _fail(test_name: String):
	push_error("Wall traversal test failed: " + test_name)
	quit(1)
