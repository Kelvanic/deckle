//! The built-in paper library, copied value-for-value from
//! `Sources/Deckle/TexturePreset.swift`. Keep ids, seeds, and recipes in sync
//! with the macOS app: the id is what settings store, and the seed is what
//! makes a paper's grain its own.

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rgb {
    pub r: f64,
    pub g: f64,
    pub b: f64,
}

const fn rgb(r: f64, g: f64, b: f64) -> Rgb {
    Rgb { r, g, b }
}

const BLACK: Rgb = rgb(0.0, 0.0, 0.0);
const WHITE: Rgb = rgb(1.0, 1.0, 1.0);

/// One octave of the grain spectrum: coarser cells put energy at lower
/// spatial frequencies.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Octave {
    pub cell: u32,
    pub weight: f32,
}

const fn octave(cell: u32, weight: f32) -> Octave {
    Octave { cell, weight }
}

/// Woven crosshatch: period in logical pixels, and amplitude.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Weave {
    pub period: u32,
    pub amplitude: f32,
}

/// Fiber strands and surface roughness of the v4 engine.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FiberConfig {
    /// Dominant fiber orientation in radians (0 = horizontal, pi/2 = vertical).
    pub angle: f32,
    pub strength: f32,
    pub roughness: f32,
}

/// macOS applies this to every built-in that does not name its own config.
pub const DEFAULT_FIBER: FiberConfig = FiberConfig { angle: 0.3, strength: 0.30, roughness: 0.15 };

/// Where a paper sits in the menu.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Shelf {
    QuietReading,
    Light,
    Dark,
}

/// A built-in paper. Every built-in renders with the v4 spectral fiber engine.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Paper {
    pub id: &'static str,
    pub name: &'static str,
    pub subtitle: &'static str,
    /// Base tint wash laid under the grain.
    pub tint: Rgb,
    /// Opacity of the tint wash at full design strength.
    pub tint_alpha: f64,
    /// Grain colour for field values below the midpoint.
    pub dark_color: Rgb,
    /// Grain colour for field values above the midpoint.
    pub light_color: Rgb,
    pub dark_strength: f32,
    pub light_strength: f32,
    pub octaves: &'static [Octave],
    pub weave: Option<Weave>,
    pub is_dark: bool,
    pub seed: u64,
    pub fiber: FiberConfig,
    pub shelf: Shelf,
}

const BASE: Paper = Paper {
    id: "",
    name: "",
    subtitle: "",
    tint: WHITE,
    tint_alpha: 0.0,
    dark_color: BLACK,
    light_color: WHITE,
    dark_strength: 0.0,
    light_strength: 0.0,
    octaves: &[],
    weave: None,
    is_dark: false,
    seed: 0,
    fiber: DEFAULT_FIBER,
    shelf: Shelf::Light,
};

