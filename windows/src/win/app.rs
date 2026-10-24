//! The hidden message window that owns the tray icon, hotkey, and snooze
//! timer, and the app state behind it.
//!
//! State lives in a thread-local `RefCell`. Win32 can re-enter the window
//! procedure while a handler runs (the tray menu runs a modal loop), so the
//! state is only ever borrowed briefly, and never across `TrackPopupMenuEx`.

use super::overlay::{self, Overlays};
use super::tray::{self, Tray};
use crate::menu::{self, Command};
use crate::settings::{self, Settings};
use crate::state::State;
use std::cell::RefCell;
use std::ffi::c_void;
use std::path::PathBuf;
use std::ptr::{null, null_mut};
use std::sync::atomic::{AtomicPtr, AtomicU32, Ordering};
use std::time::SystemTime;
use windows_sys::core::{w, PCWSTR};
use windows_sys::Win32::Foundation::{HINSTANCE, HWND, LPARAM, LRESULT, WPARAM};
use windows_sys::Win32::UI::Accessibility::{SetWinEventHook, UnhookWinEvent, HWINEVENTHOOK};
use windows_sys::Win32::UI::Input::KeyboardAndMouse::{
    RegisterHotKey, UnregisterHotKey, MOD_ALT, MOD_CONTROL, MOD_NOREPEAT,
};
use windows_sys::Win32::UI::Shell::{NINF_KEY, NIN_SELECT};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DestroyMenu, DestroyWindow, GetSystemMetrics, KillTimer, PostMessageW,
    PostQuitMessage, RegisterClassW, RegisterWindowMessageW, SetForegroundWindow, SetTimer, TrackPopupMenuEx,
    EVENT_SYSTEM_FOREGROUND, PBT_APMRESUMEAUTOMATIC, SM_MENUDROPALIGNMENT, TPM_BOTTOMALIGN, TPM_LEFTALIGN,
    TPM_NONOTIFY, TPM_RETURNCMD, TPM_RIGHTALIGN, TPM_RIGHTBUTTON, WINEVENT_OUTOFCONTEXT, WINEVENT_SKIPOWNPROCESS,
    WM_APP, WM_CONTEXTMENU, WM_DESTROY, WM_DISPLAYCHANGE, WM_HOTKEY, WM_NULL, WM_POWERBROADCAST, WM_TIMER, WNDCLASSW,
    WS_EX_TOOLWINDOW, WS_POPUP,
};

const CLASS: PCWSTR = w!("DeckleTray");

pub(super) const WM_APP_TRAY: u32 = WM_APP + 1;
const WM_APP_REFRESH: u32 = WM_APP + 2;
const WM_APP_RAISE: u32 = WM_APP + 3;

const HOTKEY_ID: i32 = 1;
const SNOOZE_TIMER: usize = 1;

struct App {
    hwnd: HWND,
    state: State,
    settings_path: Option<PathBuf>,
    overlays: Overlays,
    tray: Tray,
    hotkey_registered: bool,
    foreground_hook: HWINEVENTHOOK,
}

thread_local! {
    static APP: RefCell<Option<App>> = const { RefCell::new(None) };
}

/// The message window, for callers without access to the app state.
static MAIN_WINDOW: AtomicPtr<c_void> = AtomicPtr::new(null_mut());
/// Broadcast when Explorer restarts and every tray icon must be re-added.
static TASKBAR_CREATED: AtomicU32 = AtomicU32::new(0);

/// Runs `action` on the app state unless it is already borrowed further up
/// the stack.
fn with_app<R>(action: impl FnOnce(&mut App) -> R) -> Option<R> {
    APP.with(|cell| cell.try_borrow_mut().ok().and_then(|mut app| app.as_mut().map(action)))
}

/// Asks for a refresh from code that may run inside another handler.
pub(super) fn request_refresh() {
    let hwnd = MAIN_WINDOW.load(Ordering::Relaxed);
    if !hwnd.is_null() {
        unsafe { PostMessageW(hwnd, WM_APP_REFRESH, 0, 0) };
    }
}

