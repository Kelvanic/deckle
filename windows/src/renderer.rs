//! Port of the macOS v4 "spectral fiber" renderer
//! (`Sources/Deckle/TextureRenderer.swift`), the engine every built-in uses.
//!
//! The pipeline, its constants, and the order of every random draw follow the
//! Swift code exactly, so a paper's seed produces the same grain structure on
//! both platforms. Output is not byte-identical to macOS: vDSP and this FFT,
//! and the two platforms' `exp`/`sin`/`cos`, round differently in the last
//! float bits.
//!
//! The renderer only ever produces one small seamless tile (256 points at 1x
//! or 2x). The overlay repeats it across the display.

use crate::fft;
use crate::papers::Paper;
use crate::rng::SplitMix64;
use std::f32::consts::PI;

/// Logical size, in points, of the square tile every paper renders.
pub const TILE_POINTS: usize = 256;

/// Snaps a display scale to the two resolutions the renderer supports, as
/// macOS does: 1x up to 150%, 2x above.
pub fn normalized_scale(scale: f64) -> usize {
    if scale > 1.5 {
        2
    } else {
        1
    }
}

/// A square, seamless tile of premultiplied RGBA8 pixels, top row first.
#[derive(Clone, Debug, PartialEq)]
pub struct Tile {
    pub size: usize,
    pub rgba: Vec<u8>,
}

impl Tile {
    /// The same pixels in the BGRA order Windows bitmaps use.
    pub fn to_bgra(&self) -> Tile {
        let mut bgra = self.rgba.clone();
        bgra.chunks_exact_mut(4).for_each(|pixel| pixel.swap(0, 2));
        Tile { size: self.size, rgba: bgra }
    }
}

/// Repeats a tile across a `width` x `height` 32-bit bitmap, top row first,
/// starting from the bitmap's top-left corner.
pub fn fill_tiled(target: &mut [u8], width: usize, height: usize, tile: &Tile) {
    assert_eq!(target.len(), width * height * 4);
    let size = tile.size;
    for (y, row) in target.chunks_exact_mut(width * 4).enumerate() {
        let source = &tile.rgba[(y % size) * size * 4..(y % size + 1) * size * 4];
        for chunk in row.chunks_mut(size * 4) {
            chunk.copy_from_slice(&source[..chunk.len()]);
        }
    }
}

/// The overlay tile: grain composited over the paper's tint wash, at full
/// design strength. The overlay's intensity is applied by the window.
pub fn composite_tile(paper: &Paper, scale: usize) -> Tile {
    let grain = grain_tile(paper, scale);
    let tint_alpha = paper.tint_alpha.clamp(0.0, 1.0);
    let tint = [paper.tint.r * tint_alpha, paper.tint.g * tint_alpha, paper.tint.b * tint_alpha];

    let mut rgba = grain.rgba;
    for pixel in rgba.chunks_exact_mut(4) {
        // Source-over: grain on top of the tint wash, both premultiplied.
        let cover = 1.0 - pixel[3] as f64 / 255.0;
        for (channel, tint_channel) in pixel[..3].iter_mut().zip(tint) {
            *channel = to_byte(*channel as f64 / 255.0 + tint_channel * cover);
        }
        pixel[3] = to_byte(pixel[3] as f64 / 255.0 + tint_alpha * cover);
    }
    Tile { size: grain.size, rgba }
}

