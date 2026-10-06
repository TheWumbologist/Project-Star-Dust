// Deep-space backdrop drawn on a big plane far below the flight plane:
// drifting nebula clouds in rift purple, teal and ember, plus two layers
// of stars. Pinned to world space so it parallaxes behind the action.
// Cheap: four octaves of value noise, no textures.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform vec3 deep_color : source_color = vec3(0.015, 0.01, 0.04);
uniform vec3 cloud_a : source_color = vec3(0.32, 0.08, 0.45);
uniform vec3 cloud_b : source_color = vec3(0.05, 0.28, 0.38);
uniform vec3 ember : source_color = vec3(0.7, 0.3, 0.08);
uniform float scale = 0.006;
uniform float brightness = 1.35;
uniform float drift_speed = 0.004;
uniform float star_density = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

float stars(vec2 p, float density, float size) {
	vec2 cell = floor(p);
	float h = hash(cell);
	if (h > density) {
		return 0.0;
	}
	vec2 centre = cell + vec2(hash(cell + 3.1), hash(cell + 7.7));
	float d = length(p - centre);
	return smoothstep(size, 0.0, d) * (0.5 + 0.5 * sin(TIME * (1.0 + h * 400.0) + h * 50.0));
}

void fragment() {
	vec2 p = world_pos.xz * scale + vec2(TIME * drift_speed, 0.0);
	// Domain warp for wispy shapes.
	vec2 warp = vec2(fbm(p + vec2(3.0, 1.0)), fbm(p + vec2(8.3, 2.8)));
	float n = fbm(p + warp * 1.6);
	float m = fbm(p * 1.7 - warp + vec2(5.2, 1.3));
	vec3 col = deep_color;
	col = mix(col, cloud_a, smoothstep(0.34, 0.8, n) * 0.9);
	col = mix(col, cloud_b, smoothstep(0.42, 0.85, m) * 0.7);
	col += ember * pow(smoothstep(0.62, 0.95, n * m * 1.6), 2.0) * 0.6;
	col *= brightness;
	vec2 sp = world_pos.xz;
	col += vec3(0.85, 0.88, 1.0) * stars(sp * 0.35, 0.02 * star_density, 0.05) * 0.9;
	col += vec3(1.0, 0.85, 0.7) * stars(sp * 0.12 + 40.0, 0.05 * star_density, 0.035) * 1.4;
	ALBEDO = col;
}
