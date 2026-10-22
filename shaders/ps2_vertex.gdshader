shader_type spatial;
render_mode vertex_lighting, cull_back;

uniform sampler2D albedo_tex : source_color, filter_nearest;
uniform float snap_res : hint_range(32.0, 512.0) = 160.0;
uniform vec3 tint : source_color = vec3(1.0);

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	clip.xyz /= clip.w;
	clip.xy = floor(clip.xy * snap_res) / snap_res;
	clip.xyz *= clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * tint;
}
