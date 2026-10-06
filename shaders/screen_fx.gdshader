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

	// Thin speed beams rushing outward from the centre, each with a soft
	// glow, plus a sprinkle of small sparks between them. Kept faint so the
	// screen doesn't get crowded.
	float angle = atan(uv.y, uv.x) / 6.2831853 + 0.5;
	float t = TIME + time_offset;
	float fade_in = smoothstep(0.22, 0.5, r);

	float a = angle * 140.0;
	float lane = floor(a);
	float across = abs(fract(a) - 0.5);
	float rnd = hash(lane);
	float rush = fract(r * 1.2 - t * (1.6 + rnd * 2.2) + rnd * 13.0);
	float beam_len = smoothstep(0.55, 0.97, rush) * (1.0 - smoothstep(0.97, 1.0, rush));
	float core = 1.0 - smoothstep(0.03, 0.09, across);
	float glow = (1.0 - smoothstep(0.05, 0.3, across)) * 0.35;
	float beams = step(0.84, rnd) * beam_len * (core + glow);

	float b = angle * 260.0;
	float slane = floor(b);
	float srnd = hash(slane + 71.0);
	float srad = r * 22.0 - t * (5.0 + srnd * 6.0) + srnd * 40.0;
	vec2 cell = vec2(fract(b) - 0.5, fract(srad) - 0.5);
	float spark_on = step(0.86, hash(slane * 3.1 + floor(srad)));
	float sparks = spark_on * (1.0 - smoothstep(0.08, 0.2, length(cell * vec2(1.0, 1.6))));

	float lines = (beams * 0.32 + sparks * 0.22) * fade_in * speed_lines;

	float pulse = 0.5 + 0.5 * sin(TIME * 7.0);
	vec4 col = vec4(0.82, 0.9, 1.0, lines);
	col = mix(col, vec4(flash_color.rgb, 1.0), clamp(edge * flash, 0.0, 1.0));
	float danger_a = edge * danger * (0.25 + 0.2 * pulse);
	col.rgb = mix(col.rgb, vec3(0.9, 0.05, 0.05), danger_a / max(col.a + danger_a, 0.001));
	col.a = max(col.a, danger_a);
	float rift_a = edge * instability * (0.25 + 0.1 * sin(TIME * 2.0));
	col.rgb = mix(col.rgb, vec3(0.55, 0.15, 1.0), rift_a / max(col.a + rift_a, 0.001));
	col.a = max(max(col.a, rift_a), edge * flash);
	COLOR = col;
}
