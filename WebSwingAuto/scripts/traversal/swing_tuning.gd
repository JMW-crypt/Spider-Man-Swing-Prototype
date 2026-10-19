class_name SwingTuning
extends Resource

# Speeds use Godot units/second, accelerations and forces use units/second^2,
# distances use Godot units, and the wheel rotation step is in degrees.
@export var ground_speed: float = 24.0
@export var air_speed: float = 28.0
@export var ground_acceleration: float = 60.0
@export var air_acceleration: float = 14.0
@export var jump_force: float = 26.0
@export var gravity: float = 32.0

@export var web_range: float = 300.0
@export var web_assist_radius: float = 60.0
@export var web_min_anchor_height: float = 5.0
@export var web_candidate_limit: int = 24
@export var web_visibility_margin: float = 0.25
@export var web_screen_sample_radius: float = 14.0
@export var web_target_refresh_interval: float = 0.15
@export var score_height_weight: float = 0.20
@export var score_forward_weight: float = 0.25
@export var score_momentum_weight: float = 0.30
@export var score_distance_weight: float = 0.25
@export var direct_aim_score_tolerance: float = 0.18
@export var web_climb_speed: float = 22.0

@export var spring_strength: float = 20.0
@export var spring_damping: float = 5.0
@export var max_spring_force: float = 115.0
@export var rope_safety_stretch: float = 1.5
@export var swing_forward_force: float = 30.0
@export var swing_side_force: float = 42.0
@export var swing_reverse_force: float = 24.0
@export var max_swing_speed: float = 82.0
@export var web_attach_yank_impulse: float = 12.0
@export var min_rope_length: float = 7.0

@export var camera_wheel_rotation_step: float = 15.0
@export var camera_yaw_follow_smoothing: float = 7.5
@export var character_turn_speed: float = 1.2
@export var default_camera_distance: float = 14.0
@export var default_camera_height: float = 3.5
@export var default_camera_pitch: float = 0.0
@export var camera_position_smoothing: float = 10.0
@export var camera_collision_margin: float = 0.5
@export var camera_minimum_height: float = 0.75
@export var camera_look_height: float = 1.0
@export var camera_base_fov: float = 82.0
@export var camera_speed_fov_increase: float = 10.0
@export var camera_fov_full_speed: float = 82.0
@export var camera_fov_smoothing: float = 3.5
@export var camera_look_ahead_time: float = 0.16
@export var camera_look_ahead_max_distance: float = 5.0
@export var camera_bank_max_degrees: float = 8.0
@export var camera_bank_turn_rate_scale: float = 0.30
@export var camera_bank_swing_weight: float = 0.22
@export var camera_bank_smoothing: float = 4.0
