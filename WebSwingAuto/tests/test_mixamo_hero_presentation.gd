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
	print(
		"Ch44 skeleton bones=%d mesh_size=%s surfaces=%d"
		% [
			presentation.character_skeleton.get_bone_count(),
			character_mesh.get_aabb().size,
			character_mesh.mesh.get_surface_count()
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

	presentation.update_presentation(
		1.0 / 60.0,
		Vector3(0.0, 0.0, -10.0),
		false,
		"none",
		false,
		true,
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
