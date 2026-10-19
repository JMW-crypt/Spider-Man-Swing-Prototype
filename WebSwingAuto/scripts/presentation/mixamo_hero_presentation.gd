class_name MixamoHeroPresentation
extends Node3D

const CHARACTER_SCENE_PATH := "res://local_reference/Character/Ch44_nonPBR.fbx"
const ANIMATION_ROOT_PATH := "res://local_reference/Animations/ActionAdventure/"
const ANIMATION_SOURCES := {
	"idle": "idle.fbx",
	"walk": "walking.fbx",
	"run": "running.fbx",
	"jump": "jumping up.fbx",
	"fall": "falling idle.fbx",
	"landing": "hard landing.fbx",
	"crawl_left": "crouched sneaking left.fbx",
	"crawl_right": "crouched sneaking right.fbx",
	"swing_release": "jumping up.fbx"
}
const TRAVERSAL_STATES := [
	"idle",
	"run",
	"sprint",
	"jump",
	"fall",
	"landing",
	"wall_crawl",
	"wall_run",
	"swing",
	"swing_release"
]
const MIXAMO_HIPS_BONE := "mixamorig_Hips"
const MIXAMO_RIGHT_HAND_BONE := "mixamorig_RightHand"
const ANIMATION_LIBRARY_NAME := "mixamo"
const RUN_BLEND_PATH := "parameters/run/blend_position"
const WALL_CRAWL_BLEND_PATH := "parameters/wall_crawl/blend_position"
const SPRINT_ANIMATION_SPEED_SCALE := 1.25

var character_root: Node3D
var character_skeleton: Skeleton3D
var character_animation_player: AnimationPlayer
var animation_tree: AnimationTree
var state_playback: AnimationNodeStateMachinePlayback
var web_hand_attachment: BoneAttachment3D
var visual_lean := Vector3.ZERO
var previous_airborne := false
var previous_web_attached := false

func initialize() -> bool:
	var character_scene := ResourceLoader.load(CHARACTER_SCENE_PATH) as PackedScene
	if character_scene == null:
		push_warning("Mixamo character scene is unavailable; using the procedural character.")
		return false

	character_root = character_scene.instantiate() as Node3D
	if character_root == null:
		push_error("The Mixamo character scene root is not a Node3D.")
		return false
	character_root.name = "Ch44Visual"
	character_root.position.y = -0.95
	add_child(character_root)

	character_skeleton = character_root.find_child("Skeleton3D", true, false) as Skeleton3D
	character_animation_player = character_root.find_child(
		"AnimationPlayer",
		true,
		false
	) as AnimationPlayer
	if character_skeleton == null or character_animation_player == null:
		push_error("The Mixamo character scene is missing its Skeleton3D or AnimationPlayer.")
		character_root.queue_free()
		character_root = null
		return false

	character_animation_player.root_node = NodePath("..")
	if not _build_retargeted_animation_library():
		character_root.queue_free()
		character_root = null
		return false
	if not _create_web_hand_attachment():
		character_root.queue_free()
		character_root = null
		return false
	_create_animation_tree()
	return true

func _build_retargeted_animation_library() -> bool:
	var animation_library := AnimationLibrary.new()
	for animation_name in ANIMATION_SOURCES:
		var source_path: String = ANIMATION_ROOT_PATH + ANIMATION_SOURCES[animation_name]
		var source_scene := ResourceLoader.load(source_path) as PackedScene
		if source_scene == null:
			push_error("Could not import Mixamo animation source: " + source_path)
			return false
		var source_root := source_scene.instantiate()
		var source_player := source_root.find_child(
			"AnimationPlayer",
			true,
			false
		) as AnimationPlayer
		if source_player == null or not source_player.has_animation(&"mixamo_com"):
			push_error("Mixamo animation source has no 'mixamo_com' clip: " + source_path)
			source_root.free()
			return false
		var source_animation := source_player.get_animation(&"mixamo_com")
		var retargeted_animation := source_animation.duplicate(true) as Animation
		source_root.free()
		if retargeted_animation == null:
			push_error("Could not duplicate Mixamo animation: " + source_path)
			return false
		_strip_root_motion(retargeted_animation)
		if not _animation_tracks_match_skeleton(retargeted_animation, source_path):
			return false
		retargeted_animation.loop_mode = (
			Animation.LOOP_LINEAR
			if animation_name in ["idle", "walk", "run", "fall", "crawl_left", "crawl_right"]
			else Animation.LOOP_NONE
		)
		var add_error := animation_library.add_animation(animation_name, retargeted_animation)
		if add_error != OK:
			push_error("Could not add retargeted Mixamo animation '%s' (error %d)." % [
				animation_name,
				add_error
			])
			return false
	var library_error := character_animation_player.add_animation_library(
		ANIMATION_LIBRARY_NAME,
		animation_library
	)
	if library_error != OK:
		push_error("Could not attach the retargeted Mixamo animation library (error %d)." % library_error)
		return false
	return true

