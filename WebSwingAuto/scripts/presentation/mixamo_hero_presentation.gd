class_name MixamoHeroPresentation
extends Node3D

const CHARACTER_SCENE_PATH := "res://local_reference/Character/Ch44_nonPBR.fbx"
const ANIMATION_ROOT_PATH := "res://local_reference/Animations/ActionAdventure/"
const DOUBLE_JUMP_FLIP_ANIMATION_PATH := (
	"res://local_reference/Animations/Extra/RunningForwardFlip.fbx"
)
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
const DOUBLE_JUMP_FLIP_STATE := "double_jump_flip"
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
const MIXAMO_MODEL_FORWARD_YAW_OFFSET := PI
const MIXAMO_HIPS_BONE := "mixamorig_Hips"
const MIXAMO_RIGHT_HAND_BONE := "mixamorig_RightHand"
const ANIMATION_LIBRARY_NAME := "mixamo"
const RUN_BLEND_PATH := "parameters/run/blend_position"
const WALL_CRAWL_BLEND_PATH := "parameters/wall_crawl/blend_position"
const SPRINT_ANIMATION_SPEED_SCALE := 1.25

var character_root: Node3D
var model_orientation_root: Node3D
var character_skeleton: Skeleton3D
var character_animation_player: AnimationPlayer
var animation_tree: AnimationTree
var state_playback: AnimationNodeStateMachinePlayback
var web_hand_attachment: BoneAttachment3D
var visual_lean := Vector3.ZERO
var previous_airborne := false
var previous_web_attached := false
var flip_animation_available := false
var flip_source_animation_name: StringName = &""
var flip_source_animation_length: float = 0.0
var flip_source_loop_mode: int = Animation.LOOP_NONE
var flip_source_skeleton_bone_count: int = 0
var flip_source_root_motion_track_count: int = 0
var flip_source_root_rotation_track_count: int = 0
var flip_root_motion_tracks_removed: int = 0

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
	model_orientation_root = Node3D.new()
	model_orientation_root.name = "ModelForwardCorrection"
	model_orientation_root.rotation.y = MIXAMO_MODEL_FORWARD_YAW_OFFSET
	add_child(model_orientation_root)
	model_orientation_root.add_child(character_root)

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
		model_orientation_root.queue_free()
		model_orientation_root = null
		character_root = null
		return false
	if not _create_web_hand_attachment():
		model_orientation_root.queue_free()
		model_orientation_root = null
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
		push_error(
			"Could not attach the retargeted Mixamo animation library (error %d)."
			% library_error
		)
		return false
	_load_double_jump_flip_animation(animation_library)
	return true

func _load_double_jump_flip_animation(animation_library: AnimationLibrary) -> void:
	var source_scene := ResourceLoader.load(
		DOUBLE_JUMP_FLIP_ANIMATION_PATH
	) as PackedScene
	if source_scene == null:
		push_warning(
			"Double-jump flip animation is unavailable; using the existing airborne presentation."
		)
		return
	var source_root := source_scene.instantiate()
	var source_player := source_root.find_child(
		"AnimationPlayer",
		true,
		false
	) as AnimationPlayer
	if source_player == null:
		push_warning(
			"Double-jump flip source has no AnimationPlayer; using the existing airborne presentation."
		)
		source_root.free()
		return
	var source_animation_name: StringName = &"mixamo_com"
	if not source_player.has_animation(source_animation_name):
		var animation_list := source_player.get_animation_list()
		if animation_list.is_empty():
			push_warning(
				"Double-jump flip source has no animation clips; using the existing airborne presentation."
			)
			source_root.free()
			return
		source_animation_name = animation_list[0]
	var source_animation := source_player.get_animation(source_animation_name)
	var retargeted_animation := source_animation.duplicate(true) as Animation
	flip_source_animation_name = source_animation_name
	flip_source_animation_length = source_animation.length
	flip_source_loop_mode = source_animation.loop_mode
	for track_index in range(source_animation.get_track_count()):
		if _is_root_motion_track(source_animation, track_index):
			flip_source_root_motion_track_count += 1
			if (
				source_animation.track_get_type(track_index)
				== Animation.TYPE_ROTATION_3D
			):
				flip_source_root_rotation_track_count += 1
	var source_skeleton := source_root.find_child(
		"Skeleton3D",
		true,
		false
	) as Skeleton3D
	if source_skeleton != null:
		flip_source_skeleton_bone_count = source_skeleton.get_bone_count()
	source_root.free()
	if retargeted_animation == null:
		push_warning(
			"Could not duplicate the double-jump flip animation; using the existing airborne presentation."
		)
		return
	if not _animation_tracks_match_skeleton(
		retargeted_animation,
		DOUBLE_JUMP_FLIP_ANIMATION_PATH,
		false
	):
		push_warning(
			"Double-jump flip skeleton is incompatible; using the existing airborne presentation."
		)
		return
	flip_root_motion_tracks_removed = _strip_root_motion(retargeted_animation)
	retargeted_animation.loop_mode = Animation.LOOP_NONE
	var add_error := animation_library.add_animation(
		DOUBLE_JUMP_FLIP_STATE,
		retargeted_animation
	)
	if add_error != OK:
		push_warning(
			"Could not add the double-jump flip animation (error %d); using the existing airborne presentation."
			% add_error
		)
		return
	flip_animation_available = true

