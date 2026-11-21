struct Stage { n: u32, width: u32 }
@group(0) @binding(0) var<storage, read> src: array<Elem>;
@group(0) @binding(1) var<storage, read_write> dst: array<Elem>;
@group(0) @binding(2) var<storage, read> roots: array<Elem>;
@group(0) @binding(3) var<uniform> stage: Stage;

@compute @workgroup_size(64)
fn transform(@builtin(global_invocation_id) id: vec3<u32>) {
    let j = id.x;
    if (j >= stage.n/2u) { return; }
    let offset = j & (stage.width - 1u);
    let index = (j-offset)*2u + offset;
    let left = src[j];
    let right = mul(src[j + stage.n/2u], roots[offset*(stage.n/(2u*stage.width))]);
    dst[index] = add(left, right);
    dst[index + stage.width] = subtract(left, right);
}

@compute @workgroup_size(64)
fn quotient(@builtin(global_invocation_id) id: vec3<u32>) {
    if (id.x < stage.n) {
        dst[id.x] = mul(src[id.x], roots[id.x % stage.width]);
    }
}
