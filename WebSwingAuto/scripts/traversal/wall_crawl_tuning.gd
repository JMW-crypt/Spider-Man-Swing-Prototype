class_name WallCrawlTuning
extends Resource

# Distances use world units, speeds units/second, accelerations units/second^2,
# smoothing rates inverse seconds, times seconds, angles degrees, and ratios fractions.
@export var enabled: bool = true

@export_group("Detection")
@export var wall_detection_distance: float = 1.35
@export var wall_contact_distance: float = 0.72
@export var wall_probe_radius: float = 0.35
@export var wall_collision_mask: int = 1
@export_range(0.0, 90.0, 0.1) var minimum_wall_steepness_degrees: float = 55.0
@export_range(0.0, 1.0, 0.01) var maximum_wall_normal_vertical_component: float = 0.55
@export var minimum_wall_approach_speed: float = 0.25
@export var corner_probe_distance: float = 1.25
@export var ledge_probe_distance: float = 0.55

@export_group("Wall Crawling")
@export var maximum_vertical_crawl_speed: float = 11.0
@export var maximum_lateral_crawl_speed: float = 13.5
@export var crawl_acceleration: float = 70.0
@export var crawl_deceleration: float = 90.0
@export var stationary_adhesion_strength: float = 40.0
@export var contact_correction_strength: float = 40.0
@export var maximum_contact_correction_speed: float = 18.0
@export var wall_normal_smoothing: float = 10.0
@export var orientation_smoothing: float = 9.0
@export var detach_clearance: float = 0.2

@export_group("Wall Running")
@export var minimum_wall_run_entry_speed: float = 11.0
@export var maximum_wall_run_speed: float = 30.0
@export var maximum_wall_run_duration: float = 0.9
@export var wall_run_downward_acceleration: float = 3.5
@export_range(0.0, 1.0, 0.01) var wall_run_tangential_speed_retention: float = 0.94
@export var wall_run_steering_influence: float = 8.0
@export var wall_run_to_crawl_hold_threshold: float = 0.22
@export var wall_exit_reacquisition_cooldown: float = 0.45
@export var maximum_corner_transition_degrees: float = 50.0

@export_group("Wall Jump")
@export var wall_jump_outward_speed: float = 9.0
@export var wall_jump_upward_speed: float = 8.0
@export_range(0.0, 1.0, 0.01) var wall_jump_tangential_momentum_retention: float = 0.8
@export var wall_reacquisition_cooldown: float = 0.3
@export var preserve_double_jump_after_wall_jump: bool = true

@export_group("Safety")
@export var wall_lost_grace_duration: float = 0.12
@export var maximum_adhesion_correction_per_physics_tick: float = 0.18
@export var penetration_rejection_threshold: float = 0.25