/// The translucent grain alone: speckles in the paper's dark and light
/// colours, premultiplied.
pub fn grain_tile(paper: &Paper, scale: usize) -> Tile {
    let size = TILE_POINTS * scale.clamp(1, 2);
    let mut rgba = vec![0u8; size * size * 4];
    // A paper without visible grain (Clear Veil) is a flat wash; skip the
    // field entirely.
    if paper.dark_strength <= 0.0 && paper.light_strength <= 0.0 {
        return Tile { size, rgba };
    }

    let field = grain_field(paper, scale);
    let dark_strength = paper.dark_strength.min(1.0);
    let light_strength = paper.light_strength.min(1.0);
    for (value, pixel) in field.iter().zip(rgba.chunks_exact_mut(4)) {
        let delta = value - 0.5;
        let (color, alpha) = if delta < 0.0 {
            (paper.dark_color, (-delta * 2.0).min(1.0) * dark_strength)
        } else {
            (paper.light_color, (delta * 2.0).min(1.0) * light_strength)
        };
        // Truncating conversions, as the Swift `UInt8(_:)` initializers do.
        let a = alpha as f64;
        pixel[0] = (color.r * a * 255.0) as u8;
        pixel[1] = (color.g * a * 255.0) as u8;
        pixel[2] = (color.b * a * 255.0) as u8;
        pixel[3] = (a * 255.0) as u8;
    }
    Tile { size, rgba }
}

fn to_byte(unit: f64) -> u8 {
    (unit.clamp(0.0, 1.0) * 255.0).round() as u8
}

/// The deterministic [0, 1] grain field, row-major at the tile's pixel
/// resolution. `scale` (1 or 2) changes sampling density, not structure.
pub fn grain_field(paper: &Paper, scale: usize) -> Vec<f32> {
    let factor = scale.clamp(1, 2);
    let n = TILE_POINTS * factor;

    let mut base = spectral_field(n, factor, paper);

    let fiber_strength = paper.fiber.strength.clamp(0.0, 1.0);
    if fiber_strength > 0.001 {
        let mut fiber_rng = SplitMix64::new(paper.seed.wrapping_add(0xA5B9_C4E3_D2F1_0678));
        stamp_fiber_strands(&mut base, n, paper.fiber.angle, fiber_strength, factor as f32, &mut fiber_rng);
    }

    let roughness = paper.fiber.roughness.clamp(0.0, 1.0);
    if roughness > 0.001 {
        let surface = surface_noise(n, paper.seed.wrapping_add(0x7E3D_A1B8_C9F0_5246), factor);
        for (value, bump) in base.iter_mut().zip(surface) {
            // Roughness only darkens, like a veil of paper fibers.
            *value = (*value + bump.min(0.0) * roughness * 0.35).max(0.0);
        }
    }
    base
}

