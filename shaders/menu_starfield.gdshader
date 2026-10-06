// Drifting starfield and nebula glow for menu backgrounds. Procedural, so
// there is no texture asset to track.
shader_type canvas_item;

uniform vec4 nebula_a : source_color = vec4(0.35, 0.1, 0.55, 1.0);
uniform vec4 nebula_b : source_color = vec4(0.9, 0.45, 0.15, 1.0);
uniform float speed = 0.02;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float stars(vec2 uv, float density, float t) {
	vec2 p = uv * density + vec2(t, 0.0);
	vec2 cell = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = hash(cell);
	float twinkle = 0.6 + 0.4 * sin(TIME * (1.0 + h * 3.0) + h * 20.0);
	return step(0.93, h) * smoothstep(0.08, 0.0, length(f)) * twinkle;
}

void fragment() {
	vec2 uv = UV;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float t = TIME * speed;
	float n = noise(uv * 3.0 + vec2(t * 2.0, t)) * 0.6 + noise(uv * 7.0 - vec2(t, t * 3.0)) * 0.4;
	vec3 col = vec3(0.02, 0.015, 0.05);
	col += nebula_a.rgb * smoothstep(0.45, 0.9, n) * 0.5;
	col += nebula_b.rgb * smoothstep(0.7, 1.0, n) * 0.25;
	col += vec3(stars(uv, 60.0, t * 10.0)) * 0.7;
	col += vec3(stars(uv, 30.0, t * 25.0));
	COLOR = vec4(col, 1.0);
}
