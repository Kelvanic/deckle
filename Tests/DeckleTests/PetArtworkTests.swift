import XCTest
import AppKit
@testable import Deckle

final class PetArtworkTests: XCTestCase {
    private let canvas = CGRect(origin: .zero, size: PetArtwork.canvas)
    private let display = CGRect(x: -1440, y: -900, width: 1440, height: 875)

    /// Every layer shares the canvas coordinate space. A zero-bounds layer
    /// silently pivots rotations and blinks around the canvas corner, which
    /// is how tails, fins, and eyes once came loose.
    @MainActor
    func testEveryPartUsesTheSharedCanvasSpace() {
        for kind in PetKind.allCases {
            let rig = PetRig(kind: kind)
            var visited = 0
            func visit(_ layer: CALayer) {
                visited += 1
                XCTAssertEqual(layer.bounds.size, PetArtwork.canvas, "\(kind) layer has its own space")
                layer.sublayers?.forEach(visit)
            }
            visit(rig.root)
            XCTAssertGreaterThan(visited, 20)
        }
    }

    /// The host owns size; poses own everything below it.
    @MainActor
    func testPosesNeverOverrideTheHostScale() {
        for kind in PetKind.allCases {
            let rig = PetRig(kind: kind)
            rig.place(in: CGRect(x: 0, y: 0, width: 208, height: 156)) // Large
            for t in stride(from: 0.0, to: 40, by: 1.7) {
                rig.apply(PetMotion.frame(kind: kind, mood: .playful, time: t,
                                          in: display, spriteSize: PetArtwork.canvas))
                let transform = rig.root.affineTransform()
                XCTAssertEqual(transform.a, 1.3, accuracy: 0.0001)
                XCTAssertEqual(transform.d, 1.3, accuracy: 0.0001)
                XCTAssertEqual(transform.b, 0, accuracy: 0.0001)
            }
        }
    }

    /// The pet window clips at the canvas, so no pose may draw past it — a
    /// sitting cat's ears, a sleeping cat's z's, a fish's bubbles.
    @MainActor
    func testArtworkStaysInsideTheCanvasInEveryPose() {
        for kind in PetKind.allCases {
            let rig = PetRig(kind: kind)
            for mood in PetMood.allCases {
                for step in 0..<1200 {
                    let t = Double(step) * 0.5 // ten minutes reaches the rarer tricks
                    var frame = PetMotion.frame(kind: kind, mood: mood, time: t, in: display,
                                                spriteSize: PetArtwork.canvas,
                                                cursor: CGPoint(x: -1400, y: -40))
                    // Also check the mirror image: tilt follows facing.
                    for mirror in [false, true] {
                        if mirror {
                            frame.facing = -frame.facing
                            frame.rotation = -frame.rotation
                        }
                        let facing = frame.facing
                        rig.apply(frame)
                        let drawn = rig.artworkBounds()
                        XCTAssertFalse(drawn.isNull)
                        XCTAssertTrue(canvas.insetBy(dx: -0.5, dy: -0.5).contains(drawn),
                                      "\(kind)/\(mood) at t=\(t) facing \(facing) drew \(drawn)")
                    }
                }
            }
            for still in [PetMotionFrame.portrait(kind), PetMotionFrame.portrait(kind).settled()] {
                rig.apply(still)
                XCTAssertTrue(canvas.contains(rig.artworkBounds()))
            }
        }
    }

    /// Named postures actually change the silhouette, so a nap or a sit is
    /// never just the standing pose with the eyes closed.
    @MainActor
    func testPosturesChangeTheSilhouette() {
        let rig = PetRig(kind: .cat)
        var base = PetMotionFrame.portrait(.cat)
        base.pose = .stand
        rig.apply(base)
        let standing = rig.artworkBounds()
        for pose in [PetPose(sit: 1), PetPose(lie: 1), PetPose(stretch: 1)] {
            var frame = base
            frame.pose = pose
            rig.apply(frame)
            let posed = rig.artworkBounds()
            let moved = abs(posed.minX - standing.minX) + abs(posed.maxX - standing.maxX)
                + abs(posed.maxY - standing.maxY)
            XCTAssertGreaterThan(moved, 8, "\(pose) looks like standing")
        }
        var lying = base
        lying.pose = PetPose(lie: 1)
        rig.apply(lying)
        XCTAssertLessThan(rig.artworkBounds().maxY, standing.maxY - 6, "a nap should lower the cat")
    }

    @MainActor
    func testPortraitFramesTheDrawingNotTheCanvas() {
        let view = PetRigView(kind: .cat)
        view.frame = CGRect(x: 0, y: 0, width: 160, height: 84)
        view.fitsArtwork = true
        view.pose(.portrait(.cat))
        view.layoutSubtreeIfNeeded()
        let drawn = view.rig.artworkBounds()
        let scale = view.rig.root.affineTransform().a
        // Filling the height means the drawn pose, not the 120-point canvas,
        // sets the scale.
        XCTAssertEqual(drawn.height * scale, 84 - 2 * PetRigView.portraitMargin * scale, accuracy: 1)
        XCTAssertGreaterThan(scale, 84 / PetArtwork.canvas.height)
    }
}
