        // On the extended coset, division by X^n - 1 is multiplication
        // by a repeating table of precomputed inverses.
        use std::any::{Any, TypeId};
        use midnight_curves::{Fq, serde_traits::SerdeObject};
        if TypeId::of::<F>() == TypeId::of::<Fq>() && a.values.len() >= 64 {
            let pack = |values: &[F]| {
                let mut bytes = Vec::with_capacity(values.len() * 32);
                for value in values {
                    (value as &dyn Any).downcast_ref::<Fq>().unwrap().write_raw(&mut bytes).unwrap();
                }
                bytes
            };
            let mut data = pack(&a.values);
            mdwa_vulkan::divide_vanishing(&mut data, &pack(&self.t_evaluations)).expect("Vulkan quotient failed");
            for (value, raw) in a.values.iter_mut().zip(data.chunks_exact(32)) {
                *(value as &mut dyn Any).downcast_mut::<Fq>().unwrap() = Fq::from_raw_bytes_unchecked(raw);
            }
            return a;
        }
