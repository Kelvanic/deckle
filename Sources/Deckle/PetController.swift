import AppKit
import Combine
import QuartzCore

/// A small borderless, transparent, click-through window that holds one pet.
/// Same space/level contract as the paper overlay, but tiny — the artwork is
/// a retained layer tree, never a screen-sized bitmap.
final class PetWindow: NSWindow {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosts a PetRig inside a window and applies sampled poses. All animation is
/// layer transforms driven by the controller's single timer; the view itself
/// draws nothing. Also used for the still portraits on the companion cards.
@MainActor
final class PetRigView: NSView {
    private(set) var rig: PetRig
    private var lastFrame: PetMotionFrame?
    /// Portraits frame the drawn pose instead of the whole travel canvas.
    var fitsArtwork = false { didSet { needsLayout = true } }
    /// Breathing room around a portrait, in canvas points.
    static let portraitMargin: CGFloat = 7

    init(kind: PetKind) {
        rig = PetRig(kind: kind)
        super.init(frame: CGRect(origin: .zero, size: PetArtwork.canvas))
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.addSublayer(rig.root)
    }

    required init?(coder: NSCoder) { nil }

    /// Artwork is authored on a fixed canvas and uniformly scaled to whatever
    /// window size the current PetSize asks for. Poses never touch this scale.
    override func layout() {
        super.layout()
        fit()
    }

    private func fit() {
        guard fitsArtwork else {
            rig.place(in: bounds)
            return
        }
        let margin = Self.portraitMargin
        rig.place(in: bounds, showing: rig.artworkBounds().insetBy(dx: -margin, dy: -margin))
    }

    /// Swap species by rebuilding the layer tree once.
    func setKind(_ kind: PetKind) {
        guard kind != rig.kind else { return }
        rig.root.removeFromSuperlayer()
        rig = PetRig(kind: kind)
        layer?.addSublayer(rig.root)
        lastFrame = nil
        fit()
    }

    /// Callers pass an already-settled frame when motion is paused.
    func pose(_ frame: PetMotionFrame) {
        guard frame != lastFrame else { return }
        lastFrame = frame
        rig.apply(frame)
        if fitsArtwork { fit() }
    }
}

/// Runtime gates that decide whether a pet may appear or animate. Injected in
/// tests so power/session/motion states are exercised without touching global
/// machine preferences.
struct PetEnvironment {
    var reduceMotion: Bool
    var lowPowerMode: Bool
    var sessionActive: Bool
    var screenAsleep: Bool

    @MainActor
    static var live: PetEnvironment {
        PetEnvironment(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            sessionActive: true,
            screenAsleep: false
        )
    }

    var motionAllowed: Bool { !reduceMotion && !lowPowerMode && sessionActive && !screenAsleep }
    var presenceAllowed: Bool { sessionActive && !screenAsleep }
}

/// Owns the single desktop pet window and its animation timer. Mirrors
/// OverlayController's lifecycle patterns: observe AppState, screen changes,
/// and workspace events; coalesce; keep everything on the main actor.
@MainActor
final class PetController {
    static let shared = PetController()

    private let state: AppState
    private var baseEnvironment: @MainActor () -> PetEnvironment
    private var window: PetWindow?
    private var rigView: PetRigView?
    private var displayID: CGDirectDisplayID?
    private var cancellables: Set<AnyCancellable> = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?
    private(set) var isAnimating = false
    private var started = false
    /// Accumulated animation time — preserved across pauses, reset on resume
    /// only by continuing from where it stopped (no time jumps after sleep).
    private var elapsed: TimeInterval = 0
    private var lastTick: TimeInterval = 0
    private var sessionActive = true
    private var screenAsleep = false
    private var frontmostBundleID: String?
    private var refreshScheduled = false

    init(state: AppState? = nil, environment: (@MainActor () -> PetEnvironment)? = nil) {
        self.state = state ?? .shared
        self.baseEnvironment = environment ?? { PetEnvironment.live }
    }

    /// Injected environment merged with the session/display sleep flags this
    /// controller tracks from workspace notifications — either source can
    /// suspend presence.
    private func environment() -> PetEnvironment {
        var env = baseEnvironment()
        env.sessionActive = sessionActive && env.sessionActive
        env.screenAsleep = screenAsleep || env.screenAsleep
        return env
    }

    func start() {
        guard !started else { return }
        started = true

        state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        let app = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observe(app, NSApplication.didChangeScreenParametersNotification) { $0.refresh() }
        observe(app, .NSProcessInfoPowerStateDidChange) { $0.refresh() }
        // Reduce Motion can change while pets are out; re-gate the timer.
        observe(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { $0.refresh() }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { controller, note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            controller.frontmostBundleID = app?.bundleIdentifier
            controller.refresh()
        }
        // Session and display sleep gates — presence stops entirely.
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionActive = false; $0.refresh() }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionActive = true; $0.refresh() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.screenAsleep = true; $0.refresh() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.screenAsleep = false; $0.refresh() }
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        refresh()
    }

