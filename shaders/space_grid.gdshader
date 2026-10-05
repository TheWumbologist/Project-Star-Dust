// Grey-box reference grid drawn under the flight plane so speed and drift
// are readable in an otherwise empty test arena. Fades out with distance.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

uniform vec4 line_color : source_color = vec4(0.25, 0.35, 0.8, 1.0);
uniform vec4 major_color : source_color = vec4(0.9, 0.6, 0.25, 1.0);
uniform float cell_size = 5.0;
uniform float major_every = 5.0;
uniform float line_width = 0.04;
uniform float fade_radius = 140.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid(vec2 p, float size, float width) {
	vec2 cell = abs(fract(p / size - 0.5) - 0.5) * size;
	vec2 aa = fwidth(p) * 1.5;
	vec2 g = 1.0 - smoothstep(vec2(width), vec2(width) + aa, cell);
	return max(g.x, g.y);
}

void fragment() {
	vec2 p = world_pos.xz;
	float minor = grid(p, cell_size, line_width);
	float major = grid(p, cell_size * major_every, line_width * 2.0);
	float fade = 1.0 - smoothstep(fade_radius * 0.6, fade_radius, length(p));
	vec3 col = line_color.rgb * minor * 0.35 + major_color.rgb * major * 0.5;
	ALBEDO = col * fade;
}
