struct Elem { limbs: array<u32,L> }
fn subtract(a: Elem, b: Elem) -> Elem {
    var out: Elem;
    var borrow = 0u;
    for (var i = 0u; i < L; i++) {
        let d = a.limbs[i] - b.limbs[i];
        out.limbs[i] = d - borrow;
        borrow = u32(a.limbs[i] < b.limbs[i] || d < borrow);
    }
    var carry = 0u;
    for (var i = 0u; i < L; i++) {
        let v = out.limbs[i] + (MOD[i] & (0u - borrow));
        let sum = v + carry;
        carry = u32(v < out.limbs[i] || sum < v);
        out.limbs[i] = sum;
    }
    return out;
}

fn add(a: Elem, b: Elem) -> Elem {
    var out: Elem;
    var carry = 0u;
    for (var i = 0u; i < L; i++) {
        let lo = a.limbs[i] + b.limbs[i];
        out.limbs[i] = lo + carry;
        carry = u32(lo < a.limbs[i] || out.limbs[i] < lo);
    }
    // Twice the modulus fits in L words. Subtract r and add it back on underflow.
    return subtract(out, Elem(MOD));
}

// Exact a*b+c+d, returned low word first. The 16-bit partials fit in u32.
fn mac(a: u32, b: u32, c: u32, d: u32) -> vec2<u32> {
    let a0 = a & 65535u; let a1 = a >> 16u;
    let b0 = b & 65535u; let b1 = b >> 16u;
    let m = a1*b0 + ((a0*b0) >> 16u);
    let t = (m & 65535u) + a0*b1;
    let high = a1*b1 + (m >> 16u) + (t >> 16u);
    let low = a*b;
    let x = low+c;
    let y = x+d;
    return vec2<u32>(y, high + u32(x < low) + u32(y < x));
}

fn mul(a: Elem, b: Elem) -> Elem {
    var t: array<u32, L+2u>;
    for (var i = 0u; i < L; i++) {
        var carry = 0u;
        for (var j = 0u; j < L; j++) {
            let v = mac(a.limbs[j], b.limbs[i], t[j], carry);
            t[j] = v.x; carry = v.y;
        }
        t[L] += carry;
        t[L+1u] = u32(t[L] < carry);
        let factor = INV * t[0];
        carry = mac(factor, MOD[0], t[0], 0u).y;
        for (var j = 1u; j < L; j++) {
            let v = mac(factor, MOD[j], t[j], carry);
            t[j-1u] = v.x; carry = v.y;
        }
        t[L-1u] = t[L] + carry;
        t[L] = t[L+1u] + u32(t[L-1u] < carry);
    }
    var out: Elem;
    for (var i = 0u; i < L; i++) { out.limbs[i] = t[i]; }
    return subtract(out, Elem(MOD));
}
