// Asteroids: lumps the sphere with 3D noise along its normal and shades
// the result as flat facets, so cheap spheres read as chunky rocks. Each
// rock gets its own shape from its world position. Colour varies across
// the surface with darker cracks and a cool rim light.
shader_type spatial;

uniform vec3 rock_color : source_color = vec3(0.4, 0.35, 0.38);
uniform vec3 dark_color : source_color = vec3(0.16, 0.13, 0.19);
uniform vec3 rim_color : source_color = vec3(0.55, 0.45, 0.9);
uniform float lumpiness = 0.22;
uniform float roughness_amount = 0.92;

varying vec3 local_pos;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	vec3 seed = MODEL_MATRIX[3].xyz * 0.37;
	float r = length(VERTEX);
	vec3 dir = VERTEX / max(r, 0.001);
	float n = noise3(dir * 1.8 + seed) * 0.7 + noise3(dir * 4.0 + seed * 1.3) * 0.3;
	VERTEX = dir * r * (1.0 - lumpiness * 0.5 + lumpiness * n);
	local_pos = dir * 3.0 + seed;
}

void fragment() {
	// Flat facets from screen-space derivatives.
	NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	float n = noise3(local_pos * 1.2) * 0.7 + noise3(local_pos * 3.1) * 0.3;
	float cracks = smoothstep(0.7, 0.8, noise3(local_pos * 2.2 + 11.0));
	ALBEDO = mix(dark_color, rock_color, smoothstep(0.2, 0.8, n)) * (1.0 - cracks * 0.3);
	ROUGHNESS = roughness_amount;
	RIM = 0.6;
	RIM_TINT = 0.5;
	EMISSION = rim_color * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0) * 0.25;
}
