    // Only scalar-field transforms are eligible. The same generic upstream
    // routine also handles elliptic-curve points when constructing parameters.
    use std::any::{Any, TypeId};
    use crate::{Fq, serde_traits::SerdeObject};
    if log_n > 0 && TypeId::of::<G>() == TypeId::of::<Fq>() {
        if let Some(root) = (&omega as &dyn Any).downcast_ref::<Fq>() {
            assert_eq!(a.len(), 1usize << log_n);
            let mut data = Vec::with_capacity(a.len() * 32);
            for value in a.iter() {
                (value as &dyn Any).downcast_ref::<Fq>().unwrap().write_raw(&mut data).unwrap();
            }
            mdwa_vulkan::ntt(&mut data, log_n, root.to_bytes_le(), || {
                let mut roots = Vec::with_capacity(a.len() * 16);
                let mut twiddle = Fq::ONE;
                for _ in 0..a.len()/2 {
                    twiddle.write_raw(&mut roots).unwrap();
                    twiddle *= root;
                }
                roots
            }).expect("Vulkan NTT failed");
            for (value, raw) in a.iter_mut().zip(data.chunks_exact(32)) {
                *(value as &mut dyn Any).downcast_mut::<Fq>().unwrap() = Fq::from_raw_bytes_unchecked(raw);
            }
            return;
        }
    }
