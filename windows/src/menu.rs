//! The tray menu as plain data. The Win32 layer turns it into an `HMENU` and
//! maps the chosen id back to a `Command`, so labels, checkmarks, and ids are
//! all testable without Windows.

use crate::papers::{Shelf, PAPERS};
use crate::state::{State, SNOOZE_MINUTES};
use std::time::SystemTime;

/// Intensities offered in the menu. 22% is the default; the range matches
/// the macOS slider.
pub const INTENSITY_STEPS: [f64; 8] = [0.05, 0.10, 0.15, 0.18, 0.22, 0.30, 0.38, 0.45];

pub const HOTKEY_LABEL: &str = "Ctrl+Alt+P";

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Command {
    Toggle,
    Resume,
    Quit,
    Snooze(u64),
    Intensity(f64),
    Paper(&'static str),
}

const TOGGLE_ID: u32 = 1;
const RESUME_ID: u32 = 2;
const QUIT_ID: u32 = 3;
const SNOOZE_BASE: u32 = 100;
const INTENSITY_BASE: u32 = 200;
const PAPER_BASE: u32 = 1000;

impl Command {
    /// Menu item id. Never zero: `TrackPopupMenu` reports zero for "nothing".
    pub fn id(self) -> u32 {
        match self {
            Command::Toggle => TOGGLE_ID,
            Command::Resume => RESUME_ID,
            Command::Quit => QUIT_ID,
            Command::Snooze(minutes) => {
                SNOOZE_BASE + SNOOZE_MINUTES.iter().position(|&m| m == minutes).unwrap_or(0) as u32
            }
            Command::Intensity(value) => {
                INTENSITY_BASE + INTENSITY_STEPS.iter().position(|&step| step == value).unwrap_or(0) as u32
            }
            Command::Paper(id) => PAPER_BASE + PAPERS.iter().position(|paper| paper.id == id).unwrap_or(0) as u32,
        }
    }

    pub fn from_id(id: u32) -> Option<Command> {
        let index = |base: u32| id.checked_sub(base).map(|offset| offset as usize);
        match id {
            TOGGLE_ID => Some(Command::Toggle),
            RESUME_ID => Some(Command::Resume),
            QUIT_ID => Some(Command::Quit),
            _ if id >= PAPER_BASE => {
                index(PAPER_BASE).and_then(|i| PAPERS.get(i)).map(|paper| Command::Paper(paper.id))
            }
            _ if id >= INTENSITY_BASE => {
                index(INTENSITY_BASE).and_then(|i| INTENSITY_STEPS.get(i)).map(|&step| Command::Intensity(step))
            }
            _ if id >= SNOOZE_BASE => {
                index(SNOOZE_BASE).and_then(|i| SNOOZE_MINUTES.get(i)).map(|&minutes| Command::Snooze(minutes))
            }
            _ => None,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum Item {
    Action {
        label: String,
        command: Command,
        checked: bool,
        enabled: bool,
    },
    /// A greyed-out line of information or a section heading.
    Note(String),
    Separator,
    Submenu {
        label: String,
        items: Vec<Item>,
        enabled: bool,
    },
}

fn action(label: impl Into<String>, command: Command, checked: bool) -> Item {
    Item::Action { label: label.into(), command, checked, enabled: true }
}

pub fn snooze_label(minutes: u64) -> String {
    match minutes {
        60 => "1 hour".to_string(),
        m if m % 60 == 0 => format!("{} hours", m / 60),
        m => format!("{m} minutes"),
    }
}

pub fn percent_label(intensity: f64) -> String {
    format!("{}%", (intensity * 100.0).round() as i64)
}

/// The step the current intensity is closest to.
pub fn nearest_intensity_step(intensity: f64) -> f64 {
    INTENSITY_STEPS
        .iter()
        .copied()
        .min_by(|a, b| (a - intensity).abs().total_cmp(&(b - intensity).abs()))
        .unwrap_or(INTENSITY_STEPS[0])
}

/// Tooltip shown when hovering the tray icon.
pub fn tooltip(state: &State, now: SystemTime) -> String {
    let paper = state.paper().name;
    if !state.is_enabled() {
        format!("Deckle: off ({paper})")
    } else if state.is_snoozed(now) {
        format!("Deckle: snoozed ({paper})")
    } else {
        format!("Deckle: {paper} at {}", percent_label(state.intensity()))
    }
}

pub fn tray_menu(state: &State, now: SystemTime, hotkey_registered: bool) -> Vec<Item> {
    let mut items = vec![Item::Note(format!("Deckle: {}", state.paper().name)), Item::Separator];

    let toggle_label = if hotkey_registered { format!("Show paper\t{HOTKEY_LABEL}") } else { "Show paper".to_string() };
    items.push(action(toggle_label, Command::Toggle, state.should_show_overlay(now)));

    if let Some(remaining) = state.snooze_remaining(now) {
        let minutes = remaining.as_secs().div_ceil(60);
        let unit = if minutes == 1 { "minute" } else { "minutes" };
        items.push(Item::Note(format!("Snoozed, {minutes} {unit} left")));
        items.push(action("Resume now", Command::Resume, false));
    }
    items.push(Item::Submenu {
        label: "Snooze".to_string(),
        items: SNOOZE_MINUTES
            .iter()
            .map(|&minutes| action(snooze_label(minutes), Command::Snooze(minutes), false))
            .collect(),
        enabled: state.is_enabled(),
    });
    items.push(Item::Separator);

    let selected = state.paper().id;
    let mut paper_items = Vec::new();
    for (shelf, heading) in
        [(Shelf::QuietReading, "Quiet reading"), (Shelf::Light, "Light papers"), (Shelf::Dark, "Dark papers")]
    {
        if !paper_items.is_empty() {
            paper_items.push(Item::Separator);
        }
        paper_items.push(Item::Note(heading.to_string()));
        paper_items.extend(
            PAPERS
                .iter()
                .filter(|paper| paper.shelf == shelf)
                .map(|paper| action(paper.name, Command::Paper(paper.id), paper.id == selected)),
        );
    }
    items.push(Item::Submenu { label: "Paper".to_string(), items: paper_items, enabled: true });

    let current = nearest_intensity_step(state.intensity());
    items.push(Item::Submenu {
        label: format!("Intensity ({})", percent_label(state.intensity())),
        items: INTENSITY_STEPS
            .iter()
            .map(|&step| action(percent_label(step), Command::Intensity(step), step == current))
            .collect(),
        enabled: true,
    });
    items.push(Item::Separator);

    if !hotkey_registered {
        items.push(Item::Note(format!("{HOTKEY_LABEL} is unavailable")));
    }
    items.push(action("Quit Deckle", Command::Quit, false));
    items
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::settings::Settings;
    use std::time::Duration;

    fn now() -> SystemTime {
        SystemTime::UNIX_EPOCH + Duration::from_secs(1_700_000_000)
    }

    fn actions(items: &[Item]) -> Vec<(String, Command, bool)> {
        let mut found = Vec::new();
        for item in items {
            match item {
                Item::Action { label, command, checked, .. } => found.push((label.clone(), *command, *checked)),
                Item::Submenu { items, .. } => found.extend(actions(items)),
                _ => {}
            }
        }
        found
    }

    #[test]
    fn every_command_id_round_trips_and_is_unique() {
        let mut commands = vec![Command::Toggle, Command::Resume, Command::Quit];
        commands.extend(SNOOZE_MINUTES.map(Command::Snooze));
        commands.extend(INTENSITY_STEPS.map(Command::Intensity));
        commands.extend(PAPERS.iter().map(|paper| Command::Paper(paper.id)));
        let mut ids: Vec<u32> = commands.iter().map(|command| command.id()).collect();
        for command in &commands {
            assert_ne!(command.id(), 0);
            assert_eq!(Command::from_id(command.id()), Some(*command));
        }
        ids.sort_unstable();
        ids.dedup();
        assert_eq!(ids.len(), commands.len());
        assert_eq!(Command::from_id(0), None);
        assert_eq!(Command::from_id(PAPER_BASE + PAPERS.len() as u32), None);
        assert_eq!(Command::from_id(SNOOZE_BASE + SNOOZE_MINUTES.len() as u32), None);
    }

    #[test]
    fn menu_checks_the_current_paper_and_intensity() {
        let mut state = State::new(Settings::default());
        state.select_paper("espresso");
        state.set_intensity(0.31);
        let checked: Vec<Command> = actions(&tray_menu(&state, now(), true))
            .into_iter()
            .filter(|(_, _, checked)| *checked)
            .map(|(_, command, _)| command)
            .collect();
        assert_eq!(checked, [Command::Toggle, Command::Paper("espresso"), Command::Intensity(0.30)]);
    }

    #[test]
    fn menu_lists_every_paper_once() {
        let state = State::new(Settings::default());
        let mut listed: Vec<&str> = actions(&tray_menu(&state, now(), true))
            .into_iter()
            .filter_map(|(_, command, _)| match command {
                Command::Paper(id) => Some(id),
                _ => None,
            })
            .collect();
        let mut expected: Vec<&str> = PAPERS.iter().map(|paper| paper.id).collect();
        listed.sort_unstable();
        expected.sort_unstable();
        assert_eq!(listed, expected);
    }

    #[test]
    fn snoozed_menu_offers_resume_and_counts_down() {
        let mut state = State::new(Settings::default());
        state.snooze(30, now());
        let menu = tray_menu(&state, now() + Duration::from_secs(90), true);
        assert!(menu.contains(&Item::Note("Snoozed, 29 minutes left".to_string())));
        assert!(actions(&menu).iter().any(|(_, command, _)| *command == Command::Resume));
        assert!(actions(&menu).contains(&("Show paper\tCtrl+Alt+P".to_string(), Command::Toggle, false)));
    }

    #[test]
    fn missing_hotkey_is_reported_instead_of_advertised() {
        let state = State::new(Settings::default());
        let menu = tray_menu(&state, now(), false);
        assert!(menu.contains(&Item::Note("Ctrl+Alt+P is unavailable".to_string())));
        assert!(actions(&menu).iter().all(|(label, _, _)| !label.contains('\t')));
    }

    #[test]
    fn labels_read_naturally() {
        assert_eq!(SNOOZE_MINUTES.map(snooze_label), ["15 minutes", "30 minutes", "1 hour", "2 hours"]);
        assert_eq!(percent_label(0.22), "22%");
        assert_eq!(nearest_intensity_step(0.19), 0.18);
        let mut state = State::new(Settings::default());
        assert_eq!(tooltip(&state, now()), "Deckle: Clear Veil at 22%");
        state.toggle(now());
        assert_eq!(tooltip(&state, now()), "Deckle: off (Clear Veil)");
    }
}
