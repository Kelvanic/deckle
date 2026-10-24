//! The running app's state and its transitions, free of Win32 so they can be
//! tested anywhere. Mirrors the macOS `AppState` rules: a snooze hides the
//! paper until it expires, toggling clears a snooze, and snoozes are never
//! saved, so quitting ends one.

use crate::papers::{self, Paper};
use crate::settings::{clamp_intensity, Settings};
use std::time::{Duration, SystemTime};

/// Snooze lengths offered in the menu, in minutes.
pub const SNOOZE_MINUTES: [u64; 4] = [15, 30, 60, 120];

#[derive(Clone, Debug, PartialEq)]
pub struct State {
    settings: Settings,
    snooze_until: Option<SystemTime>,
}

impl State {
    pub fn new(settings: Settings) -> Self {
        Self { settings, snooze_until: None }
    }

    pub fn settings(&self) -> &Settings {
        &self.settings
    }

    pub fn is_enabled(&self) -> bool {
        self.settings.enabled
    }

    pub fn intensity(&self) -> f64 {
        self.settings.intensity
    }

    pub fn paper(&self) -> &'static Paper {
        papers::find(self.settings.paper_id).unwrap_or_else(papers::default_paper)
    }

    pub fn snooze_remaining(&self, now: SystemTime) -> Option<Duration> {
        self.snooze_until.and_then(|until| until.duration_since(now).ok()).filter(|remaining| !remaining.is_zero())
    }

    pub fn is_snoozed(&self, now: SystemTime) -> bool {
        self.snooze_remaining(now).is_some()
    }

    pub fn should_show_overlay(&self, now: SystemTime) -> bool {
        self.settings.enabled && !self.is_snoozed(now)
    }

    /// The hotkey and menu toggle: hide a showing paper; otherwise end any
    /// snooze and show it.
    pub fn toggle(&mut self, now: SystemTime) {
        if self.should_show_overlay(now) {
            self.settings.enabled = false;
        } else {
            self.snooze_until = None;
            self.settings.enabled = true;
        }
    }

    pub fn snooze(&mut self, minutes: u64, now: SystemTime) {
        let minutes = minutes.clamp(1, 24 * 60);
        self.snooze_until = Some(now + Duration::from_secs(minutes * 60));
    }

    pub fn resume(&mut self) {
        self.snooze_until = None;
    }

    /// Drops a snooze that has run out. Returns true if one did.
    pub fn expire_snooze(&mut self, now: SystemTime) -> bool {
        if self.snooze_until.is_some() && !self.is_snoozed(now) {
            self.snooze_until = None;
            return true;
        }
        false
    }

    pub fn set_intensity(&mut self, intensity: f64) {
        if let Some(intensity) = clamp_intensity(intensity) {
            self.settings.intensity = intensity;
        }
    }

    pub fn select_paper(&mut self, id: &str) -> bool {
        match papers::find(id) {
            Some(paper) => {
                self.settings.paper_id = paper.id;
                true
            }
            None => false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(seconds: u64) -> SystemTime {
        SystemTime::UNIX_EPOCH + Duration::from_secs(1_700_000_000 + seconds)
    }

    #[test]
    fn snooze_hides_until_it_expires() {
        let mut state = State::new(Settings::default());
        state.snooze(30, at(0));
        assert!(!state.should_show_overlay(at(0)));
        assert_eq!(state.snooze_remaining(at(60)), Some(Duration::from_secs(29 * 60)));
        assert!(state.should_show_overlay(at(30 * 60)));
        assert!(state.expire_snooze(at(30 * 60)));
        assert!(!state.expire_snooze(at(30 * 60)));
    }

    #[test]
    fn toggle_matches_the_macos_hotkey() {
        let mut state = State::new(Settings::default());
        state.toggle(at(0));
        assert!(!state.is_enabled());
        state.toggle(at(0));
        assert!(state.should_show_overlay(at(0)));

        state.snooze(15, at(0));
        state.toggle(at(1));
        assert!(state.should_show_overlay(at(1)), "toggling a snoozed paper shows it again");
        assert!(!state.is_snoozed(at(1)));
    }

    #[test]
    fn snooze_is_clamped_and_resumable() {
        let mut state = State::new(Settings::default());
        state.snooze(0, at(0));
        assert_eq!(state.snooze_remaining(at(0)), Some(Duration::from_secs(60)));
        state.snooze(10_000, at(0));
        assert_eq!(state.snooze_remaining(at(0)), Some(Duration::from_secs(24 * 60 * 60)));
        state.resume();
        assert!(!state.is_snoozed(at(0)));
    }

    #[test]
    fn intensity_and_paper_changes_are_validated() {
        let mut state = State::new(Settings::default());
        state.set_intensity(0.9);
        assert_eq!(state.intensity(), 0.45);
        state.set_intensity(f64::NAN);
        assert_eq!(state.intensity(), 0.45);
        assert!(state.select_paper("espresso"));
        assert!(!state.select_paper("unknown"));
        assert_eq!(state.paper().id, "espresso");
        assert_eq!(state.settings().paper_id, "espresso");
    }
}
