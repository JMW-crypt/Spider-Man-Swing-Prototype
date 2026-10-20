extends SceneTree

const Presentation = preload("res://scripts/presentation/mixamo_hero_presentation.gd")

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var presentation = Presentation.new()
	root.add_child(presentation)
	if not presentation.initialize():
		_fail("Mixamo character, clips, and hand attachment initialize")
		return

	if presentation.character_skeleton.get_bone_count() != 65:
		_fail("Imported character skeleton has the expected 65 bones")
		return
	if presentation.model_orientation_root.get_parent() != presentation:
		_fail("Model-forward correction is applied by one presentation-only pivot")
		return
	if presentation.character_root.get_parent() != presentation.model_orientation_root:
		_fail("Imported character is beneath the dedicated forward-correction pivot")
		return
	if not is_equal_approx(
		presentation.model_orientation_root.rotation.y,
		Presentation.MIXAMO_MODEL_FORWARD_YAW_OFFSET
	):
		_fail("Imported character receives exactly one 180-degree forward correction")
		return
	if not is_equal_approx(
		presentation.model_orientation_root.rotation.y,
		PI
	):
		_fail("Imported Mixamo +Z forward axis is corrected to local -Z")
		return
	if presentation.character_skeleton.find_bone("mixamorig_RightHand") < 0:
		_fail("Imported skeleton contains the right-hand attachment bone")
		return
	var character_mesh: MeshInstance3D = (
		presentation.character_root.find_child("Ch44", true, false) as MeshInstance3D
	)
	if (
		character_mesh == null
		or character_mesh.mesh == null
		or character_mesh.mesh.get_surface_count() == 0
	):
		_fail("Imported Ch44 character has a renderable mesh")
		return
	if presentation.web_hand_attachment.get_parent() != presentation.character_skeleton:
		_fail("Web origin is attached to the animated skeleton")
		return
	if presentation.web_hand_attachment.bone_name != "mixamorig_RightHand":
		_fail("Web origin uses the right-hand bone")
		return
	if not (presentation.animation_tree.tree_root is AnimationNodeStateMachine):
		_fail("AnimationTree uses a state machine root")
		return

	var state_machine := presentation.animation_tree.tree_root as AnimationNodeStateMachine
	for state_name in Presentation.TRAVERSAL_STATES:
		if not state_machine.has_node(state_name):
			_fail("AnimationTree has the %s traversal presentation state" % state_name)
			return
	var sprint_speed_scale := float(
		presentation.animation_tree.get("parameters/sprint/time_scale/scale")
	)
	if not is_equal_approx(sprint_speed_scale, Presentation.SPRINT_ANIMATION_SPEED_SCALE):
		_fail("Sprint presentation uses the accelerated run animation")
		return

	var animation_library: AnimationLibrary = (
		presentation.character_animation_player.get_animation_library("mixamo")
	)
	if animation_library == null:
		_fail("Retargeted Mixamo animation library is registered")
		return
	if not presentation.flip_animation_available:
		_fail("Project-local forward-flip animation is loaded and retargeted")
		return
	if not animation_library.has_animation(Presentation.DOUBLE_JUMP_FLIP_STATE):
		_fail("Retargeted animation library contains the double-jump flip clip")
		return
	var flip_animation: Animation = animation_library.get_animation(
		Presentation.DOUBLE_JUMP_FLIP_STATE
	)
	if flip_animation.loop_mode != Animation.LOOP_NONE:
		_fail("Double-jump flip clip does not loop")
		return
	if (
		presentation.flip_source_root_motion_track_count
		!= presentation.flip_root_motion_tracks_removed
	):
		_fail("All source root-motion tracks are removed from the forward flip")
		return
	if presentation.flip_source_root_rotation_track_count != 0:
		_fail("Forward flip has no presentation-root rotation tracks to override facing")
		return
	print(
		"Ch44 skeleton bones=%d root_forward_axis=%s mesh_size=%s surfaces=%d"
		% [
			presentation.character_skeleton.get_bone_count(),
			presentation.character_root.transform.basis.z,
			character_mesh.get_aabb().size,
			character_mesh.mesh.get_surface_count()
		]
	)
	var flip_report_format := (
		"Forward flip source_clip=%s source_length=%.3f source_loop_mode=%d "
		+ "source_skeleton_bones=%d source_root_motion_tracks=%d "
		+ "source_root_rotation_tracks=%d retargeted_length=%.3f tracks=%d "
		+ "root_motion_tracks_removed=%d retargeted_loop_mode=%d"
	)
	print(
		flip_report_format
		% [
			presentation.flip_source_animation_name,
			presentation.flip_source_animation_length,
			presentation.flip_source_loop_mode,
			presentation.flip_source_skeleton_bone_count,
			presentation.flip_source_root_motion_track_count,
			presentation.flip_source_root_rotation_track_count,
			flip_animation.length,
			flip_animation.get_track_count(),
			presentation.flip_root_motion_tracks_removed,
			flip_animation.loop_mode
		]
	)
	for surface_index in range(character_mesh.mesh.get_surface_count()):
		var surface_material: Material = character_mesh.get_active_material(surface_index)
		if surface_material == null:
			_fail("Ch44 surface %d has an imported material" % surface_index)
			return
		print(
			"Ch44 material surface=%d name=%s type=%s"
			% [
				surface_index,
				surface_material.resource_name,
				surface_material.get_class()
			]
		)
	for animation_name in animation_library.get_animation_list():
		var animation: Animation = animation_library.get_animation(animation_name)
		print(
			"Retargeted animation %s length=%.3f tracks=%d"
			% [animation_name, animation.length, animation.get_track_count()]
		)
		for track_index in range(animation.get_track_count()):
			var track_path: NodePath = animation.track_get_path(track_index)
			if (
				animation.track_get_type(track_index) == Animation.TYPE_POSITION_3D
				and track_path.get_subname_count() > 0
				and track_path.get_subname(0) == Presentation.MIXAMO_HIPS_BONE
			):
				_fail("Retargeted %s clip has no root-motion hips translation" % animation_name)
				return
	for track_index in range(flip_animation.get_track_count()):
		var track_path: NodePath = flip_animation.track_get_path(track_index)
		if (
			flip_animation.track_get_type(track_index) == Animation.TYPE_POSITION_3D
			and track_path.get_subname_count() > 0
			and track_path.get_subname(0) in ["mixamorig_Hips", "mixamorig_Root"]
		):
			_fail("Forward flip has no root-motion bone translation")
			return
		if (
			flip_animation.track_get_type(track_index) == Animation.TYPE_ROTATION_3D
			and track_path.get_name_count() <= 1
			and track_path.get_subname_count() == 1
			and track_path.get_subname(0) == "rotation"
		):
			_fail("Forward flip has no presentation-root rotation track")
			return

	if not state_machine.has_node(Presentation.DOUBLE_JUMP_FLIP_STATE):
		_fail("AnimationTree contains the dedicated double-jump flip state")
		return
	presentation.update_presentation(
		1.0 / 60.0,
		Vector3(0.0, 9.0, 0.0),
		false,
		"none",
		false,
		"jump",
		Vector2.ZERO
	)
	presentation.animation_tree.advance(0.25)
	if presentation.get_active_animation_state() == Presentation.DOUBLE_JUMP_FLIP_STATE:
		_fail("Grounded/first jump does not activate the double-jump flip")
		return
	if presentation.get_active_animation_state() != "jump":
		_fail("Grounded/first jump selects the normal jump presentation")
		return
	presentation.reset_presentation()
	presentation.update_presentation(
		1.0 / 60.0,
		Vector3(0.0, 9.0, 0.0),
		false,
		"none",
		false,
		"wall_jump",
		Vector2.ZERO
	)
	presentation.animation_tree.advance(0.25)
	if presentation.get_active_animation_state() == Presentation.DOUBLE_JUMP_FLIP_STATE:
		_fail("Wall jump does not activate the forward flip")
		return
	presentation.reset_presentation()
	presentation.update_presentation(
		1.0 / 60.0,
		Vector3(0.0, 9.0, 0.0),
		false,
		"none",
		true,
		"web_climb",
		Vector2.ZERO
	)
	presentation.animation_tree.advance(0.25)
	if presentation.get_active_animation_state() != "swing":
		_fail("Web climbing keeps the swing state and never activates the flip")
		return
	presentation.reset_presentation()
	presentation.update_presentation(
		1.0 / 60.0,
		Vector3(0.0, 0.0, -10.0),
		false,
		"none",
		true,
		"none",
		Vector2.ZERO
	)
	presentation.animation_tree.advance(0.25)
	presentation.update_presentation(
		1.0 / 60.0,
		Vector3(0.0, 0.0, -10.0),
		false,
		"none",
		false,
		"none",
		Vector2.ZERO
	)
	presentation.animation_tree.advance(0.25)
	if presentation.get_active_animation_state() != "swing_release":
		_fail("Swing release uses its presentation state and never activates the flip")
		return
	presentation.reset_presentation()
	presentation.animation_tree.advance(0.25)
	presentation.update_presentation(
		1.0 / 60.0,
		Vector3(0.0, 9.0, 0.0),
		false,
		"none",
		false,
		"double_jump",
		Vector2.ZERO
	)
	presentation.animation_tree.advance(0.25)
	if presentation.get_active_animation_state() != Presentation.DOUBLE_JUMP_FLIP_STATE:
		_fail("Successful airborne double jump enters the forward flip exactly once")
		return
	var flip_duration: float = flip_animation.length
	var elapsed_flip_time := 0.0
	while elapsed_flip_time < flip_duration + 0.2:
		presentation.update_presentation(
			1.0 / 60.0,
			Vector3(0.0, -2.0, 0.0),
			false,
			"none",
			false,
			"none",
			Vector2.ZERO
		)
		presentation.animation_tree.advance(1.0 / 60.0)
		elapsed_flip_time += 1.0 / 60.0
	if presentation.get_active_animation_state() != "fall":
		_fail("Completed non-looping flip transitions to fall while airborne")
		return
	presentation.reset_presentation()
	presentation.update_presentation(
		1.0 / 60.0,
		Vector3(0.0, 9.0, 0.0),
		false,
		"none",
		false,
		"double_jump",
		Vector2.ZERO
	)
	presentation.animation_tree.advance(0.25)
	if presentation.get_active_animation_state() != Presentation.DOUBLE_JUMP_FLIP_STATE:
		_fail("Flip can be triggered again only by a new consumed double jump")
		return
	presentation.update_presentation(
		1.0 / 60.0,
		Vector3(0.0, 9.0, 0.0),
		false,
		"none",
		false,
		"none",
		Vector2.ZERO
	)
	presentation.animation_tree.advance(0.25)
	var airborne_before_landing: bool = presentation.previous_airborne
	presentation.update_presentation(
		1.0 / 60.0,
		Vector3(0.0, 9.0, 0.0),
		true,
		"none",
		false,
		"none",
		Vector2.ZERO
	)
	presentation.animation_tree.advance(0.25)
	if presentation.get_active_animation_state() != "landing":
		_fail(
			"Landing overrides an active double-jump flip "
			+ "(current state: %s, was airborne: %s)"
			% [
				presentation.get_active_animation_state(),
				airborne_before_landing
			]
		)
		return
	presentation.reset_presentation()
	presentation.animation_tree.advance(0.25)
	if presentation.get_active_animation_state() != "idle":
		_fail("Reset leaves the forward-flip state")
		return
	if not is_equal_approx(presentation.model_orientation_root.rotation.y, PI):
		_fail("Reset preserves the one-time model-forward correction")
		return
	presentation.update_presentation(
		1.0 / 60.0,
		Vector3(0.0, 9.0, 0.0),
		false,
		"wall_crawl",
		false,
		"double_jump",
		Vector2(1.0, 0.0)
	)
	presentation.animation_tree.advance(0.25)
	if presentation.get_active_animation_state() == Presentation.DOUBLE_JUMP_FLIP_STATE:
		_fail("Wall traversal takes priority over a flip event")
		return
	presentation.update_presentation(
		1.0 / 60.0,
		Vector3(0.0, 9.0, 0.0),
		false,
		"none",
		true,
		"double_jump",
		Vector2.ZERO
	)
	presentation.animation_tree.advance(0.25)
	if presentation.get_active_animation_state() != "swing":
		_fail("Web attachment overrides the flip with the swing state")
		return

	presentation.update_presentation(
		1.0 / 60.0,
		Vector3(0.0, 0.0, -10.0),
		false,
		"none",
		false,
		"none",
		Vector2.ZERO
	)
	presentation.animation_tree.advance(0.1)
	if not presentation.animation_tree.active:
		_fail("AnimationTree evaluates retargeted presentation clips")
		return
	presentation.queue_free()
	print("Mixamo hero presentation tests passed.")
	quit(0)

func _fail(test_name: String) -> void:
	push_error("Mixamo hero presentation test failed: " + test_name)
	quit(1)
