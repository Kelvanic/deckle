import AppKit
import Combine

/// Owns one OverlayWindow per display and keeps them in sync with AppState
/// and with display configuration changes (plug/unplug, resolution change).
@MainActor
final class OverlayController {
    static let shared = OverlayController()

    private var windows: [CGDirectDisplayID: OverlayWindow] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var frontmostBundleID: String?

    private var previewTimer: Timer?
    private var cleanShotPID: pid_t?

    private func trackCleanShot(_ needed: Bool) {
        let pid = needed ? NSRunningApplication.runningApplications(
            withBundleIdentifier: CleanShotPreview.bundleID).first?.processIdentifier : nil
        if cleanShotPID != pid {
            previewTimer?.invalidate()
            previewTimer = nil
            cleanShotPID = pid
            if pid != nil {
                // Pins are nonactivating windows. Focus notifications alone miss
                // moving, closing, or covering one while another app is active.
                let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updatePreviewRegions() }
                }
                timer.tolerance = 0.05
                previewTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            } else {
                for window in windows.values { window.setPreviewRegions([]) }
            }
        }
    }

    private func updatePreviewRegions() {
        guard let owner = cleanShotPID,
              let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0)
                as? [[String: Any]] else { return }
        for (displayID, window) in windows where window.isVisible {
            window.setPreviewRegions(CleanShotPreview.regions(in: rows, below: window.presentedWindowID,
                on: CGDisplayBounds(displayID), owner: owner))
        }
    }

    private init() {}

    private var refreshScheduled = false

    /// Coalesces refresh bursts (e.g. every tick of a slider drag) into at
    /// most ~30 refreshes/second — regenerating the grain tile on every
    /// mouse-move event is the app's only real CPU burst.
    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.033) { [weak self] in
            self?.refreshScheduled = false
            self?.refresh()
        }
    }

    func start() {
        // objectWillChange fires before the mutation lands; the coalescing
        // delay also guarantees we read post-mutation values.
        AppState.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Observer blocks are not actor-isolated; hop explicitly.
            Task { @MainActor [weak self] in self?.refresh() }
        }

        // Event-driven per-app rules: no polling, we only hear about
        // activations. The listener is always on (cheap) so switching the
        // rule mode takes effect without restructuring observers.
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            Task { @MainActor [weak self] in
                self?.frontmostBundleID = bundleID
                self?.refresh()
            }
        }

        for event in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: event, object: nil, queue: .main) { [weak self] note in
                guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                        == CleanShotPreview.bundleID else { return }
                Task { @MainActor in self?.refresh() }
            }
        }
        refresh()
    }

    func refresh() {
        let state = AppState.shared
        var seen: Set<CGDirectDisplayID> = []
        var trackingNeeded = false

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            seen.insert(displayID)

            // A Paper Mill preview overrides both the on/off state and app rules —
            // you have to be able to judge a draft while the overlay is off — but
            // still honours per-display exclusions, so the preview lands exactly
            // where the finished paper would.
            let visible = state.overlayIsVisible(on: String(displayID), frontmost: frontmostBundleID)

            // .none removes the overlay from screenshots/recordings while it
            // stays visible on the physical display. Changing sharingType on
            // an onscreen window doesn't reliably reach the window server, so
            // it is only ever set before a window first orders front — when
            // the setting changes, the window is rebuilt.
            let sharing: NSWindow.SharingType = state.hideFromCapture ? .none : .readOnly
            if let existing = windows[displayID],
               existing.sharingType != sharing || existing.frame != screen.frame
                || existing.renderScale != screen.backingScaleFactor {
                existing.close()
                windows.removeValue(forKey: displayID)
            }

            let window = windows[displayID] ?? {
                let created = OverlayWindow(screen: screen)
                created.sharingType = sharing
                windows[displayID] = created
                return created
            }()

            if visible {
                trackingNeeded = trackingNeeded || !state.hideFromCapture
                // Only visible overlays render: browsing papers or dragging
                // grain controls while paused costs no tile synthesis. The
                // texture is applied before a hidden window is shown.
                window.apply(texture: state.effectiveTexture, adjustments: state.grainAdjustments)
                if window.isVisible {
                    // Already showing (e.g. slider drag): track directly,
                    // animating every tick would lag behind the slider.
                    window.setIntensity(CGFloat(state.intensity))
                } else {
                    window.alphaValue = 0
                    window.orderFrontRegardless()
                    window.fade(to: CGFloat(state.intensity))
                }
            } else if window.isVisible {
                window.fade(to: 0, completion: { [weak window] in
                    // Only detach if nothing re-showed it mid-fade (a re-show
                    // would have restored a non-zero alpha).
                    if let window, window.alphaValue == 0 {
                        window.orderOut(nil)
                    }
                })
            }
        }

        // Drop windows for displays that went away.
        for (displayID, window) in windows where !seen.contains(displayID) {
            window.close()
            windows.removeValue(forKey: displayID)
        }
        trackCleanShot(trackingNeeded)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value
    }
}
