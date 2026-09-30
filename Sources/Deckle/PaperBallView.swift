import AppKit
import SwiftUI

/// Native rendering of the Echo reference: six counter-rotating dot rings,
/// breathing, a pulsing core, and pointer-directed eyes. `EchoGeometry` keeps
/// the reference's parameters and its 60 Hz phase-step convention.
struct PaperBallView: NSViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> EchoBallView { EchoBallView() }

    func updateNSView(_ view: EchoBallView, context: Context) {
        view.reducedMotion = reduceMotion
        view.lightInk = colorScheme == .dark
    }

    static func dismantleNSView(_ view: EchoBallView, coordinator: ()) {
        view.stop()
    }
}

struct EchoDot {
    let center: CGPoint
    let radius: CGFloat
    let opacity: CGFloat
}

/// Pure geometry makes the motion reproducible without a running window.
enum EchoGeometry {
    static func dots(radius: CGFloat, phase: Double) -> [EchoDot] {
        var result: [EchoDot] = []
        result.reserveCapacity(183)
        var index: UInt32 = 0
        for ring in 1...6 {
            let count = 6 + ring * 7
            let direction = ring.isMultiple(of: 2) ? -1.0 : 1.0
            let breathing = 1 + sin(phase * 1.6 + Double(ring)) * 0.035
            let distance = CGFloat(ring) / 6 * radius * 1.06 * breathing
            for dot in 0..<count {
                defer { index += 1 }
                let keep = radius < 45 ? max(0.3, radius / 45) : 1
                var hash = (index ^ (index >> 16)) &* 0x45d9f3b
                hash = (hash >> 16) ^ hash
                guard Double(hash) / 4_294_967_296 < Double(keep) else { continue }
                let angle = Double(dot) / Double(count) * 2 * .pi + phase * 0.3 * direction
                let inkScale = radius < 85 ? 0.45 + 0.55 * radius / 85 : 1
                result.append(EchoDot(
                    center: CGPoint(x: cos(angle) * distance, y: sin(angle) * distance),
                    radius: max(0.6, (2.3 - CGFloat(ring) * 0.16) * inkScale),
                    opacity: max(keep < 1 ? 0.55 : 0, 0.9 - CGFloat(ring) * 0.09)))
            }
        }
        return result
    }

    static func gaze(pointer: CGPoint, center: CGPoint, radius: CGFloat) -> CGPoint {
        let dx = pointer.x - center.x
        let dy = pointer.y - center.y
        let distance = max(1, hypot(dx, dy))
        let reach = min(1, distance / 240) * radius * 0.16
        return CGPoint(x: dx / distance * reach, y: dy / distance * reach)
    }

    static func openness(timeUntilBlink: Double) -> CGFloat {
        abs(timeUntilBlink) < 0.13 ? abs(timeUntilBlink) / 0.13 : 1
    }
}

struct EchoMotion {
    var phase: Double = 0
    var offset = CGPoint.zero
    var velocity = CGPoint.zero
    var squash: Double = 0
    var squashVelocity: Double = 0

    mutating func advance(seconds: Double, target: CGPoint) {
        let dt = min(0.05, max(0.001, seconds))
        // The site advances phase by .018 on each 60 Hz animation frame.
        phase += dt * 1.08
        velocity.x += (52 * (target.x - offset.x) - 12.6 * velocity.x) * dt
        velocity.y += (52 * (target.y - offset.y) - 12.6 * velocity.y) * dt
        let speed = hypot(velocity.x, velocity.y)
        if speed > 2800 {
            velocity.x *= 2800 / speed
            velocity.y *= 2800 / speed
        }
        offset.x += velocity.x * dt
        offset.y += velocity.y * dt
        squashVelocity += (-210 * squash - 16 * squashVelocity) * dt
        squash += squashVelocity * dt
        if abs(squash) < 0.004 && abs(squashVelocity) < 0.02 {
            squash = 0
            squashVelocity = 0
        }
    }
}

