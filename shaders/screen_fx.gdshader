// Full-screen overlay for game feel: speed streaks while boosting, a
// coloured edge flash on hits, a red pulse at low hull and a purple tint as
// the rift destabilises. Every effect is 0 by default.
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float speed_lines : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 0.2, 0.1, 1.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float danger : hint_range(0.0, 1.0) = 0.0;
uniform float instability : hint_range(0.0, 1.0) = 0.0;
uniform float time_offset = 0.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float r = length(uv);
	float edge = smoothstep(0.25, 0.75, r);

	// Radial streaks that rush outward from the centre.
	float angle = atan(uv.y, uv.x);
	float lane = floor(angle * 40.0);
	float rnd = hash(lane);
	float rush = fract(r * 1.5 - (TIME + time_offset) * (2.0 + rnd * 3.0) + rnd);
	float streak = step(0.82, rnd) * smoothstep(0.75, 1.0, rush) * smoothstep(0.2, 0.55, r);
	float lines = streak * speed_lines * 0.55;

	float pulse = 0.5 + 0.5 * sin(TIME * 7.0);
	vec4 col = vec4(1.0, 1.0, 1.0, lines);
	col = mix(col, vec4(flash_color.rgb, 1.0), clamp(edge * flash, 0.0, 1.0));
	float danger_a = edge * danger * (0.25 + 0.2 * pulse);
	col.rgb = mix(col.rgb, vec3(0.9, 0.05, 0.05), danger_a / max(col.a + danger_a, 0.001));
	col.a = max(col.a, danger_a);
	float rift_a = edge * instability * (0.25 + 0.1 * sin(TIME * 2.0));
	col.rgb = mix(col.rgb, vec3(0.55, 0.15, 1.0), rift_a / max(col.a + rift_a, 0.001));
	col.a = max(max(col.a, rift_a), edge * flash);
	COLOR = col;
}
