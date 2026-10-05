// Stellar wind stream: translucent streaks scrolling along local -Z.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

uniform vec4 stream_color : source_color = vec4(0.35, 0.85, 1.0, 1.0);
// Streak travel speed in metres per second.
uniform float scroll_speed = 14.0;
// Metres between streaks.
uniform float streak_spacing = 6.0;
uniform float intensity = 0.6;

varying float along_m;

void vertex() {
	// Distance along the stream's flow direction (local -Z), in metres.
	along_m = -VERTEX.z;
}

void fragment() {
	float phase = (along_m - TIME * scroll_speed) / streak_spacing;
	// Chevrons pointing downstream, so the flow direction reads at a glance.
	float wobble = abs(UV.x - 0.5) * 0.8;
	float streak = smoothstep(0.8, 1.0, sin((phase + wobble) * 6.2831));
	float edge = sin(UV.x * 3.14159);
	ALBEDO = stream_color.rgb * (streak + 0.15) * edge * intensity;
}
