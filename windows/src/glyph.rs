//! The tray icon, drawn in code: a sheet of paper with a folded corner and
//! three lines of type. It is cream with rust type while the paper shows, and
//! a faded grey sheet while it is off or snoozed.

#[derive(Clone, Copy)]
struct Point {
    x: f64,
    y: f64,
}

fn distance_to_segment(p: Point, a: Point, b: Point) -> f64 {
    let (dx, dy) = (b.x - a.x, b.y - a.y);
    let t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)).clamp(0.0, 1.0);
    ((p.x - a.x - t * dx).powi(2) + (p.y - a.y - t * dy).powi(2)).sqrt()
}

/// Inside a convex polygon listed clockwise in screen coordinates (y down).
fn inside(p: Point, polygon: &[Point]) -> bool {
    polygon
        .iter()
        .zip(polygon.iter().cycle().skip(1))
        .all(|(a, b)| (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) >= 0.0)
}

fn edge_distance(p: Point, polygon: &[Point]) -> f64 {
    polygon
        .iter()
        .zip(polygon.iter().cycle().skip(1))
        .map(|(a, b)| distance_to_segment(p, *a, *b))
        .fold(f64::INFINITY, f64::min)
}

/// Straight-alpha RGBA, top row first, `size` x `size` pixels.
pub fn tray_glyph(size: usize, on: bool) -> Vec<u8> {
    let s = size as f64;
    let (left, right, top, bottom, fold) = (0.18 * s, 0.82 * s, 0.08 * s, 0.92 * s, 0.26 * s);
    let sheet = [
        Point { x: left, y: top },
        Point { x: right - fold, y: top },
        Point { x: right, y: top + fold },
        Point { x: right, y: bottom },
        Point { x: left, y: bottom },
    ];
    let flap = [
        Point { x: right - fold, y: top },
        Point { x: right, y: top + fold },
        Point { x: right - fold, y: top + fold },
    ];
    let stroke = (s / 16.0).max(1.0);
    let line_height = (s / 14.0).max(1.0);
    let lines = [0.48, 0.63, 0.78].map(|y| (y * s, y * s + line_height));
    let (line_left, line_right) = (left + 0.12 * s, right - 0.12 * s);

    let ink = [0.16, 0.15, 0.13];
    let (paper, flap_color, type_color, opacity) = if on {
        ([0.97, 0.95, 0.90], [0.84, 0.80, 0.72], [0.70, 0.29, 0.13], 1.0)
    } else {
        ([0.80, 0.80, 0.80], [0.66, 0.66, 0.66], [0.45, 0.45, 0.45], 0.55)
    };

    let samples = 4;
    let mut pixels = vec![0u8; size * size * 4];
    for py in 0..size {
        for px in 0..size {
            let mut premultiplied = [0.0f64; 4];
            for sy in 0..samples {
                for sx in 0..samples {
                    let p = Point {
                        x: px as f64 + (sx as f64 + 0.5) / samples as f64,
                        y: py as f64 + (sy as f64 + 0.5) / samples as f64,
                    };
                    if !inside(p, &sheet) {
                        continue;
                    }
                    let in_line =
                        lines.iter().any(|&(y0, y1)| p.y >= y0 && p.y < y1) && p.x >= line_left && p.x < line_right;
                    let color = if edge_distance(p, &sheet) < stroke
                        || (inside(p, &flap) && edge_distance(p, &flap) < stroke)
                    {
                        ink
                    } else if inside(p, &flap) {
                        flap_color
                    } else if in_line {
                        type_color
                    } else {
                        paper
                    };
                    for channel in 0..3 {
                        premultiplied[channel] += color[channel] * opacity;
                    }
                    premultiplied[3] += opacity;
                }
            }
            let count = (samples * samples) as f64;
            let alpha = premultiplied[3] / count;
            let o = (py * size + px) * 4;
            if alpha > 0.0 {
                for channel in 0..3 {
                    pixels[o + channel] = (premultiplied[channel] / count / alpha * 255.0).round() as u8;
                }
                pixels[o + 3] = (alpha * 255.0).round() as u8;
            }
        }
    }
    pixels
}

#[cfg(test)]
mod tests {
    use super::*;

    fn alpha(pixels: &[u8], size: usize, x: usize, y: usize) -> u8 {
        pixels[(y * size + x) * 4 + 3]
    }

    #[test]
    fn draws_an_opaque_sheet_with_transparent_margins() {
        for size in [16, 20, 24, 32, 48] {
            let pixels = tray_glyph(size, true);
            assert_eq!(pixels.len(), size * size * 4);
            assert_eq!(alpha(&pixels, size, 0, 0), 0);
            assert_eq!(alpha(&pixels, size, size - 1, 0), 0, "the folded corner is cut away");
            assert_eq!(alpha(&pixels, size, size / 2, size / 2), 255);
        }
    }

    #[test]
    fn off_state_is_faded_and_distinct() {
        let on = tray_glyph(32, true);
        let off = tray_glyph(32, false);
        assert_ne!(on, off);
        let max_off = off.chunks_exact(4).map(|pixel| pixel[3]).max().unwrap_or(0);
        assert!(max_off < 160);
    }
}
