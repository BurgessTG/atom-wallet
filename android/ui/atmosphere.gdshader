shader_type canvas_item;
render_mode unshaded;
// Moonlight backdrop: near-black with two soft violet glows.
void fragment() {
	vec2 a = (UV - vec2(0.88, -0.05)) * vec2(1.0, 1.7);
	vec2 b = (UV - vec2(-0.1, 0.35)) * vec2(1.0, 1.4);
	vec3 color = vec3(0.043, 0.043, 0.078);
	color += vec3(0.12, 0.09, 0.26) * exp(-3.2 * length(a));
	color += vec3(0.06, 0.05, 0.14) * exp(-3.8 * length(b));
	COLOR = vec4(color, 1.0);
}
