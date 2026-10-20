class_name ComicVisualTuning
extends Resource

const TOON_SHADER = preload("res://shaders/comic_toon.gdshader")
const OUTLINE_SHADER = preload("res://shaders/comic_outline.gdshader")

@export_range(0.0, 1.0, 0.01) var saturation_multiplier: float = 1.18
@export_range(0.0, 1.0, 0.01) var ambient_fill_strength: float = 0.34
@export var shadow_tint: Color = Color(0.40, 0.32, 0.66, 1.0)
@export var rim_color: Color = Color(0.35, 0.82, 1.0, 1.0)
@export_range(0.0, 1.0, 0.01) var rim_strength: float = 0.24
@export_range(0.5, 4.0, 0.1) var character_outline_width_px: float = 2.3
@export_range(0.5, 3.0, 0.1) var building_outline_width_px: float = 1.15
@export var character_outline_color: Color = Color(0.035, 0.025, 0.10, 1.0)
@export var building_outline_color: Color = Color(0.055, 0.055, 0.16, 1.0)
@export var ambient_light_color: Color = Color(0.58, 0.62, 0.92, 1.0)
@export_range(0.0, 2.0, 0.01) var ambient_light_energy: float = 0.78
@export var fog_color: Color = Color(0.47, 0.68, 0.91, 1.0)
@export_range(0.0, 0.01, 0.0001) var fog_density: float = 0.00045
@export_range(0.0, 2.0, 0.01) var glow_intensity: float = 0.42
@export_range(0.0, 1.0, 0.01) var glow_bloom: float = 0.10
@export_range(0.5, 2.0, 0.01) var contrast: float = 1.20
@export_range(0.5, 2.0, 0.01) var color_saturation: float = 1.22

var toon_material_cache: Dictionary = {}

func create_toon_material(source_material: Material) -> ShaderMaterial:
	var material_key: int = (
		source_material.get_instance_id()
		if source_material != null
		else 0
	)
	if toon_material_cache.has(material_key):
		return toon_material_cache[material_key] as ShaderMaterial
	var toon_material := ShaderMaterial.new()
	toon_material.shader = TOON_SHADER
	var base_color := Color.WHITE
	var albedo_texture: Texture2D
	if source_material is StandardMaterial3D:
		var standard_material := source_material as StandardMaterial3D
		base_color = standard_material.albedo_color
		albedo_texture = standard_material.albedo_texture
	base_color = _saturate_color(base_color, saturation_multiplier)
	toon_material.set_shader_parameter("base_color", base_color)
	toon_material.set_shader_parameter("albedo_texture", albedo_texture)
	toon_material.set_shader_parameter("use_albedo_texture", albedo_texture != null)
	toon_material.set_shader_parameter("shadow_tint", shadow_tint)
	toon_material.set_shader_parameter("ambient_fill_strength", ambient_fill_strength)
	toon_material.set_shader_parameter("rim_color", rim_color)
	toon_material.set_shader_parameter("rim_strength", rim_strength)
	toon_material_cache[material_key] = toon_material
	return toon_material

func create_outline_material(width_px: float, color: Color) -> ShaderMaterial:
	var outline_material := ShaderMaterial.new()
	outline_material.shader = OUTLINE_SHADER
	outline_material.render_priority = 1
	outline_material.set_shader_parameter("outline_width_px", width_px)
	outline_material.set_shader_parameter("outline_color", color)
	return outline_material

func create_comic_environment(source_environment: Environment) -> Environment:
	var comic_environment := source_environment.duplicate(true) as Environment
	comic_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	comic_environment.ambient_light_color = ambient_light_color
	comic_environment.ambient_light_energy = ambient_light_energy
	comic_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	comic_environment.adjustment_enabled = true
	comic_environment.adjustment_brightness = 1.04
	comic_environment.adjustment_contrast = contrast
	comic_environment.adjustment_saturation = color_saturation
	comic_environment.fog_enabled = true
	comic_environment.fog_light_color = fog_color
	comic_environment.fog_light_energy = 0.84
	comic_environment.fog_density = fog_density
	comic_environment.fog_height = 12.0
	comic_environment.fog_height_density = 0.014
	comic_environment.fog_sun_scatter = 0.18
	comic_environment.glow_enabled = true
	comic_environment.glow_intensity = glow_intensity
	comic_environment.glow_bloom = glow_bloom
	comic_environment.glow_hdr_threshold = 1.15
	return comic_environment

func _saturate_color(color: Color, multiplier: float) -> Color:
	return Color.from_hsv(
		color.h,
		clampf(color.s * multiplier, 0.0, 1.0),
		color.v,
		color.a
	)
