// Rift walls: a crackling membrane of void energy instead of flat glass.
// Bright where the wall meets the floor plane, with slow bands of noise
// crawling along it. Additive, so it glows and never hides the ship.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

uniform vec3 core_color : source_color = vec3(0.65, 0.3, 1.0);
uniform vec3 hot_color : source_color = vec3(0.95, 0.7, 1.0);
uniform float intensity = 0.4;
uniform float speed = 0.35;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	// Distance along the wall works for walls running either way.
	float along = world_pos.x + world_pos.z;
	float t = TIME * speed;
	float n = vnoise(vec2(along * 0.18 - t, world_pos.y * 0.6 + t * 0.5));
	float n2 = vnoise(vec2(along * 0.6 + t * 1.7, world_pos.y * 2.0));
	float veins = smoothstep(0.55, 0.95, n * 0.7 + n2 * 0.45);
	float band = 0.35 + 0.65 * n;
	vec3 col = core_color * band + hot_color * veins;
	// Fresnel-ish edge so the top reads as a glowing rim.
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	ALBEDO = col * intensity * (0.6 + rim);
}
