//! One borderless, click-through, topmost layered window per monitor.
//!
//! Each window's content is set once per paper, scale, and size with
//! `UpdateLayeredWindow`; intensity changes only touch its constant alpha.
//! The monitor-sized bitmap exists only for the duration of that call: the
//! process keeps just the small tile, and the window manager keeps the pixels.

use super::app;
use crate::papers::Paper;
use crate::renderer::{self, Tile};
use std::ptr::{null, null_mut};
use windows_sys::core::{w, PCWSTR};
use windows_sys::Win32::Foundation::{BOOL, HINSTANCE, HWND, LPARAM, LRESULT, POINT, RECT, SIZE, TRUE, WPARAM};
use windows_sys::Win32::Graphics::Gdi::{
    CreateCompatibleDC, CreateDIBSection, DeleteDC, DeleteObject, EnumDisplayMonitors, GetDC, GetMonitorInfoW,
    ReleaseDC, SelectObject, AC_SRC_ALPHA, AC_SRC_OVER, BITMAPINFO, BITMAPINFOHEADER, BI_RGB, BLENDFUNCTION,
    DIB_RGB_COLORS, HDC, HMONITOR, MONITORINFO, MONITORINFOEXW,
};
use windows_sys::Win32::UI::HiDpi::{GetDpiForMonitor, MDT_EFFECTIVE_DPI};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DestroyWindow, RegisterClassW, SetWindowPos, ShowWindow, UpdateLayeredWindow,
    HTTRANSPARENT, HWND_TOPMOST, MA_NOACTIVATE, SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOOWNERZORDER, SWP_NOSIZE, SW_HIDE,
    SW_SHOWNOACTIVATE, ULW_ALPHA, WM_DISPLAYCHANGE, WM_DPICHANGED, WM_MOUSEACTIVATE, WM_NCHITTEST, WNDCLASSW,
    WS_EX_LAYERED, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW, WS_EX_TOPMOST, WS_EX_TRANSPARENT, WS_POPUP,
};

const CLASS: PCWSTR = w!("DeckleOverlay");

/// Overlay tiles kept rendered: enough for two monitors at different scales.
const TILE_CACHE_CAPACITY: usize = 2;

pub(super) fn register_class(instance: HINSTANCE) -> bool {
    let class = WNDCLASSW {
        lpfnWndProc: Some(overlay_proc),
        hInstance: instance,
        lpszClassName: CLASS,
        // SAFETY: WNDCLASSW is plain data; zero is valid for every other field.
        ..unsafe { std::mem::zeroed() }
    };
    unsafe { RegisterClassW(&class) != 0 }
}