pub(super) fn start(instance: HINSTANCE) -> Option<()> {
    let class = WNDCLASSW {
        lpfnWndProc: Some(window_proc),
        hInstance: instance,
        lpszClassName: CLASS,
        // SAFETY: WNDCLASSW is plain data; zero is valid for every other field.
        ..unsafe { std::mem::zeroed() }
    };
    if unsafe { RegisterClassW(&class) } == 0 || !overlay::register_class(instance) {
        return None;
    }

    // A hidden top-level window rather than a message-only one: only
    // top-level windows hear the TaskbarCreated broadcast and display changes.
    let hwnd = unsafe {
        CreateWindowExW(
            WS_EX_TOOLWINDOW,
            CLASS,
            w!("Deckle"),
            WS_POPUP,
            0,
            0,
            0,
            0,
            null_mut(),
            null_mut(),
            instance,
            null(),
        )
    };
    if hwnd.is_null() {
        return None;
    }
    MAIN_WINDOW.store(hwnd, Ordering::Relaxed);
    TASKBAR_CREATED.store(unsafe { RegisterWindowMessageW(w!("TaskbarCreated")) }, Ordering::Relaxed);

    let settings_path = settings::path_in(std::env::var_os("APPDATA").map(PathBuf::from).as_deref());
    let saved = settings_path.as_deref().map(Settings::load).unwrap_or_default();
    let hotkey_registered =
        unsafe { RegisterHotKey(hwnd, HOTKEY_ID, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, u32::from(b'P')) } != 0;
    // Event-driven, not polled: hear about activations so another topmost
    // window can't settle above the paper.
    let foreground_hook = unsafe {
        SetWinEventHook(
            EVENT_SYSTEM_FOREGROUND,
            EVENT_SYSTEM_FOREGROUND,
            null_mut(),
            Some(foreground_changed),
            0,
            0,
            WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS,
        )
    };

    let app = App {
        hwnd,
        state: State::new(saved),
        settings_path,
        overlays: Overlays::new(instance),
        tray: Tray::new(hwnd),
        hotkey_registered,
        foreground_hook,
    };
    APP.with(|cell| *cell.borrow_mut() = Some(app));
    with_app(App::refresh);
    Some(())
}

/// Releases everything after the message loop ends.
pub(super) fn shutdown() {
    if let Some(mut app) = APP.with(|cell| cell.borrow_mut().take()) {
        app.close();
    }
    MAIN_WINDOW.store(null_mut(), Ordering::Relaxed);
}

impl App {
    fn refresh(&mut self) {
        let now = SystemTime::now();
        self.state.expire_snooze(now);
        match self.state.snooze_remaining(now) {
            // One timer for the snooze's end; nothing ticks in between.
            Some(remaining) => unsafe {
                let milliseconds = remaining.as_millis().min(0x7FFF_FFFF) as u32;
                SetTimer(self.hwnd, SNOOZE_TIMER, milliseconds.max(1), None);
            },
            None => unsafe {
                KillTimer(self.hwnd, SNOOZE_TIMER);
            },
        }
        let visible = self.state.should_show_overlay(now);
        self.overlays.sync(visible, self.state.paper(), self.state.intensity());
        self.tray.update(visible, &menu::tooltip(&self.state, now));
    }

    fn run(&mut self, command: Command) {
        let now = SystemTime::now();
        match command {
            Command::Toggle => self.state.toggle(now),
            Command::Resume => self.state.resume(),
            Command::Snooze(minutes) => self.state.snooze(minutes, now),
            Command::Intensity(intensity) => self.state.set_intensity(intensity),
            Command::Paper(id) => {
                self.state.select_paper(id);
            }
            Command::Quit => {
                // WM_DESTROY only posts the quit message; `shutdown` cleans up.
                unsafe { DestroyWindow(self.hwnd) };
                return;
            }
        }
        if let Some(path) = &self.settings_path {
            // A failed save keeps the change for this session; there is no
            // console to report it to.
            let _ = self.state.settings().save(path);
        }
        self.refresh();
    }