@MainActor
final class EchoBallView: NSView {
    var reducedMotion = false {
        didSet {
            guard reducedMotion != oldValue else { return }
            if reducedMotion { motion = EchoMotion() }
            synchronizeAnimation()
            needsDisplay = true
        }
    }
    var lightInk = false { didSet { needsDisplay = true } }
    private(set) var motion = EchoMotion()
    private(set) var isAnimating = false
    private var timer: Timer?
    private var visibilityObservation: NSKeyValueObservation?
    private var tracking: NSTrackingArea?
    private var mouseMonitor: Any?
    private weak var motionWindow: NSWindow?
    private var previousMouseMovedSetting: Bool?
    private var pointer: CGPoint?
    private var lastFrame: TimeInterval = 0
    private var blinkAt: TimeInterval = 0

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 140, height: 140) }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 140, height: 140))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Echo paper companion")
        setAccessibilityHelp("Eyes follow your cursor. Activate to squish the dotted rings.")
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard let window else { return }
        visibilityObservation = window.observe(\.isVisible, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.synchronizeAnimation() }
        }
        let center = NotificationCenter.default
        for notification in [NSWindow.didChangeOcclusionStateNotification,
                             NSWindow.didBecomeKeyNotification,
                             NSWindow.didMiniaturizeNotification,
                             NSWindow.didDeminiaturizeNotification,
                             NSWindow.willCloseNotification] {
            center.addObserver(self, selector: #selector(visibilityChanged), name: notification, object: window)
        }
        synchronizeAnimation()
    }

    override func viewDidHide() { super.viewDidHide(); synchronizeAnimation() }
    override func viewDidUnhide() { super.viewDidUnhide(); synchronizeAnimation() }

    @objc private func visibilityChanged(_ notification: Notification) {
        if notification.name == NSWindow.willCloseNotification { stop() }
        else { synchronizeAnimation() }
    }

    private func synchronizeAnimation() {
        // Deckle's own screen-saver-level paper window can mark the menu
        // occluded. Window visibility, not occlusion, is the animation gate.
        let visible = window?.isVisible == true && window?.isMiniaturized == false
            && !isHiddenOrHasHiddenAncestor
        guard visible && !reducedMotion else {
            pauseAnimation()
            return
        }
        guard timer == nil else { return }
        lastFrame = ProcessInfo.processInfo.systemUptime
        blinkAt = lastFrame + 2.2
        isAnimating = true
        motionWindow = window
        previousMouseMovedSetting = window?.acceptsMouseMovedEvents
        window?.acceptsMouseMovedEvents = true
        let tick = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.advanceFrame() }
        }
        tick.tolerance = 1 / 240
        timer = tick
        RunLoop.main.add(tick, forMode: .common)
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            // Stored callbacks are not actor-isolated under the release compiler.
            let location = event.locationInWindow
            let eventWindow = event.window
            Task { @MainActor [weak self] in
                guard let self, self.window === eventWindow else { return }
                self.pointer = self.convert(location, from: nil)
            }
            return event
        }
    }

    func stop() {
        visibilityObservation?.invalidate()
        visibilityObservation = nil
        pauseAnimation()
        NotificationCenter.default.removeObserver(self)
    }

    private func pauseAnimation() {
        timer?.invalidate()
        timer = nil
        isAnimating = false
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor); self.mouseMonitor = nil }
        if let previousMouseMovedSetting {
            motionWindow?.acceptsMouseMovedEvents = previousMouseMovedSetting
        }
        previousMouseMovedSetting = nil
        motionWindow = nil
    }

    private func advanceFrame() {
        guard isAnimating else { return }
        // Retained MenuBarExtra content may never receive onDisappear.
        guard window?.isVisible == true, window?.isMiniaturized == false,
              !isHiddenOrHasHiddenAncestor else { synchronizeAnimation(); return }
        let now = ProcessInfo.processInfo.systemUptime
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var target = CGPoint.zero
        if let pointer {
            let dx = pointer.x - center.x
            let dy = pointer.y - center.y
            let distance = hypot(dx, dy)
            if distance > 1 && distance < 420 {
                target = CGPoint(x: dx / distance * 16, y: dy / distance * 12)
            }
        }
        motion.advance(seconds: now - lastFrame, target: target)
        lastFrame = now
        if now > blinkAt + 0.13 { blinkAt = now + Double.random(in: 2.6...6.2) }
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited], owner: self)
        tracking = area
        addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) { pointer = convert(event.locationInWindow, from: nil) }
    override func mouseDown(with event: NSEvent) { squish() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 || event.keyCode == 36 { squish() }
        else { super.keyDown(with: event) }
    }
    override func accessibilityPerformPress() -> Bool { squish(); return true }

    private func squish() {
        guard !reducedMotion else { return }
        motion.squash = 1
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let radius = min(bounds.width, bounds.height) * 0.33
        let center = CGPoint(x: bounds.midX + motion.offset.x, y: bounds.midY + motion.offset.y)
        let ink = lightInk ? NSColor(srgbRed: 121 / 255, green: 198 / 255, blue: 232 / 255, alpha: 1)
            : NSColor(srgbRed: 14 / 255, green: 14 / 255, blue: 12 / 255, alpha: 1)
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        let speed = hypot(motion.velocity.x, motion.velocity.y)
        let stretch = min(1, speed / 2400) * 0.2
        if stretch > 0.015 {
            let angle = atan2(motion.velocity.y, motion.velocity.x)
            context.rotate(by: angle)
            context.scaleBy(x: 1 + stretch, y: 1 - stretch * 0.72)
            context.rotate(by: -angle)
        }
        context.scaleBy(x: 1 + motion.squash * 0.22, y: 1 - motion.squash * 0.3)
        for dot in EchoGeometry.dots(radius: radius, phase: motion.phase) {
            context.setFillColor(ink.withAlphaComponent(dot.opacity).cgColor)
            context.fillEllipse(in: CGRect(x: dot.center.x - dot.radius, y: dot.center.y - dot.radius,
                                          width: dot.radius * 2, height: dot.radius * 2))
        }
        let core = max(8, radius * 0.16 + sin(motion.phase * 2) * 1.1)
        context.setFillColor(ink.cgColor)
        context.fillEllipse(in: CGRect(x: -core, y: -core, width: core * 2, height: core * 2))
        let gaze = EchoGeometry.gaze(pointer: pointer ?? center, center: center, radius: radius)
        let open = isAnimating ? EchoGeometry.openness(timeUntilBlink: blinkAt - ProcessInfo.processInfo.systemUptime) : 1
        let eyeRadius = radius * 0.2
        for side in [-1.0, 1.0] {
            let eye = CGPoint(x: side * radius * 0.34 + gaze.x * 0.6, y: -radius * 0.18 + gaze.y * 0.6)
            let white = NSColor(srgbRed: 253 / 255, green: 251 / 255, blue: 242 / 255, alpha: 1)
            if open < 0.12 {
                context.setStrokeColor(white.cgColor)
                context.setLineWidth(2.2)
                context.move(to: CGPoint(x: eye.x - eyeRadius * 0.9, y: eye.y))
                context.addLine(to: CGPoint(x: eye.x + eyeRadius * 0.9, y: eye.y))
                context.strokePath()
            } else {
                context.saveGState()
                context.translateBy(x: eye.x, y: eye.y)
                context.scaleBy(x: 1, y: max(0.12, open))
                context.setFillColor(white.cgColor)
                context.fillEllipse(in: CGRect(x: -eyeRadius, y: -eyeRadius, width: eyeRadius * 2, height: eyeRadius * 2))
                let pupil = eyeRadius * 0.46
                context.setFillColor(NSColor(srgbRed: 14 / 255, green: 14 / 255, blue: 12 / 255, alpha: 1).cgColor)
                context.fillEllipse(in: CGRect(x: gaze.x * 0.5 - pupil, y: gaze.y * 0.5 / max(0.2, open) - pupil,
                                              width: pupil * 2, height: pupil * 2))
                context.restoreGState()
            }
        }
        context.restoreGState()
    }
}
