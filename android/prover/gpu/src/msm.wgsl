// One invocation accumulates a short run of affine G1 points in Jacobian
// coordinates. Jobs for independent buckets run together.
struct Affine { x: Elem, y: Elem }
struct Jacobian { x: Elem, y: Elem, z: Elem }
struct Job { start: u32, count: u32 }
@group(0) @binding(0) var<storage, read> bases: array<Affine>;
@group(0) @binding(1) var<storage, read> indices: array<u32>;
@group(0) @binding(2) var<storage, read> jobs: array<Job>;
@group(0) @binding(3) var<storage, read_write> sums: array<Jacobian>;

fn zero(a: Elem) -> bool {
    var v = 0u;
    for (var i = 0u; i < L; i++) { v |= a.limbs[i]; }
    return v == 0u;
}
fn twice(a: Elem) -> Elem { return add(a, a); }

// Mixed Jacobian addition for y^2=x^3+4, including equal and opposite points.
fn accumulate(p: Jacobian, q: Affine) -> Jacobian {
    if (zero(q.x) && zero(q.y)) { return p; }
    if (zero(p.z)) { return Jacobian(q.x, q.y, Elem(ONE)); }
    let zz = mul(p.z, p.z);
    let h = subtract(mul(q.x, zz), p.x);
    let r = subtract(mul(q.y, mul(p.z, zz)), p.y);
    if (zero(h)) {
        if (!zero(r)) { return Jacobian(); }
        let xx = mul(p.x, p.x);
        let m = add(xx, twice(xx));
        let yy = mul(p.y, p.y);
        let s = twice(twice(mul(p.x, yy)));
        let x = subtract(mul(m, m), twice(s));
        let y = subtract(mul(m, subtract(s, x)), twice(twice(twice(mul(yy, yy)))));
        return Jacobian(x, y, twice(mul(p.y, p.z)));
    }
    let hh = mul(h, h);
    let hhh = mul(h, hh);
    let v = mul(p.x, hh);
    let x = subtract(subtract(mul(r, r), hhh), twice(v));
    let y = subtract(mul(r, subtract(v, x)), mul(p.y, hhh));
    return Jacobian(x, y, mul(p.z, h));
}

@compute @workgroup_size(32)
fn sum_buckets(@builtin(global_invocation_id) id: vec3<u32>) {
    if (id.x >= arrayLength(&jobs)) { return; }
    let job = jobs[id.x];
    var acc: Jacobian;
    for (var i = 0u; i < job.count; i++) {
        acc = accumulate(acc, bases[indices[job.start+i]]);
    }
    sums[id.x] = acc;
}