    /// Stored observer blocks are not actor-isolated under the release
    /// compiler, so each one hops to the main actor explicitly.
    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping @MainActor (PetController, Notification) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self, self.started else { return }
                handler(self, note)
            }
        }
        observers.append((center, token))
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping @MainActor (PetController) -> Void) {
        observe(center, name) { controller, _ in handler(controller) }
    }

    /// Test seam — rebuild everything as if preferences just changed.
    func updateEnvironment() { refresh() }

    /// Test seams for lifecycle assertions.
    var windowForTesting: NSWindow? { window }

    func stop() {
        started = false
        cancellables.removeAll()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        hide()
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.033) { [weak self] in
            self?.refreshScheduled = false
            self?.refresh()
        }
    }

    /// Sprite size for the current setting, shrunk to fit a small display.
    private func spriteSize(for display: PetDisplay) -> CGSize {
        let canvas = PetArtwork.canvas
        let scale = state.petSize.scale
        var size = CGSize(width: canvas.width * scale, height: canvas.height * scale)
        let maxW = display.visibleFrame.width * 0.4
        let maxH = display.visibleFrame.height * 0.4
        if size.width > maxW || size.height > maxH {
            let fit = min(maxW / max(1, size.width), maxH / max(1, size.height))
            if fit.isFinite, fit > 0 { size = CGSize(width: size.width * fit, height: size.height * fit) }
        }
        return size
    }

    func refresh() {
        guard started else { return }
        let displays: [PetDisplay] = NSScreen.screens.compactMap { screen in
            guard let id = screen.displayID else { return nil }
            return PetDisplay(id: String(id), visibleFrame: screen.visibleFrame)
        }
        let env = environment()

        guard env.presenceAllowed,
              let destination = PetPlacement.destination(
                  preferredID: state.petDisplayID, displays: displays,
                  excluded: state.excludedDisplays),
              state.petsAreVisible(on: destination.id, frontmost: frontmostBundleID),
              let newID = UInt32(destination.id) else {
            hide()
            return
        }

        // sharingType must be fixed before a window first orders front —
        // like the texture overlay, a changed setting rebuilds the window.
        let sharing: NSWindow.SharingType = state.hideFromCapture ? .none : .readOnly
        if let existing = window,
           existing.sharingType != sharing || displayID != newID {
            existing.orderOut(nil)
            window = nil
            rigView = nil
        }
        if window == nil {
            let created = PetWindow(frame: .zero)
            created.sharingType = sharing
            let view = PetRigView(kind: state.petKind)
            created.contentView = view
            rigView = view
            window = created
        }
        rigView?.setKind(state.petKind)
        displayID = newID
        syncTimer(env: env)
    }

    private func syncTimer(env: PetEnvironment) {
        let shouldRun = env.motionAllowed
        if shouldRun && timer == nil {
            lastTick = ProcessInfo.processInfo.systemUptime
            let tick = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.advanceFrame() }
            }
            tick.tolerance = 1 / 120
            timer = tick
            RunLoop.main.add(tick, forMode: .common)
            isAnimating = true
            // Show the current pose now rather than one tick later.
            applyFrame(frozen: false)
        } else if !shouldRun {
            stopTimer()
            // Leave a calm still frame on screen.
            applyFrame(frozen: true)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        isAnimating = false
    }

    private func hide() {
        stopTimer()
        window?.orderOut(nil)
    }

    private func advanceFrame() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.1, max(0, now - lastTick))
        lastTick = now
        elapsed += dt
        applyFrame(frozen: false)
    }

    private func applyFrame(frozen: Bool) {
        // A tick queued before a hide must not resurrect the window.
        let env = environment()
        guard started, env.presenceAllowed, let displayID,
              state.petsAreVisible(on: String(displayID), frontmost: frontmostBundleID) else {
            hide()
            return
        }
        guard let window, let rigView,
              let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
            stopTimer()
            return
        }
        let visibleFrame = screen.visibleFrame
        let size = spriteSize(for: PetDisplay(id: String(displayID), visibleFrame: visibleFrame))
        let frame = frozen
            ? PetMotion.settledFrame(kind: state.petKind, mood: state.petMood, time: elapsed,
                                     in: visibleFrame, spriteSize: size)
            : PetMotion.frame(kind: state.petKind, mood: state.petMood, time: elapsed,
                              in: visibleFrame, spriteSize: size, cursor: NSEvent.mouseLocation)
        let rect = PetMotion.windowRect(center: frame.center, spriteSize: size,
                                        bounds: PetMotion.safeBounds(visibleFrame, spriteSize: size))
        // A resting pet keeps its window still; skip redundant window-server moves.
        if window.frame != rect {
            window.setFrame(rect, display: false)
        }
        rigView.pose(frame)
        if !window.isVisible {
            window.alphaValue = 1
            window.orderFrontRegardless()
        }
    }
}
