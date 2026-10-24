//! The Win32 shell: one click-through layered overlay window per monitor, a
//! tray icon carrying the menu, and the Ctrl+Alt+P hotkey. Everything runs on
//! the one UI thread; nothing animates or polls, so an idle Deckle costs no
//! CPU.

mod app;
mod overlay;
mod tray;

use std::ptr::{null, null_mut};
use windows_sys::core::w;
use windows_sys::Win32::Foundation::{CloseHandle, GetLastError, ERROR_ALREADY_EXISTS};
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::System::Threading::CreateMutexW;
use windows_sys::Win32::UI::HiDpi::{SetProcessDpiAwarenessContext, DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2};
use windows_sys::Win32::UI::WindowsAndMessaging::{DispatchMessageW, GetMessageW, TranslateMessage, MSG};

/// Runs Deckle until the user quits. Returns the process exit code.
pub fn run() -> i32 {
    unsafe {
        // Physical pixels everywhere, so each overlay covers its monitor
        // exactly and the tile renders at the monitor's own scale.
        SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

        // A second launch would stack a second overlay; let the first win.
        let mutex = CreateMutexW(null(), 1, w!("Local\\Deckle.Windows.SingleInstance"));
        if mutex.is_null() {
            return 1;
        }
        if GetLastError() == ERROR_ALREADY_EXISTS {
            CloseHandle(mutex);
            return 0;
        }

        let instance = GetModuleHandleW(null());
        let code = match app::start(instance) {
            Some(()) => {
                let mut message: MSG = std::mem::zeroed();
                while GetMessageW(&mut message, null_mut(), 0, 0) > 0 {
                    TranslateMessage(&message);
                    DispatchMessageW(&message);
                }
                app::shutdown();
                0
            }
            None => 1,
        };
        CloseHandle(mutex);
        code
    }
}
