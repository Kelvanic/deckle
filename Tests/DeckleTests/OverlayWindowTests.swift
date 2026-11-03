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
}
