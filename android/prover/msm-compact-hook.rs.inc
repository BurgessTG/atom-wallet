        let count = points.len().min(scalars.len());
        let (points, scalars) = (&points[..count], &scalars[..count]);
        // Witness columns often contain long runs of zero or the same coefficient.
        // Factor s*P + s*Q into s*(P+Q) before normalizing bases and assigning buckets.
        let (mut compact_points, mut compact_scalars) = (Vec::new(), Vec::new());
        let (points, scalars) = if count >= 256 && scalars.windows(2).any(|s| s[0] == s[1]) {
            for (point, &scalar) in points.iter().zip(scalars) {
                if bool::from(scalar.is_zero()) { continue; }
                if compact_scalars.last() == Some(&scalar) {
                    *compact_points.last_mut().unwrap() += point;
                } else {
                    compact_points.push(*point);
                    compact_scalars.push(scalar);
                }
            }
            (compact_points.as_slice(), compact_scalars.as_slice())
        } else {
            (points, scalars)
        };
        if points.is_empty() { return Self::identity(); }
