        if n >= 256 {
            // s = 256*high + low. Both devices reuse the same normalized bases.
            let bases = &points.as_slice()[..n];
            let mut low = Vec::with_capacity(n);
            let mut high = Vec::with_capacity(n * 31);
            for scalar in &scalars[..n] {
                let bytes = scalar.to_bytes_le();
                low.push(bytes[0]);
                high.extend_from_slice(&bytes[1..]);
            }
            let (mut upper, lower) = rayon::join(
                || Self(bases.mult(&high, 247)),
                || {
                    let mut data = Vec::with_capacity(n * 96);
                    for &base in bases {
                        let point = G1Affine(base);
                        point.x().write_raw(&mut data).unwrap();
                        point.y().write_raw(&mut data).unwrap();
                    }
                    let (destinations, sums) = mdwa_vulkan::msm_buckets(&data, &low)
                        .expect("Vulkan MSM failed");
                    let mut buckets = vec![Self::identity(); 255];
                    for (bucket, raw) in destinations.into_iter().zip(sums.chunks_exact(144)) {
                        let z = Fp::from_raw_bytes_unchecked(&raw[96..]);
                        if !bool::from(z.is_zero()) {
                            let x = Fp::from_raw_bytes_unchecked(&raw[..48]);
                            let y = Fp::from_raw_bytes_unchecked(&raw[48..96]);
                            buckets[bucket] += Self::from_raw_unchecked(x, y, z);
                        }
                    }
                    let mut result = Self::identity();
                    let mut running = Self::identity();
                    for point in buckets.iter().rev() {
                        running += point;
                        result += &running;
                    }
                    result
                },
            );
            for _ in 0..8 { upper = upper.double(); }
            return upper + lower;
        }
