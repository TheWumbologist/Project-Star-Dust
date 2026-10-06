shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// A rift tear: a jagged, flickering crack of light standing upright and
// turned to face the camera (around the vertical axis only). With
// floor_glow on, it draws the soft pool of light under the tear instead.

uniform vec4 core_color : source_color = vec4(1.0, 0.75, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.85, 0.25, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.3, 0.55, 1.0, 1.0);
uniform float intensity = 1.6;
uniform bool floor_glow = false;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	if (!floor_glow) {
		// Y-axis billboard: keep upright, turn toward the camera.
		vec3 up = MODEL_MATRIX[1].xyz;
		vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz);
		vec3 right = normalize(cross(up, to_cam)) * length(MODEL_MATRIX[0].xyz);
		vec3 fwd = normalize(cross(right, up)) * length(MODEL_MATRIX[2].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right, 0.0), vec4(up, 0.0), vec4(fwd, 0.0), MODEL_MATRIX[3]);
	}
}

void fragment() {
	float t = TIME;
	vec2 uv = UV * 2.0 - 1.0;
	if (floor_glow) {
		float r = length(uv);
		float swirl = fbm(vec2(atan(uv.y, uv.x) * 2.0 + t * 0.6, r * 3.0 - t * 0.8));
		float a = (1.0 - smoothstep(0.0, 1.0, r)) * (0.55 + 0.45 * swirl);
		ALBEDO = mix(glow_color.rgb, edge_color.rgb, swirl) * a * intensity * 0.6;
		ALPHA = 1.0;
	} else {
		float y = -uv.y;
		// Pointed at both ends.
		float taper = 1.0 - smoothstep(0.45, 1.0, abs(y));
		float bend = (fbm(vec2(y * 2.5, t * 0.5)) - 0.5) * 0.7 + (fbm(vec2(y * 9.0, t * 1.6)) - 0.5) * 0.22;
		float d = abs(uv.x - bend * taper);
		float pulse = 0.85 + 0.15 * sin(t * 5.0 + y * 3.0);
		float width = (0.08 + 0.12 * pulse) * taper;
		float core = 1.0 - smoothstep(width * 0.25, width, d);
		float glow = exp(-d * 7.0 / (0.25 + taper)) * taper;
		float flicker = fbm(vec2(uv.x * 4.0 + t, y * 6.0 - t * 2.0));
		vec3 col = mix(edge_color.rgb, core_color.rgb, smoothstep(width, width * 0.3, d)) * core * 1.4 + mix(glow_color.rgb, edge_color.rgb, flicker) * glow * (0.7 + 0.6 * flicker);
		// Motes drifting up along the crack.
		vec2 mote_uv = vec2(uv.x * 6.0, y * 5.0 - t * 1.4);
		float mote = step(0.94, hash(floor(mote_uv))) * (1.0 - smoothstep(0.0, 0.35, length(fract(mote_uv) - 0.5)));
		col += edge_color.rgb * mote * glow * 2.0;
		ALBEDO = col * intensity;
		ALPHA = 1.0;
	}
}