    fn close(&mut self) {
        unsafe {
            KillTimer(self.hwnd, SNOOZE_TIMER);
            if self.hotkey_registered {
                UnregisterHotKey(self.hwnd, HOTKEY_ID);
            }
            if !self.foreground_hook.is_null() {
                UnhookWinEvent(self.foreground_hook);
            }
        }
        self.tray.remove();
        self.overlays.destroy();
    }
}

unsafe extern "system" fn window_proc(hwnd: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    let taskbar_created = TASKBAR_CREATED.load(Ordering::Relaxed);
    if taskbar_created != 0 && message == taskbar_created {
        with_app(|app| app.tray.add_again());
        return 0;
    }
    match message {
        WM_APP_TRAY => {
            // NOTIFYICON_VERSION_4: the event is in the low word of lParam
            // and the icon's anchor point, in screen pixels, in wParam.
            let event = (lparam as u32) & 0xFFFF;
            if event == WM_CONTEXTMENU || event == NIN_SELECT || event == (NIN_SELECT | NINF_KEY) {
                let x = (wparam & 0xFFFF) as u16 as i16 as i32;
                let y = ((wparam >> 16) & 0xFFFF) as u16 as i16 as i32;
                show_menu(hwnd, x, y);
            }
            0
        }
        WM_HOTKEY => {
            if wparam == HOTKEY_ID as WPARAM {
                with_app(|app| app.run(Command::Toggle));
            }
            0
        }
        WM_TIMER if wparam == SNOOZE_TIMER => {
            with_app(App::refresh);
            0
        }
        WM_DISPLAYCHANGE | WM_APP_REFRESH => {
            with_app(App::refresh);
            0
        }
        WM_POWERBROADCAST => {
            // A snooze may have ended while the machine slept.
            if wparam == PBT_APMRESUMEAUTOMATIC as WPARAM {
                with_app(App::refresh);
            }
            1
        }
        WM_APP_RAISE => {
            with_app(|app| app.overlays.raise());
            0
        }
        WM_DESTROY => {
            PostQuitMessage(0);
            0
        }
        _ => DefWindowProcW(hwnd, message, wparam, lparam),
    }
}

unsafe fn show_menu(hwnd: HWND, x: i32, y: i32) {
    let Some(menu) =
        with_app(|app| tray::build_menu(&menu::tray_menu(&app.state, SystemTime::now(), app.hotkey_registered)))
    else {
        return;
    };
    if menu.is_null() {
        return;
    }
    // Without these two calls the menu would not close when the user clicks
    // elsewhere.
    SetForegroundWindow(hwnd);
    let horizontal = if GetSystemMetrics(SM_MENUDROPALIGNMENT) != 0 { TPM_RIGHTALIGN } else { TPM_LEFTALIGN };
    let chosen = TrackPopupMenuEx(
        menu,
        TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN | horizontal,
        x,
        y,
        hwnd,
        null(),
    );
    PostMessageW(hwnd, WM_NULL, 0, 0);
    DestroyMenu(menu);

    if let Some(command) = u32::try_from(chosen).ok().and_then(Command::from_id) {
        with_app(|app| app.run(command));
    }
}

unsafe extern "system" fn foreground_changed(
    _hook: HWINEVENTHOOK,
    _event: u32,
    _hwnd: HWND,
    _object: i32,
    _child: i32,
    _thread: u32,
    _time: u32,
) {
    let hwnd = MAIN_WINDOW.load(Ordering::Relaxed);
    if !hwnd.is_null() {
        PostMessageW(hwnd, WM_APP_RAISE, 0, 0);
    }
}