unsafe extern "system" fn overlay_proc(hwnd: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match message {
        // Belt and braces with WS_EX_TRANSPARENT: never take a click or focus.
        WM_NCHITTEST => HTTRANSPARENT as LRESULT,
        WM_MOUSEACTIVATE => MA_NOACTIVATE as LRESULT,
        // Rebuild from the real monitor geometry instead of accepting the
        // suggested rectangle.
        WM_DPICHANGED | WM_DISPLAYCHANGE => {
            app::request_refresh();
            0
        }
        _ => DefWindowProcW(hwnd, message, wparam, lparam),
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
struct Bounds {
    left: i32,
    top: i32,
    width: i32,
    height: i32,
}

impl From<RECT> for Bounds {
    fn from(rect: RECT) -> Self {
        Bounds { left: rect.left, top: rect.top, width: rect.right - rect.left, height: rect.bottom - rect.top }
    }
}

struct Monitor {
    device: Vec<u16>,
    bounds: Bounds,
    scale: usize,
}

/// What a window currently shows; repainting is skipped while it matches.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
struct Content {
    paper: &'static str,
    scale: usize,
    bounds: Bounds,
}

struct Overlay {
    hwnd: HWND,
    device: Vec<u16>,
    content: Option<Content>,
    alpha: u8,
    shown: bool,
}

pub(super) struct Overlays {
    instance: HINSTANCE,
    windows: Vec<Overlay>,
    /// BGRA tiles keyed by paper id and scale, least recently used first.
    tiles: Vec<(&'static str, usize, Tile)>,
}

impl Overlays {
    pub(super) fn new(instance: HINSTANCE) -> Self {
        Self { instance, windows: Vec::new(), tiles: Vec::new() }
    }

    /// Matches the windows to the connected monitors and shows or hides them.
    /// Hidden windows keep their last content, and nothing renders for them.
    pub(super) fn sync(&mut self, visible: bool, paper: &'static Paper, intensity: f64) {
        let monitors = monitors();
        self.windows.retain(|overlay| {
            let connected = monitors.iter().any(|monitor| monitor.device == overlay.device);
            if !connected {
                unsafe { DestroyWindow(overlay.hwnd) };
            }
            connected
        });

        let alpha = (intensity.clamp(0.0, 1.0) * 255.0).round() as u8;
        for monitor in &monitors {
            let index = match self.windows.iter().position(|overlay| overlay.device == monitor.device) {
                Some(index) => index,
                None => match create_window(self.instance, monitor.bounds) {
                    Some(hwnd) => {
                        self.windows.push(Overlay {
                            hwnd,
                            device: monitor.device.clone(),
                            content: None,
                            alpha: 0,
                            shown: false,
                        });
                        self.windows.len() - 1
                    }
                    None => continue,
                },
            };
            let overlay = &mut self.windows[index];

            if !visible {
                if overlay.shown {
                    unsafe { ShowWindow(overlay.hwnd, SW_HIDE) };
                    overlay.shown = false;
                }
                continue;
            }

            let content = Content { paper: paper.id, scale: monitor.scale, bounds: monitor.bounds };
            if overlay.content != Some(content) {
                let tile = cached_tile(&mut self.tiles, paper, monitor.scale);
                if !paint(overlay.hwnd, monitor.bounds, tile, alpha) {
                    continue;
                }
                overlay.content = Some(content);
                overlay.alpha = alpha;
            } else if overlay.alpha != alpha {
                set_alpha(overlay.hwnd, alpha);
                overlay.alpha = alpha;
            }

            if !overlay.shown {
                unsafe { ShowWindow(overlay.hwnd, SW_SHOWNOACTIVATE) };
                overlay.shown = true;
            }
            raise(overlay.hwnd);
        }
    }

    /// Puts visible overlays back on top after another topmost window
    /// activates.
    pub(super) fn raise(&self) {
        for overlay in self.windows.iter().filter(|overlay| overlay.shown) {
            raise(overlay.hwnd);
        }
    }

    pub(super) fn destroy(&mut self) {
        for overlay in self.windows.drain(..) {
            unsafe { DestroyWindow(overlay.hwnd) };
        }
        self.tiles.clear();
    }
}

fn cached_tile<'a>(tiles: &'a mut Vec<(&'static str, usize, Tile)>, paper: &'static Paper, scale: usize) -> &'a Tile {
    if let Some(index) = tiles.iter().position(|(id, s, _)| *id == paper.id && *s == scale) {
        let entry = tiles.remove(index);
        tiles.push(entry);
    } else {
        tiles.push((paper.id, scale, renderer::composite_tile(paper, scale).to_bgra()));
        if tiles.len() > TILE_CACHE_CAPACITY {
            tiles.remove(0);
        }
    }
    &tiles[tiles.len() - 1].2
}

fn monitors() -> Vec<Monitor> {
    unsafe extern "system" fn collect(monitor: HMONITOR, _: HDC, _: *mut RECT, data: LPARAM) -> BOOL {
        let list = &mut *(data as *mut Vec<Monitor>);
        let mut info: MONITORINFOEXW = std::mem::zeroed();
        info.monitorInfo.cbSize = std::mem::size_of::<MONITORINFOEXW>() as u32;
        if GetMonitorInfoW(monitor, &mut info as *mut MONITORINFOEXW as *mut MONITORINFO) != 0 {
            let (mut dpi_x, mut dpi_y) = (96u32, 96u32);
            if GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &mut dpi_x, &mut dpi_y) != 0 {
                dpi_x = 96;
            }
            let length = info.szDevice.iter().position(|&c| c == 0).unwrap_or(info.szDevice.len());
            list.push(Monitor {
                device: info.szDevice[..length].to_vec(),
                bounds: info.monitorInfo.rcMonitor.into(),
                scale: renderer::normalized_scale(dpi_x as f64 / 96.0),
            });
        }
        TRUE
    }

    let mut list: Vec<Monitor> = Vec::new();
    unsafe {
        EnumDisplayMonitors(null_mut(), null(), Some(collect), &mut list as *mut Vec<Monitor> as LPARAM);
    }
    list
}

fn create_window(instance: HINSTANCE, bounds: Bounds) -> Option<HWND> {
    let hwnd = unsafe {
        CreateWindowExW(
            WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
            CLASS,
            w!("Deckle paper"),
            WS_POPUP,
            bounds.left,
            bounds.top,
            bounds.width,
            bounds.height,
            null_mut(),
            null_mut(),
            instance,
            null(),
        )
    };
    (!hwnd.is_null()).then_some(hwnd)
}

fn blend(alpha: u8) -> BLENDFUNCTION {
    BLENDFUNCTION {
        BlendOp: AC_SRC_OVER as u8,
        BlendFlags: 0,
        SourceConstantAlpha: alpha,
        AlphaFormat: AC_SRC_ALPHA as u8,
    }
}

/// Fills a monitor-sized premultiplied BGRA bitmap with the tile and hands it
/// to the window manager, at `alpha` overall.
fn paint(hwnd: HWND, bounds: Bounds, tile: &Tile, alpha: u8) -> bool {
    if bounds.width <= 0 || bounds.height <= 0 {
        return false;
    }
    let (width, height) = (bounds.width as usize, bounds.height as usize);
    unsafe {
        let mut info: BITMAPINFO = std::mem::zeroed();
        info.bmiHeader = BITMAPINFOHEADER {
            biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
            biWidth: bounds.width,
            // Negative height: top-down rows, matching the tile.
            biHeight: -bounds.height,
            biPlanes: 1,
            biBitCount: 32,
            biCompression: BI_RGB,
            ..std::mem::zeroed()
        };
        let screen = GetDC(null_mut());
        let mut bits = null_mut();
        let bitmap = CreateDIBSection(screen, &info, DIB_RGB_COLORS, &mut bits, null_mut(), 0);
        if bitmap.is_null() || bits.is_null() {
            ReleaseDC(null_mut(), screen);
            return false;
        }
        let pixels = std::slice::from_raw_parts_mut(bits as *mut u8, width * height * 4);
        renderer::fill_tiled(pixels, width, height, tile);

        let memory = CreateCompatibleDC(screen);
        let previous = SelectObject(memory, bitmap);
        let position = POINT { x: bounds.left, y: bounds.top };
        let size = SIZE { cx: bounds.width, cy: bounds.height };
        let origin = POINT { x: 0, y: 0 };
        let blend = blend(alpha);
        let painted = UpdateLayeredWindow(hwnd, screen, &position, &size, memory, &origin, 0, &blend, ULW_ALPHA) != 0;

        SelectObject(memory, previous);
        DeleteDC(memory);
        DeleteObject(bitmap);
        ReleaseDC(null_mut(), screen);
        painted
    }
}

/// Changes only the window's overall opacity; its pixels stay as painted.
fn set_alpha(hwnd: HWND, alpha: u8) {
    let blend = blend(alpha);
    unsafe {
        UpdateLayeredWindow(hwnd, null_mut(), null(), null(), null_mut(), null(), 0, &blend, ULW_ALPHA);
    }
}

fn raise(hwnd: HWND) {
    unsafe {
        SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
    }
}