static func _strip_root_motion(animation: Animation) -> int:
	var removed_track_count := 0
	for track_index in range(animation.get_track_count() - 1, -1, -1):
		var track_path: NodePath = animation.track_get_path(track_index)
		if (
			animation.track_get_type(track_index) == Animation.TYPE_POSITION_3D
			and track_path.get_subname_count() > 0
			and track_path.get_subname(0) == MIXAMO_HIPS_BONE
		):
			animation.remove_track(track_index)
			removed_track_count += 1
	return removed_track_count

func _animation_tracks_match_skeleton(animation: Animation, source_path: String) -> bool:
	for track_index in range(animation.get_track_count()):
		var track_path: NodePath = animation.track_get_path(track_index)
		if track_path.get_subname_count() == 0:
			continue
		var bone_name: StringName = track_path.get_subname(0)
		if character_skeleton.find_bone(bone_name) < 0:
			push_error(
				"Animation '%s' targets missing Mixamo bone '%s'."
				% [source_path, bone_name]
			)
			return false
	return true

func _create_web_hand_attachment() -> bool:
	if character_skeleton.find_bone(MIXAMO_RIGHT_HAND_BONE) < 0:
		push_error("The Mixamo skeleton does not contain the expected right-hand bone.")
		return false
	web_hand_attachment = BoneAttachment3D.new()
	web_hand_attachment.name = "WebHandAttachment"
	web_hand_attachment.bone_name = MIXAMO_RIGHT_HAND_BONE
	web_hand_attachment.position = Vector3(0.0, 0.0, -0.06)
	character_skeleton.add_child(web_hand_attachment)
	return true

func _create_animation_tree() -> void:
	var state_machine := AnimationNodeStateMachine.new()
	state_machine.add_node(
		"idle",
		_animation_node("mixamo/idle"),
		Vector2(0.0, 0.0)
	)
	var locomotion := AnimationNodeBlendSpace1D.new()
	locomotion.min_space = 0.0
	locomotion.max_space = 1.0
	locomotion.add_blend_point(_animation_node("mixamo/walk"), 0.0, -1, "walk")
	locomotion.add_blend_point(_animation_node("mixamo/run"), 1.0, -1, "run")
	state_machine.add_node("run", locomotion, Vector2(1.0, 0.0))
	state_machine.add_node(
		"sprint",
		_scaled_animation_node("mixamo/run"),
		Vector2(1.0, -1.0)
	)
	state_machine.add_node(
		"jump",
		_animation_node("mixamo/jump"),
		Vector2(2.0, -1.0)
	)
	state_machine.add_node(
		"fall",
		_animation_node("mixamo/fall"),
		Vector2(2.0, 0.0)
	)
	state_machine.add_node(
		"landing",
		_animation_node("mixamo/landing"),
		Vector2(2.0, 1.0)
	)
	var wall_crawl := AnimationNodeBlendSpace1D.new()
	wall_crawl.min_space = -1.0
	wall_crawl.max_space = 1.0
	wall_crawl.add_blend_point(
		_animation_node("mixamo/crawl_left"),
		-1.0,
		-1,
		"crawl_left"
	)
	wall_crawl.add_blend_point(
		_animation_node("mixamo/crawl_right"),
		1.0,
		-1,
		"crawl_right"
	)
	state_machine.add_node("wall_crawl", wall_crawl, Vector2(0.0, 1.0))
	state_machine.add_node(
		"wall_run",
		_animation_node("mixamo/run"),
		Vector2(-1.0, 1.0)
	)
	state_machine.add_node(
		"swing",
		_animation_node("mixamo/fall"),
		Vector2(-2.0, 0.0)
	)
	state_machine.add_node(
		"swing_release",
		_animation_node("mixamo/swing_release"),
		Vector2(-2.0, 1.0)
	)

	state_machine.add_transition(
		"Start",
		"idle",
		_state_transition(0.0)
	)
	for from_state in TRAVERSAL_STATES:
		for to_state in TRAVERSAL_STATES:
			if from_state != to_state:
				state_machine.add_transition(
					from_state,
					to_state,
					_state_transition(0.16)
				)

	animation_tree = AnimationTree.new()
	animation_tree.name = "AnimationTree"
	animation_tree.anim_player = NodePath("../AnimationPlayer")
	animation_tree.tree_root = state_machine
	character_root.add_child(animation_tree)
	animation_tree.active = true
	animation_tree.set(
		"parameters/sprint/time_scale/scale",
		SPRINT_ANIMATION_SPEED_SCALE
	)
	state_playback = animation_tree.get("parameters/playback")

