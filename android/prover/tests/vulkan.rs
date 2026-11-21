use group::{
    Group,
    ff::{Field, PrimeField},
};
use midnight_curves::{Fq, G1Projective, fft::best_fft};

// Requires a hardware Vulkan adapter. The references use only ordinary CPU
// field arithmetic and single-point multiplication, outside the patched paths.
#[test]
fn transforms_and_exceptional_buckets() {
    for log_n in [1, 3, 6, 7, 8] {
        let n = 1usize << log_n;
        let omega = Fq::ROOT_OF_UNITY.pow_vartime([1u64 << (Fq::S - log_n)]);
        let coefficients: Vec<Fq> = (0..n).map(|i| -Fq::from(i as u64 + 17)).collect();
        let mut actual = coefficients.clone();
        best_fft(&mut actual, omega, log_n);
        let mut x = Fq::ONE;
        for result in &actual {
            let expected = coefficients
                .iter()
                .rev()
                .fold(Fq::ZERO, |sum, &c| sum * x + c);
            assert_eq!(*result, expected);
            x *= omega;
        }
        best_fft(&mut actual, omega.invert().unwrap(), log_n);
        for (v, c) in actual.iter().zip(coefficients) {
            assert_eq!(*v, c * Fq::from(n as u64));
        }
    }
    let g = G1Projective::generator();
    let choices = [g, g, -g, G1Projective::identity(), g.double()];
    let points: Vec<_> = (0..512).map(|i| choices[i % choices.len()]).collect();
    let scalars: Vec<_> = (0..points.len())
        .map(|i| match i % 7 {
            0 => Fq::ZERO,
            1 => -Fq::ONE,
            _ => Fq::from(257),
        })
        .collect();
    let expected = points
        .iter()
        .zip(&scalars)
        .fold(G1Projective::identity(), |sum, (p, k)| sum + p * k);
    assert_eq!(G1Projective::multi_exp(&points, &scalars), expected);
    assert_eq!(
        G1Projective::multi_exp(&points, &vec![Fq::ZERO; points.len()]),
        G1Projective::identity()
    );
    assert!(gpu::transforms() >= 10 && gpu::multiscalars() > 0);
}