/// Every built-in paper, in the macOS library order: the quiet reading
/// collection first, then the light and dark papers.
pub static PAPERS: [Paper; 26] = [
    // Quiet reading collection
    Paper {
        id: "clear-veil",
        name: "Clear Veil",
        subtitle: "Neutral dimming, no grain",
        tint: rgb(0.35, 0.35, 0.35),
        tint_alpha: 0.16,
        dark_color: BLACK,
        light_color: WHITE,
        dark_strength: 0.0,
        light_strength: 0.0,
        octaves: &[octave(1, 1.0)],
        seed: 0x434C454152,
        fiber: FiberConfig { angle: 0.0, strength: 0.0, roughness: 0.0 },
        shelf: Shelf::QuietReading,
        ..BASE
    },
    Paper {
        id: "book-cream",
        name: "Book Cream",
        subtitle: "Faint warmth, barely-there grain",
        tint: rgb(0.60, 0.50, 0.35),
        tint_alpha: 0.20,
        dark_color: rgb(0.25, 0.22, 0.17),
        light_color: rgb(0.80, 0.77, 0.70),
        dark_strength: 0.035,
        light_strength: 0.005,
        octaves: &[octave(1, 0.85), octave(2, 0.15)],
        seed: 0x424F4F4B,
        fiber: FiberConfig { angle: 0.2, strength: 0.015, roughness: 0.01 },
        shelf: Shelf::QuietReading,
        ..BASE
    },
    Paper {
        id: "quiet-gray",
        name: "Quiet Gray",
        subtitle: "Balanced gray, fine quiet grain",
        tint: rgb(0.30, 0.31, 0.32),
        tint_alpha: 0.22,
        dark_color: rgb(0.15, 0.16, 0.17),
        light_color: rgb(0.65, 0.66, 0.67),
        dark_strength: 0.025,
        light_strength: 0.003,
        octaves: &[octave(1, 0.9), octave(2, 0.1)],
        seed: 0x47524159,
        fiber: FiberConfig { angle: 0.0, strength: 0.01, roughness: 0.005 },
        shelf: Shelf::QuietReading,
        ..BASE
    },
    Paper {
        id: "evening-shade",
        name: "Evening Shade",
        subtitle: "Deeper dimming, minimal texture",
        tint: rgb(0.08, 0.07, 0.06),
        tint_alpha: 0.40,
        dark_color: BLACK,
        light_color: rgb(0.25, 0.23, 0.21),
        dark_strength: 0.015,
        light_strength: 0.002,
        octaves: &[octave(1, 1.0)],
        is_dark: true,
        seed: 0x4556454E494E47,
        fiber: FiberConfig { angle: 0.0, strength: 0.005, roughness: 0.005 },
        shelf: Shelf::QuietReading,
        ..BASE
    },
    // Light papers
    Paper {
        id: "classic-matte",
        name: "Soft Wove",
        subtitle: "Smooth, even-milled finish",
        tint: rgb(0.98, 0.96, 0.92),
        tint_alpha: 0.35,
        dark_color: rgb(0.25, 0.22, 0.18),
        light_color: WHITE,
        dark_strength: 0.50,
        light_strength: 0.35,
        octaves: &[octave(1, 0.50), octave(2, 0.30), octave(4, 0.20)],
        seed: 0xC7961D948ED7998F,
        ..BASE
    },
    Paper {
        id: "rice-paper",
        name: "Rice Paper",
        subtitle: "Feather-light, near invisible",
        tint: rgb(0.98, 0.97, 0.94),
        tint_alpha: 0.40,
        dark_color: rgb(0.40, 0.38, 0.32),
        light_color: WHITE,
        dark_strength: 0.30,
        light_strength: 0.50,
        octaves: &[octave(1, 0.30), octave(4, 0.40), octave(8, 0.30)],
        seed: 0x7272C412F6B61BED,
        ..BASE
    },
    Paper {
        id: "whisper-weave",
        name: "Laid Cotton",
        subtitle: "Fine ribbed cotton sheet",
        tint: rgb(0.97, 0.95, 0.93),
        tint_alpha: 0.32,
        dark_color: rgb(0.28, 0.25, 0.22),
        light_color: WHITE,
        dark_strength: 0.45,
        light_strength: 0.40,
        octaves: &[octave(1, 0.40), octave(2, 0.35), octave(4, 0.25)],
        weave: Some(Weave { period: 8, amplitude: 0.12 }),
        seed: 0x93E20FBC9E404AEC,
        ..BASE
    },
    Paper {
        id: "newsprint",
        name: "Newsprint",
        subtitle: "Cool gray daily-paper stock",
        tint: rgb(0.93, 0.93, 0.92),
        tint_alpha: 0.38,
        dark_color: rgb(0.25, 0.25, 0.25),
        light_color: WHITE,
        dark_strength: 0.50,
        light_strength: 0.30,
        octaves: &[octave(1, 0.55), octave(2, 0.30), octave(4, 0.15)],
        seed: 0x377D226124C9CCF,
        ..BASE
    },
    Paper {
        id: "painters-press",
        name: "Cold Press",
        subtitle: "Rough watercolor stock",
        tint: rgb(0.96, 0.95, 0.92),
        tint_alpha: 0.35,
        dark_color: rgb(0.30, 0.28, 0.25),
        light_color: WHITE,
        dark_strength: 0.55,
        light_strength: 0.40,
        octaves: &[octave(1, 0.30), octave(2, 0.25), octave(4, 0.20), octave(16, 0.25)],
        seed: 0x8B246A4C71E884E5,
        ..BASE
    },
    Paper {
        id: "artist-canvas",
        name: "Artist Canvas",
        subtitle: "Coarse stretched weave",
        tint: rgb(0.94, 0.91, 0.84),
        tint_alpha: 0.40,
        dark_color: rgb(0.32, 0.28, 0.22),
        light_color: rgb(1.0, 0.98, 0.93),
        dark_strength: 0.50,
        light_strength: 0.40,
        octaves: &[octave(1, 0.30), octave(2, 0.30), octave(4, 0.40)],
        weave: Some(Weave { period: 10, amplitude: 0.28 }),
        seed: 0x9DE627723A756745,
        ..BASE
    },
    Paper {
        id: "sunbaked-parchment",
        name: "Foxed Amber",
        subtitle: "Age-warmed amber grain",
        tint: rgb(0.93, 0.82, 0.60),
        tint_alpha: 0.48,
        dark_color: rgb(0.36, 0.26, 0.10),
        light_color: rgb(1.0, 0.95, 0.82),
        dark_strength: 0.50,
        light_strength: 0.30,
        octaves: &[octave(1, 0.35), octave(2, 0.25), octave(4, 0.20), octave(16, 0.20)],
        seed: 0xFAF968E9FD88861,
        ..BASE
    },
    Paper {
        id: "saddle-linen",
        name: "Bookcloth",
        subtitle: "Binder's linen weave",
        tint: rgb(0.88, 0.80, 0.68),
        tint_alpha: 0.45,
        dark_color: rgb(0.30, 0.24, 0.16),
        light_color: rgb(0.99, 0.96, 0.90),
        dark_strength: 0.50,
        light_strength: 0.35,
        octaves: &[octave(1, 0.35), octave(2, 0.35), octave(4, 0.30)],
        weave: Some(Weave { period: 6, amplitude: 0.20 }),
        seed: 0xDABC481A6E28F0F5,
        ..BASE
    },
    Paper {
        id: "recycled-kraft",
        name: "Recycled Kraft",
        subtitle: "Rough brown packing stock",
        tint: rgb(0.76, 0.62, 0.45),
        tint_alpha: 0.50,
        dark_color: rgb(0.30, 0.22, 0.12),
        light_color: rgb(0.95, 0.88, 0.75),
        dark_strength: 0.55,
        light_strength: 0.30,
        octaves: &[octave(1, 0.30), octave(2, 0.20), octave(4, 0.20), octave(16, 0.30)],
        seed: 0xDB6B807523843F95,
        ..BASE
    },
    Paper {
        id: "mulberry-veil",
        name: "Plum Kozo",
        subtitle: "Plum-washed kozo fibre",
        tint: rgb(0.85, 0.78, 0.86),
        tint_alpha: 0.42,
        dark_color: rgb(0.30, 0.20, 0.30),
        light_color: rgb(0.98, 0.95, 1.0),
        dark_strength: 0.45,
        light_strength: 0.35,
        octaves: &[octave(1, 0.45), octave(2, 0.30), octave(4, 0.25)],
        seed: 0xB5967DD1F65D7714,
        ..BASE
    },
    Paper {
        id: "rose-quartz",
        name: "Rose Quartz",
        subtitle: "Soft blush wash",
        tint: rgb(0.93, 0.83, 0.84),
        tint_alpha: 0.45,
        dark_color: rgb(0.35, 0.22, 0.24),
        light_color: rgb(1.0, 0.96, 0.96),
        dark_strength: 0.40,
        light_strength: 0.35,
        octaves: &[octave(1, 0.45), octave(2, 0.30), octave(4, 0.25)],
        seed: 0xC0CC582D31372172,
        ..BASE
    },
    Paper {
        id: "sage-press",
        name: "Sage Press",
        subtitle: "Muted botanical green",
        tint: rgb(0.80, 0.86, 0.76),
        tint_alpha: 0.45,
        dark_color: rgb(0.22, 0.30, 0.20),
        light_color: rgb(0.95, 1.0, 0.92),
        dark_strength: 0.45,
        light_strength: 0.30,
        octaves: &[octave(1, 0.40), octave(2, 0.30), octave(4, 0.30)],
        seed: 0x7272E43507ED9DFF,
        ..BASE
    },
    Paper {
        id: "nordic-sky",
        name: "Nordic Sky",
        subtitle: "Cool pale blue",
        tint: rgb(0.80, 0.87, 0.93),
        tint_alpha: 0.45,
        dark_color: rgb(0.18, 0.26, 0.34),
        light_color: rgb(0.94, 0.98, 1.0),
        dark_strength: 0.40,
        light_strength: 0.35,
        octaves: &[octave(1, 0.45), octave(2, 0.30), octave(4, 0.25)],
        seed: 0x7272237CB7458AE8,
        ..BASE
    },
    Paper {
        id: "vellum-mist",
        name: "Frost Glassine",
        subtitle: "Translucent frosted haze",
        tint: rgb(0.97, 0.97, 0.98),
        tint_alpha: 0.50,
        dark_color: rgb(0.45, 0.45, 0.48),
        light_color: WHITE,
        dark_strength: 0.25,
        light_strength: 0.60,
        octaves: &[octave(1, 0.40), octave(2, 0.30), octave(8, 0.30)],
        seed: 0xC0E06D51FCA203E4,
        ..BASE
    },
    Paper {
        id: "monastic-felt",
        name: "Felt Side",
        subtitle: "The sheet's soft felt side",
        tint: rgb(0.85, 0.86, 0.82),
        tint_alpha: 0.45,
        dark_color: rgb(0.28, 0.30, 0.26),
        light_color: rgb(0.97, 0.98, 0.95),
        dark_strength: 0.45,
        light_strength: 0.35,
        octaves: &[octave(2, 0.30), octave(4, 0.40), octave(8, 0.30)],
        seed: 0xB16BE8D7268391BB,
        ..BASE
    },
    // Dark papers
    Paper {
        id: "carbon-ledger",
        name: "Ink Stone",
        subtitle: "Ground-ink black",
        tint: rgb(0.12, 0.12, 0.13),
        tint_alpha: 0.38,
        dark_color: rgb(0.02, 0.02, 0.03),
        light_color: rgb(0.80, 0.80, 0.85),
        dark_strength: 0.30,
        light_strength: 0.45,
        octaves: &[octave(1, 0.45), octave(2, 0.30), octave(4, 0.25)],
        is_dark: true,
        seed: 0xC0389DD22BCB37BA,
        shelf: Shelf::Dark,
        ..BASE
    },
    Paper {
        id: "midnight-slate",
        name: "Midnight Slate",
        subtitle: "Blue-black stone",
        tint: rgb(0.10, 0.12, 0.16),
        tint_alpha: 0.40,
        dark_color: rgb(0.01, 0.02, 0.04),
        light_color: rgb(0.65, 0.72, 0.85),
        dark_strength: 0.30,
        light_strength: 0.40,
        octaves: &[octave(1, 0.40), octave(2, 0.30), octave(8, 0.30)],
        is_dark: true,
        seed: 0x4D4937A7157ED0FF,
        shelf: Shelf::Dark,
        ..BASE
    },
    Paper {
        id: "espresso",
        name: "Espresso",
        subtitle: "Warm near-black roast",
        tint: rgb(0.14, 0.10, 0.08),
        tint_alpha: 0.40,
        dark_color: rgb(0.03, 0.02, 0.01),
        light_color: rgb(0.85, 0.75, 0.65),
        dark_strength: 0.30,
        light_strength: 0.40,
        octaves: &[octave(1, 0.40), octave(2, 0.30), octave(4, 0.30)],
        is_dark: true,
        seed: 0x1AE701539F9C19,
        shelf: Shelf::Dark,
        ..BASE
    },
    // Fiber-forward light papers
    Paper {
        id: "gesso-ground",
        name: "Gesso Ground",
        subtitle: "Sized artist's ground, matte fiber veil",
        tint: rgb(0.86, 0.84, 0.79),
        tint_alpha: 0.48,
        dark_color: rgb(0.38, 0.35, 0.30),
        light_color: rgb(0.97, 0.96, 0.93),
        dark_strength: 0.45,
        light_strength: 0.25,
        octaves: &[octave(1, 0.35), octave(2, 0.35), octave(4, 0.30)],
        seed: 0x9E3779B97F4A7C15,
        fiber: FiberConfig { angle: 0.9, strength: 0.45, roughness: 0.20 },
        ..BASE
    },
    Paper {
        id: "linen-veil",
        name: "Linen Veil",
        subtitle: "Cool blue-gray with woven fiber alignment",
        tint: rgb(0.80, 0.83, 0.86),
        tint_alpha: 0.50,
        dark_color: rgb(0.32, 0.36, 0.42),
        light_color: rgb(0.96, 0.97, 0.98),
        dark_strength: 0.40,
        light_strength: 0.20,
        octaves: &[octave(1, 0.30), octave(2, 0.30), octave(4, 0.40)],
        seed: 0xBF58476D1CE4E5B9,
        fiber: FiberConfig { angle: 1.57, strength: 0.50, roughness: 0.15 },
        ..BASE
    },
    Paper {
        id: "parchment-grain",
        name: "Parchment Grain",
        subtitle: "Warm parchment with coarse tooth",
        tint: rgb(0.84, 0.74, 0.58),
        tint_alpha: 0.52,
        dark_color: rgb(0.40, 0.32, 0.20),
        light_color: rgb(0.96, 0.91, 0.80),
        dark_strength: 0.50,
        light_strength: 0.20,
        octaves: &[octave(1, 0.30), octave(2, 0.25), octave(4, 0.25), octave(16, 0.20)],
        seed: 0x94D049BB133111EB,
        fiber: FiberConfig { angle: 0.35, strength: 0.35, roughness: 0.35 },
        ..BASE
    },
    // Fiber-forward dark paper
    Paper {
        id: "slate-veil",
        name: "Slate Veil",
        subtitle: "Deep slate with visible fiber strands",
        tint: rgb(0.16, 0.18, 0.22),
        tint_alpha: 0.45,
        dark_color: rgb(0.05, 0.06, 0.08),
        light_color: rgb(0.55, 0.60, 0.68),
        dark_strength: 0.35,
        light_strength: 0.30,
        octaves: &[octave(1, 0.40), octave(2, 0.30), octave(4, 0.30)],
        is_dark: true,
        seed: 0xA5B9C4E3D2F10678,
        fiber: FiberConfig { angle: 1.1, strength: 0.40, roughness: 0.25 },
        shelf: Shelf::Dark,
        ..BASE
    },
];

