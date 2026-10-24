//! Saved settings: a few `key=value` lines in `%APPDATA%\Deckle\settings.ini`.
//! Loading is tolerant. Unknown keys are ignored, and a missing or invalid
//! value falls back to its default, so a damaged file never stops Deckle.

use crate::papers;
use std::path::{Path, PathBuf};

pub const MIN_INTENSITY: f64 = 0.05;
pub const MAX_INTENSITY: f64 = 0.45;
pub const DEFAULT_INTENSITY: f64 = 0.22;

#[derive(Clone, Debug, PartialEq)]
pub struct Settings {
    pub enabled: bool,
    pub intensity: f64,
    pub paper_id: &'static str,
}

impl Default for Settings {
    fn default() -> Self {
        Self { enabled: true, intensity: DEFAULT_INTENSITY, paper_id: papers::default_paper().id }
    }
}

/// Intensity clamped to the overlay's range; non-finite input is refused.
pub fn clamp_intensity(value: f64) -> Option<f64> {
    value.is_finite().then(|| value.clamp(MIN_INTENSITY, MAX_INTENSITY))
}

impl Settings {
    pub fn parse(text: &str) -> Self {
        let mut settings = Self::default();
        for line in text.lines() {
            let line = line.trim();
            if line.starts_with('#') {
                continue;
            }
            let Some((key, value)) = line.split_once('=') else { continue };
            let value = value.trim();
            match key.trim() {
                "enabled" => {
                    if let Ok(enabled) = value.parse() {
                        settings.enabled = enabled;
                    }
                }
                "intensity" => {
                    if let Some(intensity) = value.parse().ok().and_then(clamp_intensity) {
                        settings.intensity = intensity;
                    }
                }
                "paper" => {
                    if let Some(paper) = papers::find(value) {
                        settings.paper_id = paper.id;
                    }
                }
                _ => {}
            }
        }
        settings
    }

    pub fn serialize(&self) -> String {
        format!(
            "# Deckle for Windows settings\nenabled={}\nintensity={}\npaper={}\n",
            self.enabled, self.intensity, self.paper_id
        )
    }

    /// Missing or unreadable files load as defaults.
    pub fn load(path: &Path) -> Self {
        std::fs::read_to_string(path).map(|text| Self::parse(&text)).unwrap_or_default()
    }

    /// Writes a sibling file and renames it over the old one, so a crash
    /// mid-write never leaves a truncated file behind.
    pub fn save(&self, path: &Path) -> std::io::Result<()> {
        if let Some(directory) = path.parent() {
            std::fs::create_dir_all(directory)?;
        }
        let staging = path.with_extension("ini.tmp");
        std::fs::write(&staging, self.serialize())?;
        std::fs::rename(&staging, path)
    }
}

/// `%APPDATA%\Deckle\settings.ini`, given the value of `APPDATA`.
pub fn path_in(app_data: Option<&Path>) -> Option<PathBuf> {
    app_data.filter(|path| !path.as_os_str().is_empty()).map(|path| path.join("Deckle").join("settings.ini"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips() {
        let settings = Settings { enabled: false, intensity: 0.3, paper_id: "carbon-ledger" };
        assert_eq!(Settings::parse(&settings.serialize()), settings);
    }

    #[test]
    fn invalid_values_fall_back_without_losing_the_rest() {
        let settings = Settings::parse("enabled=maybe\nintensity=NaN\npaper=nope\nextra=1\n");
        assert_eq!(settings, Settings::default());
        let settings = Settings::parse("  intensity = 9 \n paper = espresso\nenabled=false");
        assert_eq!(settings.intensity, MAX_INTENSITY);
        assert_eq!(settings.paper_id, "espresso");
        assert!(!settings.enabled);
        assert_eq!(Settings::parse("intensity=0.01").intensity, MIN_INTENSITY);
    }

    #[test]
    fn defaults_match_a_new_macos_installation() {
        let settings = Settings::default();
        assert!(settings.enabled);
        assert_eq!(settings.intensity, 0.22);
        assert_eq!(settings.paper_id, "clear-veil");
    }

    #[test]
    fn saves_atomically_and_loads_back() {
        let directory = std::env::temp_dir().join(format!("deckle-settings-{}", std::process::id()));
        let path = path_in(Some(&directory)).expect("path");
        let settings = Settings { enabled: true, intensity: 0.4, paper_id: "sage-press" };
        settings.save(&path).expect("save");
        assert_eq!(Settings::load(&path), settings);
        assert!(!path.with_extension("ini.tmp").exists());
        std::fs::remove_dir_all(&directory).ok();
        assert_eq!(Settings::load(&path), Settings::default());
    }

    #[test]
    fn needs_an_app_data_folder() {
        assert_eq!(path_in(None), None);
        assert_eq!(path_in(Some(Path::new(""))), None);
    }
}
