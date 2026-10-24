//! A small radix-2 FFT standing in for `vDSP_fft2d_zip`'s inverse transform:
//! split real/imaginary rows, positive exponent, and no normalization.

/// Inverse 2D FFT of a row-major `n` x `n` split-complex grid, in place.
/// Like vDSP, the result is not divided by `n * n`.
pub fn inverse_2d(re: &mut [f32], im: &mut [f32], n: usize) {
    assert!(n.is_power_of_two(), "FFT size must be a power of two");
    assert_eq!(re.len(), n * n);
    assert_eq!(im.len(), n * n);

    let twiddles = Twiddles::inverse(n);
    for row in 0..n {
        let span = row * n..(row + 1) * n;
        transform(&mut re[span.clone()], &mut im[span], &twiddles);
    }

    let mut column_re = vec![0.0f32; n];
    let mut column_im = vec![0.0f32; n];
    for column in 0..n {
        for row in 0..n {
            column_re[row] = re[row * n + column];
            column_im[row] = im[row * n + column];
        }
        transform(&mut column_re, &mut column_im, &twiddles);
        for row in 0..n {
            re[row * n + column] = column_re[row];
            im[row * n + column] = column_im[row];
        }
    }
}

/// e^(+2 pi i k / n) for k < n / 2, computed in double precision.
struct Twiddles {
    cos: Vec<f32>,
    sin: Vec<f32>,
}

impl Twiddles {
    fn inverse(n: usize) -> Self {
        let half = n / 2;
        let angle = |k: usize| 2.0 * std::f64::consts::PI * k as f64 / n as f64;
        Self {
            cos: (0..half).map(|k| angle(k).cos() as f32).collect(),
            sin: (0..half).map(|k| angle(k).sin() as f32).collect(),
        }
    }
}

fn transform(re: &mut [f32], im: &mut [f32], twiddles: &Twiddles) {
    let n = re.len();
    let bits = n.trailing_zeros();
    if bits == 0 {
        return;
    }
    for i in 0..n {
        let j = i.reverse_bits() >> (usize::BITS - bits);
        if j > i {
            re.swap(i, j);
            im.swap(i, j);
        }
    }

    let mut length = 2;
    while length <= n {
        let half = length / 2;
        let stride = n / length;
        for start in (0..n).step_by(length) {
            for k in 0..half {
                let (wr, wi) = (twiddles.cos[k * stride], twiddles.sin[k * stride]);
                let (a, b) = (start + k, start + k + half);
                let tr = re[b] * wr - im[b] * wi;
                let ti = re[b] * wi + im[b] * wr;
                re[b] = re[a] - tr;
                im[b] = im[a] - ti;
                re[a] += tr;
                im[a] += ti;
            }
        }
        length *= 2;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dc_bin_inverts_to_a_constant() {
        let n = 8;
        let mut re = vec![0.0; n * n];
        let mut im = vec![0.0; n * n];
        re[0] = 1.0;
        inverse_2d(&mut re, &mut im, n);
        assert!(re.iter().all(|value| (value - 1.0).abs() < 1e-6));
        assert!(im.iter().all(|value| value.abs() < 1e-6));
    }

    #[test]
    fn single_bin_inverts_to_an_unnormalized_positive_exponent_wave() {
        let n = 16;
        let (u, v) = (3, 5);
        let mut re = vec![0.0; n * n];
        let mut im = vec![0.0; n * n];
        re[v * n + u] = 1.0;
        inverse_2d(&mut re, &mut im, n);
        for y in 0..n {
            for x in 0..n {
                let angle = 2.0 * std::f64::consts::PI * ((u * x + v * y) as f64) / n as f64;
                assert!((re[y * n + x] as f64 - angle.cos()).abs() < 1e-5);
                assert!((im[y * n + x] as f64 - angle.sin()).abs() < 1e-5);
            }
        }
    }

    #[test]
    fn hermitian_spectrum_inverts_to_a_real_field() {
        let n = 32;
        let mut re = vec![0.0f32; n * n];
        let mut im = vec![0.0f32; n * n];
        let mut seed = 1u32;
        let mut next = || {
            seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
            (seed >> 8) as f32 / (1u32 << 24) as f32 - 0.5
        };
        for v in 0..n {
            for u in 0..n {
                let (mu, mv) = ((n - u) % n, (n - v) % n);
                let (index, mirror) = (v * n + u, mv * n + mu);
                if index == mirror {
                    re[index] = next();
                } else if index < mirror {
                    re[index] = next();
                    im[index] = next();
                    re[mirror] = re[index];
                    im[mirror] = -im[index];
                }
            }
        }
        inverse_2d(&mut re, &mut im, n);
        assert!(im.iter().all(|value| value.abs() < 1e-3));
    }
}
