shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform vec3 player_pos = vec3(0.0);
uniform float fade_near : hint_range(0.0, 1000.0) = 60.0;
uniform float fade_far  : hint_range(0.0, 2000.0) = 220.0;
uniform vec4 tint : source_color = vec4(0.4, 0.8, 1.0, 0.55);
uniform float emission_strength : hint_range(0.0, 4.0) = 0.6;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 dxz = world_pos.xz - player_pos.xz;
	float d = length(dxz);
	float a = 1.0 - smoothstep(fade_near, fade_far, d);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * a;
	EMISSION = tint.rgb * emission_strength * a;
}
