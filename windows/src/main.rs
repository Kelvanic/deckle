// No console window for the tray app.
#![cfg_attr(windows, windows_subsystem = "windows")]

#[cfg(windows)]
fn main() {
    std::process::exit(deckle::win::run());
}

#[cfg(not(windows))]
fn main() {
    eprintln!("Deckle for Windows runs only on Windows. On macOS, build the Swift app from the repository root.");
    std::process::exit(1);
}
