//! Deckle for Windows.
//!
//! The renderer, paper library, settings, state, tray menu model, and tray
//! glyph are plain Rust and build and test on any platform. The Win32 shell
//! in [`win`] builds only on Windows.

pub mod fft;
pub mod glyph;
pub mod menu;
pub mod papers;
pub mod renderer;
pub mod rng;
pub mod settings;
pub mod state;

#[cfg(windows)]
pub mod win;
