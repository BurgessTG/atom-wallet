shader_type canvas_item;
render_mode unshaded;

// Atom Wallet's atom: a nucleus cluster with three tilted orbits. Electrons and
// smaller signal pulses flow along each orbit, passing behind and in front of
// the nucleus. `centered` places it in the middle (welcome, unlock); otherwise it
// sits partly out of frame on the right of a balance card.
uniform vec2 canvas_size = vec2(360., 200.);
uniform float centered = 0.0;
uniform float radius = 24.0;
uniform float motion = 1.0;
uniform float card = 1.0;
uniform vec3 violet : source_color = vec3(0.78, 0.75, 1.0);
uniform vec3 mint : source_color = vec3(0.62, 0.89, 0.75);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(vec2(c, s), vec2(-s, c)); }

// Distance to an ellipse of radius r and flattening k, with the orbit angle at p.
vec2 orbit(vec2 q, float r, float k) {
	float e = length(q / vec2(1.0, k));
	float g = length(q / vec2(1.0, k * k)) / max(e, 1e-4);
	return vec2(abs(e - r) / max(g, 1e-4), atan(q.y / k, q.x));
}

// Light from one orbit: the ring, the electron with its trail and the pulses.
vec3 ring(vec2 p, float tilt, float r, float k, float speed, float phase, float px, float t, bool front, out float cover) {
	vec2 q = rot(tilt) * p;
	vec2 o = orbit(q, r, k);
	float side = sin(o.y);
	cover = 0.0;
	if ((side > 0.0) != front) return vec3(0.0);
	float depth = front ? 1.0 : 0.55;
	vec3 light = violet * (1.0 - smoothstep(0.0, 1.6 * px, o.x)) * 0.32 * depth;
	light += violet * exp(-o.x / (5.0 * px)) * 0.05 * depth;
	for (int j = 0; j < 4; j++) {
		bool electron = j == 0;
		float head = t * speed * (electron ? 1.0 : 1.55) + phase + float(j) * 1.7;
		float behind = mod(head - o.y, 6.28318);
		float tail = exp(-behind * (electron ? 3.2 : 9.0)) * (1.0 - smoothstep(0.0, 2.6 * px, o.x));
		vec3 tint = electron ? mint : violet;
		light += tint * tail * (electron ? 0.9 : 0.55) * depth;
		vec2 at = vec2(cos(head), k * sin(head)) * r;
		float d = length(q - at);
		float size = electron ? 3.2 * px : 1.8 * px;
		float dot_ = exp(-d * d / (size * size));
		light += mix(tint, vec3(1.0), 0.55) * dot_ * (electron ? 1.4 : 0.9) * depth;
		light += tint * exp(-d / (size * 4.0)) * (electron ? 0.35 : 0.12) * depth;
		cover = max(cover, dot_);
	}
	return light;
}

void fragment() {
	vec2 physical = UV * canvas_size;
	float px = 1.0 / canvas_size.y;
	float t = TIME * motion;
	vec2 middle = mix(vec2(0.9, 0.5), vec2(0.5, 0.5), centered);
	vec2 p = (UV - middle) * canvas_size / canvas_size.y;
	float r = mix(0.6, 0.33, centered);

	vec3 color = mix(vec3(0.075, 0.066, 0.15), vec3(0.04, 0.037, 0.075), clamp(UV.x * 0.4 + UV.y * 0.6, 0.0, 1.0));
	color = mix(color, vec3(0.043, 0.043, 0.078), 1.0 - card);
	color += violet * 0.13 * exp(-2.4 * length(p));

	// Faint nodes, a few of them flickering like distant signals.
	vec2 cell = floor(physical / 18.0);
	vec2 star = fract(physical / 18.0) - vec2(hash(cell), hash(cell + 1.0));
	float twinkle = 0.55 + 0.45 * sin(t * (0.6 + hash(cell + 7.0)) + hash(cell + 9.0) * 6.28);
	color += vec3(0.62, 0.6, 0.86) * (1.0 - smoothstep(0.01, 0.07, length(star))) * step(0.78, hash(cell + 3.0)) * 0.45 * twinkle;

	float tilts[3] = float[](0.35, 1.4, 2.45);
	float speeds[3] = float[](0.9, -0.7, 0.8);
	float k = 0.33;
	float unused;
	for (int i = 0; i < 3; i++) color += ring(p, tilts[i], r, k, speeds[i], float(i) * 2.1, px, t, false, unused);

	// Nucleus: seven packed spheres, the nearest surface wins.
	float rn = r * 0.2;
	float breathe = 1.0 + 0.035 * sin(t * 1.3);
	vec3 offsets[7] = vec3[](vec3(0., 0., .55), vec3(.52, .1, .2), vec3(-.48, .22, .25), vec3(.1, -.5, .3), vec3(-.25, -.42, -.1), vec3(.3, .48, -.05), vec3(-.42, -.1, -.3));
	float best = -10.0;
	vec3 surface = vec3(0.0);
	for (int i = 0; i < 7; i++) {
		vec2 c = offsets[i].xy * rn * breathe;
		vec2 xy = (p - c) / (rn * 0.62);
		float d2 = dot(xy, xy);
		if (d2 < 1.0) {
			float z = sqrt(1.0 - d2) + offsets[i].z * 1.6;
			if (z > best) {
				best = z;
				vec3 n = vec3(xy, sqrt(1.0 - d2));
				float light = clamp(dot(n, normalize(vec3(-0.55, -0.6, 0.6))), 0.0, 1.0);
				vec3 base = (i % 2 == 0) ? violet : mix(violet, mint, 0.65);
				surface = base * (0.14 + 0.72 * light) + pow(light, 24.0) * 0.32 + pow(1.0 - n.z, 2.5) * base * 0.35;
			}
		}
	}
	color += violet * 0.5 * exp(-length(p) / (rn * 0.9)) * (0.85 + 0.15 * sin(t * 1.3));
	if (best > -10.0) color = surface;

	for (int i = 0; i < 3; i++) color += ring(p, tilts[i], r, k, speeds[i], float(i) * 2.1, px, t, true, unused);

	color += (hash(floor(physical)) - 0.5) * 0.02;
	vec2 edge = abs(physical - canvas_size * 0.5) - (canvas_size * 0.5 - vec2(radius));
	float corner = length(max(edge, vec2(0.0))) + min(max(edge.x, edge.y), 0.0) - radius;
	// Without a card the artwork fades into the page instead of ending at an edge.
	vec2 fromEdge = min(UV, 1.0 - UV) * canvas_size / min(canvas_size.x, canvas_size.y);
	float feather = smoothstep(0.0, 0.22, min(fromEdge.x, fromEdge.y));
	float alpha = mix(feather, 1.0 - smoothstep(-1.0, 0.0, corner), card);
	COLOR = vec4(color, alpha);
}
