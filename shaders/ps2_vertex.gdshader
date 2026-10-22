shader_type spatial;
render_mode vertex_lighting, cull_back;

// PS2-style surface: vertex snapping ("wobble"), nearest-filtered texture,
// per-vertex lighting. COLOR carries MultiMesh instance colors, so the same
// shader works for parts, enemies and pickups.

uniform sampler2D albedo_tex : source_color, filter_nearest, hint_default_white;
uniform float snap_res : hint_range(32.0, 512.0) = 160.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 emission_color : source_color = vec3(0.0);

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	clip.xyz /= clip.w;
	clip.xy = floor(clip.xy * snap_res) / snap_res;
	clip.xyz *= clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * tint * COLOR.rgb;
	EMISSION = emission_color * COLOR.rgb;
}