/// New installations start on Clear Veil, as on macOS.
pub fn default_paper() -> &'static Paper {
    &PAPERS[0]
}

pub fn find(id: &str) -> Option<&'static Paper> {
    PAPERS.iter().find(|paper| paper.id == id)
}

pub fn index_of(id: &str) -> Option<usize> {
    PAPERS.iter().position(|paper| paper.id == id)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn library_matches_the_macos_ids_and_order() {
        let ids: Vec<&str> = PAPERS.iter().map(|paper| paper.id).collect();
        assert_eq!(
            ids,
            [
                "clear-veil",
                "book-cream",
                "quiet-gray",
                "evening-shade",
                "classic-matte",
                "rice-paper",
                "whisper-weave",
                "newsprint",
                "painters-press",
                "artist-canvas",
                "sunbaked-parchment",
                "saddle-linen",
                "recycled-kraft",
                "mulberry-veil",
                "rose-quartz",
                "sage-press",
                "nordic-sky",
                "vellum-mist",
                "monastic-felt",
                "carbon-ledger",
                "midnight-slate",
                "espresso",
                "gesso-ground",
                "linen-veil",
                "parchment-grain",
                "slate-veil",
            ]
        );
        assert_eq!(ids.iter().collect::<HashSet<_>>().len(), PAPERS.len());
    }

    #[test]
    fn shelves_follow_the_library_grouping() {
        let quiet: Vec<&str> =
            PAPERS.iter().filter(|paper| paper.shelf == Shelf::QuietReading).map(|paper| paper.id).collect();
        assert_eq!(quiet, ["clear-veil", "book-cream", "quiet-gray", "evening-shade"]);
        for paper in PAPERS.iter().filter(|paper| paper.shelf != Shelf::QuietReading) {
            assert_eq!(paper.is_dark, paper.shelf == Shelf::Dark, "{}", paper.id);
        }
    }

    #[test]
    fn every_paper_is_well_formed() {
        for paper in &PAPERS {
            assert!(!paper.name.is_empty() && !paper.subtitle.is_empty(), "{}", paper.id);
            assert!(!paper.octaves.is_empty(), "{}", paper.id);
            assert!(paper.octaves.iter().all(|octave| octave.cell.is_power_of_two()), "{}", paper.id);
            assert!((0.0..=1.0).contains(&paper.tint_alpha), "{}", paper.id);
        }
    }

    #[test]
    fn lookups_resolve_ids() {
        assert_eq!(default_paper().id, "clear-veil");
        assert_eq!(find("carbon-ledger").map(|paper| paper.name), Some("Ink Stone"));
        assert_eq!(index_of("slate-veil"), Some(25));
        assert!(find("missing").is_none());
    }
}
