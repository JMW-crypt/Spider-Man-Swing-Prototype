shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never;

uniform vec4 outline_color : source_color = vec4(0.035, 0.025, 0.10, 1.0);
uniform float outline_width_px : hint_range(0.5, 4.0) = 2.0;

void vertex() {
	vec4 view_vertex = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec4 clip_vertex = PROJECTION_MATRIX * view_vertex;
	vec3 clip_normal = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xyz;
	vec2 outline_direction = normalize(clip_normal.xy);
	clip_vertex.xy += outline_direction
		* (outline_width_px * 2.0 / VIEWPORT_SIZE)
		* clip_vertex.w;
	POSITION = clip_vertex;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
