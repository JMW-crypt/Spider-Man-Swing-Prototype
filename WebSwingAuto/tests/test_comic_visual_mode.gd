extends SceneTree

const WorldScript = preload("res://scripts/world.gd")

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var world := WorldScript.new()
	root.add_child(world)
	if not world.comic_visual_mode_enabled:
		_fail("Comic mode is active by default")
		return
	if world.world_environment_node.environment != world.comic_environment:
		_fail("Comic mode activates its environment profile")
		return
	if world.comic_city_outline_instances.is_empty():
		_fail("Comic mode creates major-building outlines")
		return
	if not (
		world.comic_city_meshes[0].material_override is ShaderMaterial
	):
		_fail("Comic mode applies the toon shader to building surfaces")
		return
	if world.mixamo_hero_presentation == null:
		_fail("Imported character presentation is available for comic styling")
		return
	if world.mixamo_hero_presentation.comic_outline_instances.is_empty():
		_fail("Comic mode creates character outlines")
		return
	for outline_instance in world.mixamo_hero_presentation.comic_outline_instances:
		if not outline_instance.visible:
			_fail("Character outlines are visible while comic mode is active")
			return
		var source_name: String = outline_instance.name.trim_suffix("ComicOutline")
		var source_mesh := world.mixamo_hero_presentation.character_root.find_child(
			source_name,
			true,
			false
		) as MeshInstance3D
		if (
			source_mesh == null
			or outline_instance.mesh != source_mesh.mesh
			or outline_instance.skeleton != source_mesh.skeleton
		):
			_fail("Character outline follows the source mesh and its animated skeleton")
			return
	var character_mesh := (
		world.mixamo_hero_presentation.character_root.find_child(
			"Ch44",
			true,
			false
		) as MeshInstance3D
	)
	if (
		character_mesh == null
		or not (character_mesh.get_active_material(0) is ShaderMaterial)
	):
		_fail("Comic mode applies toon shading to the imported hero")
		return

	world.player.velocity = Vector3(12.0, 3.0, -7.0)
	var original_position: Vector3 = world.player.global_position
	var original_velocity: Vector3 = world.player.velocity
	var f4_event := InputEventKey.new()
	f4_event.keycode = KEY_F4
	f4_event.pressed = true
	world._input(f4_event)
	if world.comic_visual_mode_enabled:
		_fail("F4 toggle switches back to current visual mode")
		return
	if world.world_environment_node.environment != world.current_environment:
		_fail("Current mode restores the original environment profile")
		return
	if not (
		world.comic_city_meshes[0].material_override is StandardMaterial3D
	):
		_fail("Current mode restores the original building material")
		return
	if not world.player.velocity.is_equal_approx(original_velocity):
		_fail("Visual mode switching preserves player velocity")
		return
	if not world.player.global_position.is_equal_approx(original_position):
		_fail("Visual mode switching preserves player position")
		return
	for outline_instance in world.mixamo_hero_presentation.comic_outline_instances:
		if outline_instance.visible:
			_fail("Character outlines are hidden in current visual mode")
			return
	var outline_count: int = (
		world.mixamo_hero_presentation.comic_outline_instances.size()
	)
	world._input(f4_event)
	if not world.comic_visual_mode_enabled:
		_fail("F4 toggle re-enables comic mode without a reload")
		return
	if (
		world.mixamo_hero_presentation.comic_outline_instances.size()
		!= outline_count
	):
		_fail("Repeated toggles do not add duplicate character outlines")
		return
	print(
		"Comic visual mode tests passed. City outlines=%d character outlines=%d."
		% [
			world.comic_city_outline_instances.size(),
			world.mixamo_hero_presentation.comic_outline_instances.size()
		]
	)
	quit(0)

func _fail(test_name: String) -> void:
	push_error("Comic visual mode test failed: " + test_name)
	quit(1)
