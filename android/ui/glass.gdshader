shader_type canvas_item;
render_mode unshaded;
uniform vec4 tint : source_color = vec4(0.13,0.14,0.22,0.84);
uniform float radius = 20.0;
uniform sampler2D backdrop : hint_screen_texture, repeat_disable, filter_linear_mipmap;
void fragment() {
	vec2 pixel = max(fwidth(UV), vec2(0.00001));
	vec2 extent = 0.5 / pixel;
	float r = min(radius, min(extent.x, extent.y));
	vec2 local = (UV - 0.5) / pixel;
	vec2 q = abs(local) - extent + r + 1.0;
	float edge = min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
	float rim = 1.0 - smoothstep(0.5, 2.4, abs(edge));
	float curve = exp(-max(0.0, -edge) * 0.22);
	vec2 normal = normalize(local / max(extent,vec2(1.0)) + vec2(0.0001));
	vec3 scene = textureLod(backdrop, SCREEN_UV - normal * SCREEN_PIXEL_SIZE * curve * 3.0, 2.0).rgb;
	float sheen = clamp(0.50 - normal.y * 0.34 - normal.x * 0.16, 0.0, 1.0);
	vec3 glass = mix(scene, tint.rgb, tint.a) + vec3(0.045,0.065,0.068) * sheen * (0.27 + curve);
	COLOR = vec4(glass + rim * sheen * vec3(0.17,0.22,0.25), 1.0 - smoothstep(-0.65,0.65,edge));
}