/// The v2 base: a random-phase, Hermitian-symmetric spectrum shaped by the
/// paper's octaves, inverse-transformed into a real seamless field, then
/// normalized and layered with weave, fiber splats, and flecks.
fn spectral_field(n: usize, factor: usize, paper: &Paper) -> Vec<f32> {
    let mut rng = SplitMix64::new(paper.seed);

    let total_weight: f32 = paper.octaves.iter().map(|octave| octave.weight).sum();
    let safe_total_weight = if total_weight > 0.0 { total_weight } else { 1.0 };
    let bands: Vec<(f32, f32, f32)> = paper
        .octaves
        .iter()
        .map(|octave| {
            let cell = (octave.cell as f64 * factor as f64).max(1.0);
            let k0 = (n as f64 / 2.0).min(n as f64 / (2.0 * cell)) as f32;
            let sigma = (k0 * 0.6).max(1.0);
            (k0, sigma, octave.weight / safe_total_weight)
        })
        .collect();

    let amplitude = |u: usize, v: usize| -> f32 {
        let fv = v.min(n - v) as f32;
        let fu = u.min(n - u) as f32;
        let r = (fu * fu + fv * fv).sqrt();
        let mut power = 0.0f32;
        for &(k0, sigma, weight) in &bands {
            let d = (r - k0) / sigma;
            power += weight * (-0.5 * d * d).exp();
        }
        if power > 0.0 {
            power.sqrt()
        } else {
            0.0
        }
    };

    let mut re = vec![0.0f32; n * n];
    let mut im = vec![0.0f32; n * n];
    let assign_random = |re: &mut [f32], im: &mut [f32], rng: &mut SplitMix64, u: usize, v: usize| {
        let amp = amplitude(u, v);
        let phase = rng.unit_f32() * 2.0 * PI;
        re[v * n + u] = amp * phase.cos();
        im[v * n + u] = amp * phase.sin();
    };
    let mirror_conjugate = |re: &mut [f32], im: &mut [f32], u: usize, v: usize| {
        let index = v * n + u;
        let mirror = ((n - v) % n) * n + (n - u) % n;
        re[mirror] = re[index];
        im[mirror] = -im[index];
    };
    // DC and the three Nyquist bins are their own mirror: purely real.
    let assign_self_conjugate = |re: &mut [f32], im: &mut [f32], rng: &mut SplitMix64, u: usize, v: usize| {
        let amp = amplitude(u, v);
        let sign = if rng.unit_f32() < 0.5 { -1.0 } else { 1.0 };
        re[v * n + u] = amp * sign;
        im[v * n + u] = 0.0;
    };

    let half = n / 2;
    // DC stays zero. Rows 0 and n/2 mirror within themselves.
    for u in 1..half {
        assign_random(&mut re, &mut im, &mut rng, u, 0);
        mirror_conjugate(&mut re, &mut im, u, 0);
    }
    assign_self_conjugate(&mut re, &mut im, &mut rng, half, 0);
    for u in 1..half {
        assign_random(&mut re, &mut im, &mut rng, u, half);
        mirror_conjugate(&mut re, &mut im, u, half);
    }
    assign_self_conjugate(&mut re, &mut im, &mut rng, 0, half);
    assign_self_conjugate(&mut re, &mut im, &mut rng, half, half);
    // Rows 1..n/2 are free; rows n/2+1.. are their conjugate mirrors.
    for v in 1..half {
        for u in 0..n {
            assign_random(&mut re, &mut im, &mut rng, u, v);
        }
        for u in 0..n {
            mirror_conjugate(&mut re, &mut im, u, v);
        }
    }

    fft::inverse_2d(&mut re, &mut im, n);
    drop(im);
    let divisor = (n * n) as f32;
    let mut base = re;
    base.iter_mut().for_each(|value| *value /= divisor);

    // Center on the actual mean and scale by the actual peak deviation.
    let mean = (base.iter().map(|&value| value as f64).sum::<f64>() / base.len() as f64) as f32;
    base.iter_mut().for_each(|value| *value -= mean);
    let max_deviation = base.iter().fold(0.0f32, |peak, value| peak.max(value.abs()));
    if max_deviation > 0.0 {
        base.iter_mut().for_each(|value| *value /= max_deviation);
    }
    base.iter_mut().for_each(|value| *value = *value * 0.5 + 0.5);

    if let Some(weave) = paper.weave {
        // Whole cycles across the tile, or the crosshatch would seam.
        let period = (weave.period as f64 * factor as f64).max(1.0);
        let cycles = (n as f64 / period).round().max(1.0);
        let k = 2.0 * PI * cycles as f32 / n as f32;
        for y in 0..n {
            let sy = (y as f32 * k).sin();
            for x in 0..n {
                let sx = (x as f32 * k).sin();
                let value = &mut base[y * n + x];
                *value = (*value + (sx + sy) * 0.5 * weave.amplitude).clamp(0.0, 1.0);
            }
        }
        stamp_fibers(&mut base, n, weave.amplitude, factor as f32, &mut rng);
    }

    // The first of the coarsest octaves, as Swift's `max(by:)` picks it.
    let coarse = paper.octaves.iter().fold(None, |best: Option<&crate::papers::Octave>, octave| match best {
        Some(current) if current.cell >= octave.cell => Some(current),
        _ => Some(octave),
    });
    if let Some(coarse) = coarse.filter(|octave| octave.cell > 1) {
        stamp_flecks(&mut base, n, coarse.weight / safe_total_weight, factor as f32, &mut rng);
    }
    base
}

