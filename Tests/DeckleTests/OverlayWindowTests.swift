import XCTest
import AppKit
@testable import Deckle

final class OverlayWindowTests: XCTestCase {
    @MainActor
    func testOverlayIsAnIndependentFullDisplayPanel() throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("No display attached")
        }
        _ = NSApplication.shared
        let window = OverlayWindow(screen: screen)
        defer { window.close() }

        XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(window.hidesOnDeactivate)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertFalse(window.isOpaque)
        XCTAssertFalse(window.hasShadow)
        XCTAssertEqual(window.frame, screen.frame)
        XCTAssertEqual(window.level, .screenSaver)
        XCTAssertEqual(window.animationBehavior, .none)
        for behavior: NSWindow.CollectionBehavior in [
            .canJoinAllSpaces, .canJoinAllApplications, .stationary,
            .fullScreenAuxiliary, .ignoresCycle,
        ] {
            XCTAssertTrue(window.collectionBehavior.contains(behavior))
        }
    }

    @MainActor
    func testPresentedOverlayTracksAlphaVisibilityAndCaptureSetting() throws {
        guard let screen = NSScreen.screens.first else { throw XCTSkip("No display attached") }
        _ = NSApplication.shared
        let window = OverlayWindow(screen: screen)
        defer { window.close() }
        window.sharingType = .readOnly
        window.alphaValue = 0
        window.apply(texture: TexturePreset.all[0], adjustments: .none)
        window.orderFrontRegardless()
        XCTAssertTrue(window.isVisible)
        if window.presentedWindowID == CGWindowID(window.windowNumber) {
            throw XCTSkip("Direct compositor entry points unavailable; AppKit fallback is in use")
        }

        func info() throws -> [String: Any] {
            try XCTUnwrap((CGWindowListCopyWindowInfo(.optionAll, 0) as? [[String: Any]])?
                .first { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == window.presentedWindowID })
        }
        let first = try info()
        XCTAssertEqual(first[kCGWindowLayer as String] as? Int, 1000)
        XCTAssertEqual(first[kCGWindowSharingState as String] as? Int, 1)

        // An almost transparent test overlay does not change the user's screen.
        // Exercise the controller's fade path, not just its Swift property:
        // both must reach the directly drawn server window.
        window.fade(to: 0.002, duration: 0.05)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
        XCTAssertEqual(try XCTUnwrap(try info()[kCGWindowAlpha as String] as? Double), 0.002, accuracy: 0.0001)

        window.orderOut(nil)
        XCTAssertFalse(window.isVisible)
        window.orderFrontRegardless()
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(try info()[kCGWindowNumber as String] as? Int, Int(window.presentedWindowID))
        let id = window.presentedWindowID
        window.close()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        let closed = (CGWindowListCopyWindowInfo(.optionAll, 0) as? [[String: Any]] ?? [])
            .first { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id }
        XCTAssertFalse(closed?[kCGWindowIsOnscreen as String] as? Bool ?? false)
    }
}
