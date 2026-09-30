import XCTest
import AppKit
@testable import Deckle

final class EchoBallTests: XCTestCase {
    func testReferenceRingsKeepTheirCountsAndRotateInOppositeDirections() {
        let start = EchoGeometry.dots(radius: 85, phase: 0)
        let later = EchoGeometry.dots(radius: 85, phase: 1)
        XCTAssertEqual(start.count, 183)
        XCTAssertEqual(later.count, 183)
        XCTAssertEqual(atan2(later[0].center.y, later[0].center.x), 0.3, accuracy: 1e-9)
        XCTAssertEqual(atan2(later[13].center.y, later[13].center.x), -0.3, accuracy: 1e-9)
        XCTAssertEqual(start.first?.opacity, 0.81)
        XCTAssertEqual(start.last!.opacity, 0.36, accuracy: 1e-9)
    }

    func testSmallReferenceFieldThinsDeterministicallyAndRemainsBounded() {
        let first = EchoGeometry.dots(radius: 21, phase: 2)
        let repeatFrame = EchoGeometry.dots(radius: 21, phase: 2)
        XCTAssertLessThan(first.count, 183)
        XCTAssertGreaterThan(first.count, 40)
        XCTAssertEqual(first.map(\.center), repeatFrame.map(\.center))
        for dot in first {
            XCTAssertLessThanOrEqual(hypot(dot.center.x, dot.center.y), 21 * 1.06 * 1.035)
            XCTAssertGreaterThanOrEqual(dot.radius, 0.6)
            XCTAssertGreaterThanOrEqual(dot.opacity, 0.55)
        }
    }

    func testGazeSaturatesAndBlinkClosesForReferenceDuration() {
        XCTAssertEqual(EchoGeometry.gaze(pointer: .zero, center: .zero, radius: 50), .zero)
        let far = EchoGeometry.gaze(pointer: CGPoint(x: 1000, y: 0), center: .zero, radius: 50)
        XCTAssertEqual(far.x, 8, accuracy: 1e-9)
        XCTAssertEqual(far.y, 0)
        XCTAssertEqual(EchoGeometry.openness(timeUntilBlink: 0), 0)
        XCTAssertEqual(EchoGeometry.openness(timeUntilBlink: 0.065), 0.5, accuracy: 1e-9)
        XCTAssertEqual(EchoGeometry.openness(timeUntilBlink: -0.13), 1)
    }

    func testSpringSettlesAndResumesWithoutLargeTimeJump() {
        var motion = EchoMotion()
        motion.squash = 1
        for _ in 0..<300 { motion.advance(seconds: 1 / 60, target: CGPoint(x: 16, y: 12)) }
        XCTAssertEqual(motion.offset.x, 16, accuracy: 0.001)
        XCTAssertEqual(motion.offset.y, 12, accuracy: 0.001)
        XCTAssertEqual(motion.squash, 0)
        XCTAssertEqual(motion.phase, 5.4, accuracy: 1e-9)
        let phase = motion.phase
        motion.advance(seconds: 30, target: .zero)
        XCTAssertEqual(motion.phase - phase, 0.054, accuracy: 1e-9)
    }

    @MainActor
    func testAnimationStopsWhenWindowClosesOrMotionIsReduced() async throws {
        let view = EchoBallView()
        XCTAssertFalse(view.isAnimating)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 140, height: 140),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { view.stop(); window.close() }
        view.reducedMotion = true
        window.orderFront(nil)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertFalse(view.isAnimating)
        view.reducedMotion = false
        XCTAssertTrue(view.isAnimating)
        // Wait for a real tick rather than assuming one lands within a fixed
        // sleep — shared CI runners can stall the main run loop for a while.
        for _ in 0..<40 where view.motion.phase == 0 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertGreaterThan(view.motion.phase, 0)
        view.reducedMotion = true
        XCTAssertFalse(view.isAnimating)
        XCTAssertEqual(view.motion.phase, 0)
        view.reducedMotion = false
        window.orderOut(nil)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertFalse(view.isAnimating)
        let stopped = view.motion.phase
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(view.motion.phase, stopped)
        window.orderFront(nil)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(view.isAnimating)
    }
}