static func _strip_root_motion(animation: Animation) -> int:
	var removed_track_count := 0
	for track_index in range(animation.get_track_count() - 1, -1, -1):
		if _is_root_motion_track(animation, track_index):
			animation.remove_track(track_index)
			removed_track_count += 1
	return removed_track_count

static func _is_root_motion_track(animation: Animation, track_index: int) -> bool:
	var track_path: NodePath = animation.track_get_path(track_index)
	var track_type: int = animation.track_get_type(track_index)
	var is_root_node_track: bool = (
		track_path.get_name_count() <= 1
		and track_path.get_subname_count() == 1
		and track_path.get_subname(0) in ["position", "rotation", "scale"]
	)
	var is_root_bone_translation: bool = (
		track_path.get_subname_count() > 0
		and track_path.get_subname(0) in [MIXAMO_HIPS_BONE, "mixamorig_Root"]
	)
	return (
		track_type == Animation.TYPE_POSITION_3D
		and (is_root_node_track or is_root_bone_translation)
	) or (
		track_type == Animation.TYPE_ROTATION_3D
		and is_root_node_track
	)

func _animation_tracks_match_skeleton(
	animation: Animation,
	source_path: String,
	report_errors: bool = true
) -> bool:
	for track_index in range(animation.get_track_count()):
		var track_path: NodePath = animation.track_get_path(track_index)
		if track_path.get_subname_count() == 0:
			continue
		var bone_name: StringName = track_path.get_subname(0)
		if bone_name in ["position", "rotation", "scale"]:
			continue
		if character_skeleton.find_bone(bone_name) < 0:
			if report_errors:
				push_error(
					"Animation '%s' targets missing Mixamo bone '%s'."
					% [source_path, bone_name]
				)
			else:
				push_warning(
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
	if flip_animation_available:
		state_machine.add_node(
			DOUBLE_JUMP_FLIP_STATE,
			_animation_node("mixamo/" + DOUBLE_JUMP_FLIP_STATE),
			Vector2(3.0, -1.0)
		)

	state_machine.add_transition(
		"Start",
		"idle",
		_state_transition(0.0)
	)
	var traversal_states = TRAVERSAL_STATES.duplicate()
	if flip_animation_available:
		traversal_states.append(DOUBLE_JUMP_FLIP_STATE)
	for from_state in traversal_states:
		for to_state in traversal_states:
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
	jump_event: String,
	wall_input: Vector2,
	wall_tangent_velocity: Vector3 = Vector3.ZERO
) -> void:
	if animation_tree == null or state_playback == null:
		return

	var wall_traversal_active: bool = wall_mode in ["wall_run", "wall_crawl"]
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
	elif (
		jump_event == "double_jump"
		and flip_animation_available
		and not on_floor
	):
		target_state = DOUBLE_JUMP_FLIP_STATE
	elif not on_floor:
		if (
			flip_animation_available
			and current_state == DOUBLE_JUMP_FLIP_STATE
			and state_playback.get_current_play_position()
				< state_playback.get_current_length()
		):
			target_state = DOUBLE_JUMP_FLIP_STATE
		elif current_state == DOUBLE_JUMP_FLIP_STATE:
			target_state = "fall"
		elif jump_event in ["jump", "wall_jump"] and velocity.y > 0.0:
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
	) and not web_attached and not wall_traversal_active:
		target_state = "swing_release"
	if target_state != current_state:
		state_playback.travel(target_state)

	_update_visual_lean(
		delta,
		velocity,
		wall_mode,
		web_attached,
		wall_tangent_velocity
	)
	previous_airborne = not on_floor and not web_attached and not wall_traversal_active
	previous_web_attached = web_attached

func _update_visual_lean(
	delta: float,
	velocity: Vector3,
	wall_mode: String,
	web_attached: bool,
	wall_tangent_velocity: Vector3
) -> void:
	var target_lean := Vector3.ZERO
	if wall_mode == "wall_run":
		target_lean.x = -0.10
		var local_tangent_velocity: Vector3 = (
			character_root.global_transform.basis.inverse()
			* wall_tangent_velocity
		)
		target_lean.z = clampf(local_tangent_velocity.x / 30.0, -1.0, 1.0) * 0.14
	elif wall_mode == "wall_crawl":
		target_lean = Vector3.ZERO
	elif web_attached:
		target_lean.x = clampf(-velocity.y * 0.008, -0.12, 0.12)
		target_lean.z = clampf(-velocity.x * 0.008, -0.14, 0.14)
	else:
		target_lean.x = clampf(-velocity.y * 0.004, -0.10, 0.10)
	var blend := 1.0 - exp(-8.0 * delta)
	visual_lean = visual_lean.lerp(target_lean, blend)
	if character_root != null:
		character_root.rotation = visual_lean

func get_active_animation_state() -> String:
	if state_playback == null:
		return "unavailable"
	return state_playback.get_current_node()

func get_flip_normalized_time() -> float:
	if (
		not flip_animation_available
		or get_active_animation_state() != DOUBLE_JUMP_FLIP_STATE
	):
		return 0.0
	var animation_length: float = state_playback.get_current_length()
	if animation_length <= 0.0:
		return 0.0
	return clampf(
		state_playback.get_current_play_position() / animation_length,
		0.0,
		1.0
	)

func reset_presentation() -> void:
	previous_airborne = false
	previous_web_attached = false
	visual_lean = Vector3.ZERO
	if character_root != null:
		character_root.rotation = Vector3.ZERO
	if state_playback != null:
		state_playback.start("idle")