func _animation_node(animation_path: String) -> AnimationNodeAnimation:
	var animation_node := AnimationNodeAnimation.new()
	animation_node.animation = animation_path
	return animation_node

func _scaled_animation_node(animation_path: String) -> AnimationNodeBlendTree:
	var blend_tree := AnimationNodeBlendTree.new()
	blend_tree.add_node("animation", _animation_node(animation_path), Vector2.ZERO)
	var time_scale := AnimationNodeTimeScale.new()
	blend_tree.add_node("time_scale", time_scale, Vector2(200.0, 0.0))
	blend_tree.connect_node("time_scale", 0, "animation")
	blend_tree.connect_node("output", 0, "time_scale")
	return blend_tree

func _state_transition(crossfade_time: float) -> AnimationNodeStateMachineTransition:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = crossfade_time
	return transition

func update_presentation(
	delta: float,
	velocity: Vector3,
	on_floor: bool,
	wall_mode: String,
	web_attached: bool,
	space_pressed: bool,
	wall_input: Vector2
) -> void:
	if animation_tree == null or state_playback == null:
		return

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	animation_tree.set(RUN_BLEND_PATH, clampf(horizontal_speed / 18.0, 0.0, 1.0))
	animation_tree.set(WALL_CRAWL_BLEND_PATH, clampf(wall_input.x, -1.0, 1.0))

	var current_state: String = state_playback.get_current_node()
	var target_state := "idle"
	if wall_mode == "wall_run":
		target_state = "wall_run"
	elif wall_mode == "wall_crawl":
		target_state = "wall_crawl"
	elif web_attached:
		target_state = "swing"
	elif previous_web_attached:
		target_state = "swing_release"
	elif not on_floor:
		if space_pressed and velocity.y > 0.0:
			target_state = "jump"
		elif current_state == "jump" and velocity.y > 0.0:
			target_state = "jump"
		elif current_state == "jump" and (
			state_playback.get_current_play_position()
			< state_playback.get_current_length()
		):
			target_state = "jump"
		else:
			target_state = "fall"
	elif previous_airborne:
		target_state = "landing"
	elif current_state == "landing" and (
		state_playback.get_current_play_position()
		< state_playback.get_current_length()
	):
		target_state = "landing"
	elif horizontal_speed > 18.0:
		target_state = "sprint"
	elif horizontal_speed > 0.4:
		target_state = "run"

	if current_state == "swing_release" and (
		state_playback.get_current_play_position()
		< state_playback.get_current_length()
	) and not web_attached and wall_mode.is_empty():
		target_state = "swing_release"
	if target_state != current_state:
		state_playback.travel(target_state)

	_update_visual_lean(delta, velocity, wall_mode, web_attached, wall_input)
	previous_airborne = not on_floor and not web_attached and wall_mode.is_empty()
	previous_web_attached = web_attached

func _update_visual_lean(
	delta: float,
	velocity: Vector3,
	wall_mode: String,
	web_attached: bool,
	wall_input: Vector2
) -> void:
	var target_lean := Vector3.ZERO
	if wall_mode == "wall_run":
		target_lean.x = -0.10
		target_lean.z = -wall_input.x * 0.14
	elif wall_mode == "wall_crawl":
		target_lean.x = -0.04
		target_lean.z = -wall_input.x * 0.08
	elif web_attached:
		target_lean.x = clampf(-velocity.y * 0.008, -0.12, 0.12)
		target_lean.z = clampf(-velocity.x * 0.008, -0.14, 0.14)
	else:
		target_lean.x = clampf(-velocity.y * 0.004, -0.10, 0.10)
	var blend := 1.0 - exp(-8.0 * delta)
	visual_lean = visual_lean.lerp(target_lean, blend)
	if character_root != null:
		character_root.rotation = visual_lean
