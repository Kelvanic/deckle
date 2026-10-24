//! The notification-area icon and its menu.

use super::app::WM_APP_TRAY;
use crate::glyph;
use crate::menu::Item;
use std::ptr::{null, null_mut};
use windows_sys::Win32::Foundation::{HWND, TRUE};
use windows_sys::Win32::Graphics::Gdi::{
    CreateBitmap, CreateDIBSection, DeleteObject, BITMAPINFO, BITMAPINFOHEADER, BI_RGB, DIB_RGB_COLORS,
};
use windows_sys::Win32::UI::HiDpi::{GetDpiForSystem, GetSystemMetricsForDpi};
use windows_sys::Win32::UI::Shell::{
    Shell_NotifyIconW, NIF_ICON, NIF_MESSAGE, NIF_SHOWTIP, NIF_TIP, NIM_ADD, NIM_DELETE, NIM_MODIFY, NIM_SETVERSION,
    NOTIFYICONDATAW, NOTIFYICON_VERSION_4,
};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    AppendMenuW, CreateIconIndirect, CreatePopupMenu, DestroyIcon, HICON, HMENU, ICONINFO, MF_CHECKED, MF_GRAYED,
    MF_POPUP, MF_SEPARATOR, MF_STRING, SM_CXSMICON,
};

const ICON_ID: u32 = 1;

pub(super) struct Tray {
    hwnd: HWND,
    on_icon: HICON,
    off_icon: HICON,
    added: bool,
    on: bool,
    tooltip: String,
}

impl Tray {
    pub(super) fn new(hwnd: HWND) -> Self {
        let size = unsafe { GetSystemMetricsForDpi(SM_CXSMICON, GetDpiForSystem()) }.max(16) as usize;
        Self {
            hwnd,
            on_icon: create_icon(size, true),
            off_icon: create_icon(size, false),
            added: false,
            on: true,
            tooltip: String::new(),
        }
    }

    /// Shows the current state, adding the icon if the shell doesn't have it.
    pub(super) fn update(&mut self, on: bool, tooltip: &str) {
        if self.added && self.on == on && self.tooltip == tooltip {
            return;
        }
        self.on = on;
        self.tooltip = tooltip.to_string();
        let mut data = self.data();
        unsafe {
            if self.added {
                Shell_NotifyIconW(NIM_MODIFY, &data);
            } else if Shell_NotifyIconW(NIM_ADD, &data) != 0 {
                self.added = true;
                data.Anonymous.uVersion = NOTIFYICON_VERSION_4;
                Shell_NotifyIconW(NIM_SETVERSION, &data);
            }
        }
    }

    /// Explorer restarted and forgot every icon.
    pub(super) fn add_again(&mut self) {
        self.added = false;
        let (on, tooltip) = (self.on, self.tooltip.clone());
        self.tooltip.clear();
        self.update(on, &tooltip);
    }

    pub(super) fn remove(&mut self) {
        unsafe {
            if self.added {
                Shell_NotifyIconW(NIM_DELETE, &self.data());
                self.added = false;
            }
            for icon in [self.on_icon, self.off_icon] {
                if !icon.is_null() {
                    DestroyIcon(icon);
                }
            }
        }
        self.on_icon = null_mut();
        self.off_icon = null_mut();
    }

    fn data(&self) -> NOTIFYICONDATAW {
        // SAFETY: NOTIFYICONDATAW is plain data; zero is valid for every field.
        let mut data: NOTIFYICONDATAW = unsafe { std::mem::zeroed() };
        data.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
        data.hWnd = self.hwnd;
        data.uID = ICON_ID;
        data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
        data.uCallbackMessage = WM_APP_TRAY;
        data.hIcon = if self.on { self.on_icon } else { self.off_icon };
        let tip: Vec<u16> = self.tooltip.encode_utf16().take(data.szTip.len() - 1).collect();
        data.szTip[..tip.len()].copy_from_slice(&tip);
        data
    }
}

fn create_icon(size: usize, on: bool) -> HICON {
    let pixels = glyph::tray_glyph(size, on);
    unsafe {
        let mut info: BITMAPINFO = std::mem::zeroed();
        info.bmiHeader = BITMAPINFOHEADER {
            biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
            biWidth: size as i32,
            biHeight: -(size as i32),
            biPlanes: 1,
            biBitCount: 32,
            biCompression: BI_RGB,
            ..std::mem::zeroed()
        };
        let mut bits = null_mut();
        let color = CreateDIBSection(null_mut(), &info, DIB_RGB_COLORS, &mut bits, null_mut(), 0);
        if color.is_null() || bits.is_null() {
            return null_mut();
        }
        let target = std::slice::from_raw_parts_mut(bits as *mut u8, size * size * 4);
        for (to, from) in target.chunks_exact_mut(4).zip(pixels.chunks_exact(4)) {
            to.copy_from_slice(&[from[2], from[1], from[0], from[3]]);
        }
        // The alpha channel defines the shape; the mask only has to exist.
        let mask_row = size.div_ceil(16) * 2;
        let mask_bits = vec![0u8; mask_row * size];
        let mask = CreateBitmap(size as i32, size as i32, 1, 1, mask_bits.as_ptr().cast());
        let icon_info = ICONINFO { fIcon: TRUE, xHotspot: 0, yHotspot: 0, hbmMask: mask, hbmColor: color };
        let icon = CreateIconIndirect(&icon_info);
        DeleteObject(color);
        DeleteObject(mask);
        icon
    }
}

/// Builds a popup menu from the model. The caller destroys it, which also
/// destroys its submenus.
pub(super) fn build_menu(items: &[Item]) -> HMENU {
    unsafe {
        let menu = CreatePopupMenu();
        if menu.is_null() {
            return menu;
        }
        for item in items {
            match item {
                Item::Action { label, command, checked, enabled } => {
                    let mut flags = MF_STRING;
                    if *checked {
                        flags |= MF_CHECKED;
                    }
                    if !*enabled {
                        flags |= MF_GRAYED;
                    }
                    AppendMenuW(menu, flags, command.id() as usize, wide(label).as_ptr());
                }
                Item::Note(label) => {
                    AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, wide(label).as_ptr());
                }
                Item::Separator => {
                    AppendMenuW(menu, MF_SEPARATOR, 0, null());
                }
                Item::Submenu { label, items, enabled } => {
                    let submenu = build_menu(items);
                    let flags = if *enabled { MF_POPUP } else { MF_POPUP | MF_GRAYED };
                    AppendMenuW(menu, flags, submenu as usize, wide(label).as_ptr());
                }
            }
        }
        menu
    }
}

/// NUL-terminated UTF-16, with `&` doubled so it is not read as a mnemonic.
fn wide(text: &str) -> Vec<u16> {
    text.replace('&', "&&").encode_utf16().chain(std::iter::once(0)).collect()
}
