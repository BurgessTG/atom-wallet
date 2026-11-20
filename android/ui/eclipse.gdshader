shader_type canvas_item;
render_mode unshaded;
uniform vec2 canvas_size = vec2(360., 210.);
uniform float centered = 0.0;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
    vec2 physical = UV * canvas_size;
    vec2 point = (UV - mix(vec2(.80,.54), vec2(.53,.5), centered)) * canvas_size / canvas_size.y;
    float radius = mix(.34,.37,centered);
    float d = length(point);
    float halo = exp(-8.0 * abs(d-radius));
    vec3 color = mix(vec3(.082,.079,.153), vec3(.22,.18,.38), UV.x*.62 + halo*.35);
    vec2 cell = floor(physical / 14.);
    vec2 star = fract(physical / 14.) - vec2(hash(cell),hash(cell+1.));
    float stars = (1.-smoothstep(.01,.075,length(star))) * step(.70,hash(cell+3.));
    color += vec3(.59,.59,.82)*stars*.65;
    vec2 orbit = mat2(vec2(.95,.31),vec2(-.31,.95))*point;
    float arc = length(orbit / vec2(1.,.31));
    color += vec3(.45,.38,.67)*(1.-smoothstep(.001,.011,abs(arc-radius*1.9))) * .65;
    if (d < radius) {
        vec2 xy = point / radius;
        vec3 normal = vec3(xy, sqrt(max(0.,1.-dot(xy,xy))));
        float light = smoothstep(-.25,.95,dot(normal,normalize(vec3(-.78,-.48,.40))));
        float band = .5+.5*sin(128.*(xy.y*.82+xy.x*.19 + normal.z*.28 + .035*sin(xy.x*8.+xy.y*4.)));
        float rim = pow(1.-normal.z,2.);
        color = mix(vec3(.11,.093,.20),vec3(.67,.61,.87), light) + (band-.5)*vec3(.18,.15,.21)*(.3+.7*light) + rim*.17;
    }
    if (orbit.y > 0.) {
        color += vec3(.51,.43,.71)*(1.-smoothstep(.001,.012,abs(arc-radius*1.9)))*.86;
    }
    color += (hash(floor(physical))-.5)*.023;
    vec2 edge = abs(physical - canvas_size*.5) - (canvas_size*.5 - vec2(16.));
    float corner = length(max(edge,vec2(0.))) + min(max(edge.x,edge.y),0.) - 16.;
    COLOR = vec4(color, 1. - smoothstep(-1.,0.,corner));
}
