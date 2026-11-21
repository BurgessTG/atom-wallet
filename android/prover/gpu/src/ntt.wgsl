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
    var right = src[j + stage.n/2u];
    if (offset != 0u) { right = mul(right, roots[offset*(stage.n/(2u*stage.width))]); }
    dst[index] = add(left, right);
    dst[index + stage.width] = subtract(left, right);
}

// Seven Stockham stages share a tile. Each column has the same low index
// throughout those stages, which determines its twiddle and output stride.
var<workgroup> tile: array<Elem, 128>;
@compute @workgroup_size(64)
fn transform_tile(@builtin(local_invocation_index) lane: u32,
                  @builtin(workgroup_id) group: vec3<u32>) {
    let stride = stage.n / 128u;
    let column = group.x & (stage.width - 1u);
    let a = src[group.x + lane * stride];
    var b = src[group.x + (lane + 64u) * stride];
    if (column != 0u) { b = mul(b, roots[column * (stage.n / (2u * stage.width))]); }
    tile[2u * lane] = add(a, b);
    tile[2u * lane + 1u] = subtract(a, b);
    for (var width = 2u; width < 128u; width *= 2u) {
        workgroupBarrier();
        let offset = lane & (width - 1u);
        let i = 2u * (lane - offset) + offset;
        let left = tile[lane];
        var right = tile[lane + 64u];
        let exponent = (offset * stage.width + column) * (stage.n / (2u * width * stage.width));
        if (exponent != 0u) { right = mul(right, roots[exponent]); }
        let sum = add(left, right);
        let diff = subtract(left, right);
        workgroupBarrier();
        tile[i] = sum;
        tile[i + width] = diff;
    }
    workgroupBarrier();
    let base = (group.x - column) * 128u + column;
    dst[base + lane * stage.width] = tile[lane];
    dst[base + (lane + 64u) * stage.width] = tile[lane + 64u];
}

@compute @workgroup_size(64)
fn quotient(@builtin(global_invocation_id) id: vec3<u32>) {
    if (id.x < stage.n) {
        dst[id.x] = mul(src[id.x], roots[id.x % stage.width]);
    }
}
