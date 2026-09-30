import XCTest
import AppKit
import SwiftUI
@testable import Deckle

final class PetWindowTests: XCTestCase {
    @MainActor
    private func isolatedState() throws -> AppState {
        let suite = "DeckleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return AppState(defaults: defaults)
    }

    func testPetWindowMatchesOverlayContract() {
        let window = PetWindow(frame: CGRect(x: 0, y: 0, width: 160, height: 120))
        defer { window.close() }
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.level, .screenSaver)
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(window.collectionBehavior.contains(.stationary))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(window.collectionBehavior.contains(.ignoresCycle))
    }

    @MainActor
    func testControllerShowsAnimatesAndPausesWithoutJump() async throws {
        guard let screen = NSScreen.screens.first, screen.displayID != nil else {
            throw XCTSkip("No display attached")
        }
        let state = try isolatedState()
        state.petsEnabled = true
        let box = EnvBox(PetEnvironment(reduceMotion: false, lowPowerMode: false,
                                        sessionActive: true, screenAsleep: false))
        let controller = PetController(state: state, environment: { box.value })
        defer { controller.stop() }
        controller.start()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(controller.isAnimating)
        XCTAssertNotNil(controller.windowForTesting)
        XCTAssertTrue(controller.windowForTesting?.isVisible == true)

        // Reduce Motion → still on screen, no ticking.
        box.value.reduceMotion = true
        controller.updateEnvironment()
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertFalse(controller.isAnimating)
        XCTAssertTrue(controller.windowForTesting?.isVisible == true)

        // Resume — animates again without a time jump.
        box.value.reduceMotion = false
        controller.updateEnvironment()
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertTrue(controller.isAnimating)

        // Low Power Mode → still, not hidden.
        box.value.lowPowerMode = true
        controller.updateEnvironment()
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertFalse(controller.isAnimating)
        XCTAssertTrue(controller.windowForTesting?.isVisible == true)

        // Display sleep hides the pet entirely.
        box.value.screenAsleep = true
        controller.updateEnvironment()
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertFalse(controller.windowForTesting?.isVisible ?? false)

        // Disabling pets removes the window.
        box.value = PetEnvironment(reduceMotion: false, lowPowerMode: false,
                                   sessionActive: true, screenAsleep: false)
        state.petsEnabled = false
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(controller.windowForTesting?.isVisible ?? false)
        XCTAssertFalse(controller.isAnimating)
    }

    /// Size settings reach both the window and the artwork inside it.
    @MainActor
    func testPetSizeScalesWindowAndArtworkTogether() async throws {
        guard let screen = NSScreen.screens.first, screen.displayID != nil,
              screen.visibleFrame.width > 600, screen.visibleFrame.height > 500 else {
            throw XCTSkip("No display large enough")
        }
        let state = try isolatedState()
        state.petsEnabled = true
        state.petDisplayID = screen.displayID.map { String($0) }
        let box = EnvBox(PetEnvironment(reduceMotion: true, lowPowerMode: false,
                                        sessionActive: true, screenAsleep: false))
        let controller = PetController(state: state, environment: { box.value })
        defer { controller.stop() }
        controller.start()
        for size in PetSize.allCases {
            state.petSize = size
            controller.updateEnvironment()
            try await Task.sleep(nanoseconds: 60_000_000)
            let window = try XCTUnwrap(controller.windowForTesting)
            XCTAssertEqual(window.frame.width, PetArtwork.canvas.width * size.scale, accuracy: 0.5)
            let rigView = try XCTUnwrap(window.contentView as? PetRigView)
            rigView.layoutSubtreeIfNeeded()
            XCTAssertEqual(rigView.rig.root.affineTransform().a, size.scale, accuracy: 0.01)
            XCTAssertTrue(screen.visibleFrame.contains(window.frame))
        }
    }

    /// Stopping the controller detaches it: later preference changes must
    /// not bring the window back.
    @MainActor
    func testStoppedControllerIgnoresLaterChanges() async throws {
        guard NSScreen.screens.first?.displayID != nil else { throw XCTSkip("No display attached") }
        let state = try isolatedState()
        state.petsEnabled = true
        let controller = PetController(state: state, environment: {
            PetEnvironment(reduceMotion: false, lowPowerMode: false, sessionActive: true, screenAsleep: false)
        })
        controller.start()
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(controller.windowForTesting?.isVisible == true)
        controller.stop()
        state.petKind = .fish
        state.petMood = .playful
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(controller.windowForTesting?.isVisible ?? false)
        XCTAssertFalse(controller.isAnimating)
    }

    @MainActor
    func testMenuViewPetsModeFitsCompactPopover() throws {
        let state = try isolatedState()
        for kind in PetKind.allCases {
            state.petKind = kind
            for scheme in [ColorScheme.light, .dark] {
                let host = NSHostingView(rootView: MenuView(initialMode: .pets)
                    .environmentObject(state).environment(\.colorScheme, scheme))
                XCTAssertEqual(host.fittingSize.width, 370)
                XCTAssertGreaterThan(host.fittingSize.height, 400)
            }
        }
    }
}

/// Mutable box so tests can flip environment flags between refreshes.
private final class EnvBox {
    var value: PetEnvironment
    init(_ value: PetEnvironment) { self.value = value }
}
