shader_type spatial;
render_mode specular_disabled;

uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform bool use_albedo_texture = false;
uniform vec4 shadow_tint : source_color = vec4(0.30, 0.24, 0.52, 1.0);
uniform float ambient_fill_strength : hint_range(0.0, 1.0) = 0.20;
uniform vec4 rim_color : source_color = vec4(0.35, 0.82, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.16;

void fragment() {
	vec4 texture_color = use_albedo_texture
		? texture(albedo_texture, UV)
		: vec4(1.0);
	ALBEDO = base_color.rgb * texture_color.rgb;
	ROUGHNESS = 1.0;
	EMISSION = ALBEDO * shadow_tint.rgb * ambient_fill_strength;
	float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 3.0);
	EMISSION += rim_color.rgb * rim * rim_strength;
}

void light() {
	float illuminated = max(dot(normalize(NORMAL), normalize(LIGHT)), 0.0)
		* ATTENUATION;
	float bands = 0.28
		+ smoothstep(0.20, 0.29, illuminated) * 0.42
		+ smoothstep(0.63, 0.72, illuminated) * 0.34;
	float shadow_blend = smoothstep(0.05, 0.24, illuminated);
	vec3 toon_light = mix(shadow_tint.rgb, vec3(bands), shadow_blend);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * toon_light * ATTENUATION;
}
