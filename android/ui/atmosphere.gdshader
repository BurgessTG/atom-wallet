shader_type canvas_item;
render_mode unshaded;
void fragment() {
	float glow = exp(-3.5 * length((UV - vec2(0.82,0.08)) * vec2(1.0,1.5)));
	COLOR = vec4(vec3(0.034,0.055,0.065) + glow * vec3(0.035,0.085,0.084),1.0);
}
