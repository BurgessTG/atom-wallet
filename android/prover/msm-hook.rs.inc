        let count = points.len().min(scalars.len());
        if count >= 256 {
            let mut affine = vec![G1Affine::identity(); count];
            Self::batch_normalize(&points[..count], &mut affine);
            let mut data = Vec::with_capacity(count * 96);
            for point in affine {
                point.x().write_raw(&mut data).unwrap();
                point.y().write_raw(&mut data).unwrap();
            }
            let digits: Vec<_> = scalars[..count].iter().map(Fq::to_bytes_le).collect();
            let (destinations, sums) = mdwa_vulkan::msm_buckets(&data, &digits).expect("Vulkan MSM failed");
            let mut buckets = vec![Self::identity(); 32 * 255];
            for (bucket, point) in destinations.into_iter().zip(sums.chunks_exact(144)) {
                let x = Fp::from_raw_bytes_unchecked(&point[..48]);
                let y = Fp::from_raw_bytes_unchecked(&point[48..96]);
                let z = Fp::from_raw_bytes_unchecked(&point[96..]);
                if !bool::from(z.is_zero()) { buckets[bucket] += Self::from_raw_unchecked(x, y, z); }
            }
            let mut result = Self::identity();
            for window in buckets.chunks_exact(255).rev() {
                for _ in 0..8 { result = result.double(); }
                let mut running = Self::identity();
                for point in window.iter().rev() {
                    running += point;
                    result += &running;
                }
            }
            return result;
        }