/// v4 fiber strands: tapered Gabor patches whose fibrils run along `angle`.
/// They only darken, and wrap toroidally so the tile stays seamless.
fn stamp_fiber_strands(field: &mut [f32], n: usize, angle: f32, strength: f32, pixel_scale: f32, rng: &mut SplitMix64) {
    let nf = n as f32;
    let grain = pixel_scale;
    let count = ((strength * 16.0).round() as i64).max(1);
    for _ in 0..count {
        let cx = (rng.unit_f32() * nf) as i64;
        let cy = (rng.unit_f32() * nf) as i64;
        let jitter = (rng.unit_f32() - 0.5) * 0.3;
        let dir_x = (angle + jitter).cos();
        let dir_y = (angle + jitter).sin();
        // Capped below the tile size so a strand never overlaps itself.
        let half_length = (nf * 0.45).min((24.0 + rng.unit_f32() * 48.0) * grain);
        let width = (2.0 + rng.unit_f32() * 3.0) * grain;
        let half_width = 3.0 * width;
        let two_width_sq = 2.0 * width * width;
        let fibril_k = 2.0 * PI / ((3.0 + rng.unit_f32() * 3.0) * grain).max(2.5);
        let phase = rng.unit_f32() * 2.0 * PI;
        let amplitude = strength * (0.25 + rng.unit_f32() * 0.30);

        let extent_x = (dir_x.abs() * half_length + dir_y.abs() * half_width).ceil() as i64;
        let extent_y = (dir_y.abs() * half_length + dir_x.abs() * half_width).ceil() as i64;
        for dy in -extent_y..=extent_y {
            for dx in -extent_x..=extent_x {
                let along = dx as f32 * dir_x + dy as f32 * dir_y;
                let across = dy as f32 * dir_x - dx as f32 * dir_y;
                if along.abs() >= half_length || across.abs() >= half_width {
                    continue;
                }
                let taper = 0.5 + 0.5 * (PI * along / half_length).cos();
                let profile = (-across * across / two_width_sq).exp();
                let fibrils = ((across * fibril_k + phase).cos() + 1.0) * 0.5;
                let darkening = amplitude * taper * profile * fibrils;
                if darkening <= 0.0005 {
                    continue;
                }
                let index = wrap(cy + dy, n) * n + wrap(cx + dx, n);
                field[index] = (field[index] - darkening).max(0.0);
            }
        }
    }
}

/// Four octaves of tileable smoothstep value noise in [-1, 1].
fn surface_noise(size: usize, seed: u64, factor: usize) -> Vec<f32> {
    let mut rng = SplitMix64::new(seed);
    let mut out = vec![0.0f32; size * size];
    let factor = factor.max(1) as f32;
    let octaves = [(4.0, 0.40f32), (8.0, 0.30), (16.0, 0.20), (32.0, 0.10)];
    let total_weight: f32 = octaves.iter().map(|&(_, weight)| weight).sum();
    for (cell_points, weight) in octaves {
        let cell = ((cell_points * factor).round() as usize).max(1);
        let g = (size / cell).max(1);
        let grid: Vec<f32> = (0..g * g).map(|_| rng.unit_f32() * 2.0 - 1.0).collect();
        let w = weight / total_weight;
        for y in 0..size {
            let fy = y as f32 / cell as f32;
            let y0 = (fy as usize) % g;
            let y1 = (y0 + 1) % g;
            let ty = fy - (fy as usize) as f32;
            let sy = ty * ty * (3.0 - 2.0 * ty);
            for x in 0..size {
                let fx = x as f32 / cell as f32;
                let x0 = (fx as usize) % g;
                let x1 = (x0 + 1) % g;
                let tx = fx - (fx as usize) as f32;
                let sx = tx * tx * (3.0 - 2.0 * tx);
                let (a, b) = (grid[y0 * g + x0], grid[y0 * g + x1]);
                let (c, d) = (grid[y1 * g + x0], grid[y1 * g + x1]);
                let top = a + (b - a) * sx;
                let bottom = c + (d - c) * sx;
                out[y * size + x] += (top + (bottom - top) * sy) * w;
            }
        }
    }
    out
}

