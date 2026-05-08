shader_type sky;

// --- Color stops (linear-space colors) -----------------------------------
uniform vec3 day_zenith    : source_color = vec3(0.18, 0.45, 0.85);
uniform vec3 day_horizon   : source_color = vec3(0.75, 0.88, 0.97);
uniform vec3 dusk_zenith   : source_color = vec3(0.20, 0.18, 0.45);
uniform vec3 dusk_horizon  : source_color = vec3(0.95, 0.45, 0.20);
uniform vec3 night_zenith  : source_color = vec3(0.02, 0.03, 0.08);
uniform vec3 night_horizon : source_color = vec3(0.05, 0.07, 0.14);

// --- Gradient + sun shape -------------------------------------------------
uniform float horizon_softness : hint_range(0.0, 4.0) = 1.4;
uniform float sun_disc_size    : hint_range(0.0, 0.2) = 0.0;   // 0 disables disc (keep billboard sun)
uniform float sun_glow_falloff : hint_range(1.0, 256.0) = 24.0;
uniform float sun_glow_strength: hint_range(0.0, 4.0) = 0.6;

// Triangle window centered at `c` with half-width `w`. 1 at center, 0 outside.
float tri_window(float x, float c, float w) {
	return clamp(1.0 - abs(x - c) / w, 0.0, 1.0);
}

void sky() {
	float sun_y = LIGHT0_DIRECTION.y;   // +1 = sun overhead, -1 = below horizon

	// Phase weights driven by sun elevation. Dusk peaks near horizon (both sunrise and sunset).
	float w_day   = smoothstep(-0.05, 0.25, sun_y);
	float w_night = 1.0 - smoothstep(-0.20, 0.05, sun_y);
	float w_dusk  = tri_window(sun_y, 0.0, 0.20);
	float total   = w_day + w_dusk + w_night + 1e-5;
	w_day   /= total;
	w_dusk  /= total;
	w_night /= total;

	vec3 zen = w_day * day_zenith  + w_dusk * dusk_zenith  + w_night * night_zenith;
	vec3 hor = w_day * day_horizon + w_dusk * dusk_horizon + w_night * night_horizon;

	// Vertical gradient from horizon (EYEDIR.y = 0) to zenith (EYEDIR.y = 1).
	float h = pow(clamp(EYEDIR.y, 0.0, 1.0), 1.0 / max(horizon_softness, 0.0001));
	vec3 col = mix(hor, zen, h);

	// Sun disc + glow toward LIGHT0_DIRECTION.
	if (LIGHT0_ENABLED) {
		float sun_dot = dot(EYEDIR, LIGHT0_DIRECTION);
		float disc = sun_disc_size > 0.0
			? smoothstep(1.0 - sun_disc_size, 1.0 - sun_disc_size * 0.5, sun_dot)
			: 0.0;
		float glow = pow(max(sun_dot, 0.0), sun_glow_falloff);
		col += LIGHT0_COLOR * LIGHT0_ENERGY * (disc * 8.0 + glow * sun_glow_strength) * w_day;
	}

	COLOR = col;
}
