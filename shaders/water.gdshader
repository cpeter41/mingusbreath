shader_type spatial;
render_mode depth_draw_opaque, cull_disabled;

// Wave parameters — pushed each frame by globals/ocean.gd. Do not hardcode here.
uniform vec4  waves[4];               // (dir.x, dir.y, amplitude, wavelength) per wave
uniform float gravity      = 9.81;
uniform float steepness    = 0.30;    // global Q multiplier; per-wave capped below
uniform float wave_time    = 0.0;
uniform float wave_roughness = 1.0;

// Artist-facing surface appearance — set in material, not driven by Ocean.
uniform vec3  deep_color         : source_color = vec3(0.04, 0.16, 0.30);
uniform vec3  shallow_color      : source_color = vec3(0.18, 0.42, 0.58);
uniform float fresnel_power      : hint_range(1.0, 8.0)  = 4.0;
uniform float specular_strength  : hint_range(0.0, 4.0)  = 1.5;

void vertex() {
	// World-space rest position (mesh plane has no rotation/scale, MODEL only translates).
	vec3 world_rest = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	float total_y  = 0.0;
	vec2  total_xz = vec2(0.0);
	float d_dx     = 0.0;  // ∂(total_y)/∂x
	float d_dz     = 0.0;  // ∂(total_y)/∂z

	for (int i = 0; i < 4; i++) {
		vec2  dir   = waves[i].xy;
		float amp   = waves[i].z;
		float wlen  = waves[i].w;
		float k     = (2.0 * PI) / wlen;
		float omega = sqrt(gravity * k);
		// Per-wave self-intersection cap keeps steep short waves from folding.
		float Q     = min(steepness, 1.0 / max(k * amp, 1e-6));
		float phase = k * dot(dir, world_rest.xz) - omega * wave_time;
		float s     = sin(phase);
		float c     = cos(phase);

		total_y  += amp * s;
		total_xz += dir * (Q * amp * c);

		d_dx += amp * dir.x * k * c;
		d_dz += amp * dir.y * k * c;
	}

	total_y  *= wave_roughness;
	total_xz *= wave_roughness;

	VERTEX.x += total_xz.x;
	VERTEX.y += total_y;
	VERTEX.z += total_xz.y;

	// Normal from vertical-height gradient. Slightly inconsistent with horizontally-displaced
	// position, but error is bounded by steepness*amplitude — invisible at our scales.
	NORMAL = normalize(vec3(-d_dx * wave_roughness, 1.0, -d_dz * wave_roughness));
}

void fragment() {
	float fres = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), fresnel_power);
	ALBEDO     = mix(shallow_color, deep_color, 1.0 - fres);
	ROUGHNESS  = 0.10;
	METALLIC   = 0.0;
	SPECULAR   = specular_strength;
}