/// Elongated, tapered fiber splats driven by the weave amplitude.
fn stamp_fibers(field: &mut [f32], size: usize, amplitude: f32, pixel_scale: f32, rng: &mut SplitMix64) {
    if amplitude <= 0.001 {
        return;
    }
    let count = ((amplitude * 32.0).round() as i64).clamp(0, 48);
    let n = size as f32;
    for _ in 0..count {
        let cx = rng.unit_f32() * n;
        let cy = rng.unit_f32() * n;
        let angle = rng.unit_f32() * 2.0 * PI;
        let length = (24.0 + rng.unit_f32() * 40.0) * pixel_scale;
        let sign = if rng.unit_f32() < 0.5 { -1.0 } else { 1.0 };
        let intensity = sign * amplitude * (0.35 + rng.unit_f32() * 0.55);
        let (dx, dy) = (angle.cos(), angle.sin());
        let steps = ((length / 0.75) as i64).max(4);
        for step in 0..=steps {
            let t = step as f32 / steps as f32;
            let distance = (t - 0.5) * length;
            let taper = (PI * t).sin();
            splat(
                field,
                size,
                cx + dx * distance,
                cy + dy * distance,
                ((2.0 * pixel_scale).round() as i64).max(1),
                1.1 * pixel_scale,
                intensity * taper,
            );
        }
    }
}

/// Sparse bright and dark inclusions driven by the coarsest octave.
fn stamp_flecks(field: &mut [f32], size: usize, weight: f32, pixel_scale: f32, rng: &mut SplitMix64) {
    if weight <= 0.001 {
        return;
    }
    let count = ((weight * 90.0).round() as i64).clamp(0, 120);
    let n = size as f32;
    for _ in 0..count {
        let x = rng.unit_f32() * n;
        let y = rng.unit_f32() * n;
        let sign = if rng.unit_f32() < 0.5 { -1.0 } else { 1.0 };
        let intensity = sign * weight * (0.5 + rng.unit_f32() * 0.8);
        splat(field, size, x, y, (pixel_scale.round() as i64).max(1), 0.7 * pixel_scale, intensity);
    }
}

/// A small Gaussian bump at a fractional position, wrapping at the edges.
fn splat(field: &mut [f32], size: usize, x: f32, y: f32, radius: i64, sigma: f32, intensity: f32) {
    if intensity == 0.0 {
        return;
    }
    let ix = x.floor() as i64;
    let iy = y.floor() as i64;
    let two_sigma_sq = 2.0 * sigma * sigma;
    for dy in -radius..=radius {
        let wy = dy as f32 - (y - iy as f32);
        for dx in -radius..=radius {
            let wx = dx as f32 - (x - ix as f32);
            let weight = (-(wx * wx + wy * wy) / two_sigma_sq).exp();
            if weight <= 0.01 {
                continue;
            }
            let index = wrap(iy + dy, size) * size + wrap(ix + dx, size);
            field[index] = (field[index] + intensity * weight).clamp(0.0, 1.0);
        }
    }
}

fn wrap(value: i64, size: usize) -> usize {
    value.rem_euclid(size as i64) as usize
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::papers::{find, FiberConfig, PAPERS};

    fn paper(id: &str) -> Paper {
        *find(id).expect("built-in paper")
    }

    #[test]
    fn scale_normalizes_to_one_or_two() {
        assert_eq!(normalized_scale(1.0), 1);
        assert_eq!(normalized_scale(1.25), 1);
        assert_eq!(normalized_scale(1.5), 1);
        assert_eq!(normalized_scale(1.75), 2);
        assert_eq!(normalized_scale(3.0), 2);
    }

    #[test]
    fn fields_are_deterministic_bounded_and_sized_by_scale() {
        let soft_wove = paper("classic-matte");
        for scale in [1, 2] {
            let first = grain_field(&soft_wove, scale);
            assert_eq!(first.len(), (TILE_POINTS * scale).pow(2));
            assert_eq!(first, grain_field(&soft_wove, scale));
            assert!(first.iter().all(|value| (0.0..=1.0).contains(value)));
        }
    }

    #[test]
    fn seeds_give_each_paper_its_own_grain() {
        let mut reseeded = paper("classic-matte");
        reseeded.seed ^= 1;
        assert_ne!(grain_field(&paper("classic-matte"), 1), grain_field(&reseeded, 1));
    }

    #[test]
    fn fields_wrap_seamlessly() {
        // Across the tile's edge, neighbouring samples differ no more than
        // neighbouring samples inside it.
        for id in ["classic-matte", "artist-canvas", "parchment-grain"] {
            let field = grain_field(&paper(id), 1);
            let n = TILE_POINTS;
            let step = |a: usize, b: usize| (field[a] - field[b]).abs() as f64;
            let edge: f64 = (0..n).map(|y| step(y * n + n - 1, y * n)).sum::<f64>() / n as f64;
            let inside: f64 = (0..n)
                .flat_map(|y| (0..n - 1).map(move |x| (y, x)))
                .map(|(y, x)| step(y * n + x, y * n + x + 1))
                .sum::<f64>()
                / (n * (n - 1)) as f64;
            assert!(edge < inside * 1.5, "{id}: edge {edge} vs inside {inside}");
        }
    }

    #[test]
    fn fibers_and_roughness_only_darken() {
        let fibrous = paper("gesso-ground");
        let mut plain = fibrous;
        plain.fiber = FiberConfig { angle: fibrous.fiber.angle, strength: 0.0, roughness: 0.0 };
        let with_fibers = grain_field(&fibrous, 1);
        let without = grain_field(&plain, 1);
        assert!(with_fibers.iter().zip(&without).all(|(a, b)| *a <= *b + 1e-6));
        assert!(with_fibers.iter().zip(&without).any(|(a, b)| *a < *b - 0.01));
    }

    #[test]
    fn clear_veil_is_a_flat_tint_wash() {
        let tile = composite_tile(&paper("clear-veil"), 2);
        assert_eq!(tile.size, 512);
        let expected = [to_byte(0.35 * 0.16), to_byte(0.35 * 0.16), to_byte(0.35 * 0.16), to_byte(0.16)];
        assert!(tile.rgba.chunks_exact(4).all(|pixel| pixel == expected));
    }

    #[test]
    fn composites_are_premultiplied_and_never_thinner_than_the_wash() {
        for paper in &PAPERS {
            let tile = composite_tile(paper, 1);
            assert_eq!(tile.rgba.len(), TILE_POINTS * TILE_POINTS * 4);
            let wash = to_byte(paper.tint_alpha);
            for pixel in tile.rgba.chunks_exact(4) {
                assert!(pixel[3] as u16 + 1 >= wash as u16, "{}", paper.id);
                assert!(pixel[..3].iter().all(|&channel| channel <= pixel[3]), "{}", paper.id);
            }
        }
    }

    #[test]
    fn tiles_repeat_across_any_bitmap_size() {
        let tile = Tile { size: 2, rgba: (0..16).collect() };
        let (width, height) = (5, 3);
        let mut target = vec![0u8; width * height * 4];
        fill_tiled(&mut target, width, height, &tile);
        for y in 0..height {
            for x in 0..width {
                let source = ((y % 2) * 2 + x % 2) * 4;
                let pixel = (y * width + x) * 4;
                assert_eq!(target[pixel..pixel + 4], tile.rgba[source..source + 4], "({x}, {y})");
            }
        }
    }

    #[test]
    fn bgra_swaps_red_and_blue_only() {
        let tile = Tile { size: 1, rgba: vec![1, 2, 3, 4] };
        assert_eq!(tile.to_bgra().rgba, [3, 2, 1, 4]);
    }

    #[test]
    fn grain_is_visible_where_the_recipe_asks_for_it() {
        let tile = grain_tile(&paper("recycled-kraft"), 1);
        let covered = tile.rgba.chunks_exact(4).filter(|pixel| pixel[3] > 0).count();
        assert!(covered > tile.rgba.len() / 4 / 2);
    }
}
