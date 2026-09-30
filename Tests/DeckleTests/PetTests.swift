import XCTest
import AppKit
@testable import Deckle

final class PetTests: XCTestCase {
    @MainActor
    private func withState(_ body: (AppState, UserDefaults) throws -> Void) throws {
        let suite = "DeckleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(AppState(defaults: defaults), defaults)
    }

    // MARK: Persistence

    @MainActor
    func testPetsDefaultOffAndSettingsRoundTrip() throws {
        try withState { state, defaults in
            XCTAssertFalse(state.petsEnabled)
            XCTAssertEqual(state.petKind, .cat)
            XCTAssertEqual(state.petMood, .sleepy)
            XCTAssertEqual(state.petSize, .medium)
            XCTAssertNil(state.petDisplayID)

            state.petsEnabled = true
            state.petKind = .fish
            state.petMood = .playful
            state.petSize = .large
            state.petDisplayID = "7"

            let relaunched = AppState(defaults: defaults)
            XCTAssertTrue(relaunched.petsEnabled)
            XCTAssertEqual(relaunched.petKind, .fish)
            XCTAssertEqual(relaunched.petMood, .playful)
            XCTAssertEqual(relaunched.petSize, .large)
            XCTAssertEqual(relaunched.petDisplayID, "7")
        }
    }

    @MainActor
    func testUnknownStoredPetValuesRecoverToDefaults() throws {
        try withState { _, defaults in
            defaults.set(true, forKey: "petsEnabled")
            defaults.set("dragon", forKey: "petKind")
            defaults.set("feral", forKey: "petMood")
            defaults.set("colossal", forKey: "petSize")
            let recovered = AppState(defaults: defaults)
            XCTAssertTrue(recovered.petsEnabled)
            XCTAssertEqual(recovered.petKind, .cat)
            XCTAssertEqual(recovered.petMood, .sleepy)
            XCTAssertEqual(recovered.petSize, .medium)
        }
    }

    // MARK: Visibility rules

    @MainActor
    func testPetsIndependentOfPaperStateAndPreviewCannotForceThem() throws {
        try withState { state, _ in
            state.isEnabled = false
            state.snooze(minutes: 30)
            state.petsEnabled = true
            XCTAssertTrue(state.petsAreVisible(on: "1", frontmost: nil))

            // A Paper Mill preview and comparison touch only the paper.
            state.previewPaper = CustomPaper(seed: 7)
            state.isComparingOriginal = true
            XCTAssertTrue(state.petsAreVisible(on: "1", frontmost: nil))

            // But pets cannot be forced on by anything else.
            state.petsEnabled = false
            XCTAssertFalse(state.petsAreVisible(on: "1", frontmost: nil))
        }
    }

    @MainActor
    func testPetRespectsExclusionsAndAppRules() throws {
        try withState { state, _ in
            state.petsEnabled = true
            state.excludedDisplays = ["2"]
            XCTAssertTrue(state.petsAreVisible(on: "1", frontmost: nil))
            XCTAssertFalse(state.petsAreVisible(on: "2", frontmost: nil))

            state.appRuleMode = .except
            state.ruleApps = [.init(bundleID: "test.blocker", name: "Blocker")]
            XCTAssertFalse(state.petsAreVisible(on: "1", frontmost: "test.blocker"))
            XCTAssertTrue(state.petsAreVisible(on: "1", frontmost: "test.other"))

            state.appRuleMode = .only
            XCTAssertFalse(state.petsAreVisible(on: "1", frontmost: "test.other"))
            XCTAssertTrue(state.petsAreVisible(on: "1", frontmost: "test.blocker"))
        }
    }

    @MainActor
    func testApplyingDeskSetupLeavesPetsUntouched() throws {
        try withState { state, _ in
            state.petsEnabled = true
            state.petKind = .fish
            XCTAssertTrue(state.apply(DeskSetup.starters[0]))
            XCTAssertTrue(state.petsEnabled)
            XCTAssertEqual(state.petKind, .fish)
        }
    }

    // MARK: Placement

    func testPlacementPrefersConnectedIncludedDisplay() {
        let displays = [
            PetDisplay(id: "1", visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            PetDisplay(id: "2", visibleFrame: CGRect(x: -1440, y: -900, width: 1440, height: 900)),
        ]
        XCTAssertEqual(PetPlacement.destination(preferredID: "2", displays: displays,
                                                excluded: [])?.id, "2")
        // Disconnected preference falls back without error.
        XCTAssertEqual(PetPlacement.destination(preferredID: "9", displays: displays,
                                                excluded: [])?.id, "1")
        // Nil preference = first eligible.
        XCTAssertEqual(PetPlacement.destination(preferredID: nil, displays: displays,
                                                excluded: [])?.id, "1")
        // Exclusions always win, including the preferred display.
        XCTAssertNil(PetPlacement.destination(preferredID: "1", displays: [displays[0]],
                                              excluded: ["1"]))
        XCTAssertEqual(PetPlacement.destination(preferredID: "2", displays: displays,
                                                excluded: ["2"])?.id, "1")
        // Degenerate frames are never eligible.
        let bad = PetDisplay(id: "3", visibleFrame: CGRect(x: 0, y: 0, width: 0, height: 900))
        XCTAssertNil(PetPlacement.destination(preferredID: nil, displays: [bad], excluded: []))
        let nan = PetDisplay(id: "4", visibleFrame: CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100))
        XCTAssertNil(PetPlacement.destination(preferredID: nil, displays: [nan], excluded: []))
    }

    // MARK: Motion

    private let display = CGRect(x: -1440, y: -900, width: 1440, height: 875)
    private let sprite = CGSize(width: 160, height: 120)

    func testMotionIsDeterministicAndFinite() {
        for kind in PetKind.allCases {
            for mood in PetMood.allCases {
                for i in 0..<400 {
                    let t = Double(i) * 0.37
                    let a = PetMotion.frame(kind: kind, mood: mood, time: t,
                                            in: display, spriteSize: sprite)
                    let b = PetMotion.frame(kind: kind, mood: mood, time: t,
                                            in: display, spriteSize: sprite)
                    XCTAssertEqual(a, b)
                    XCTAssertTrue(a.center.x.isFinite && a.center.y.isFinite)
                    XCTAssertTrue(a.rotation.isFinite)
                }
            }
        }
    }

    func testWholeSpriteStaysInsideVisibleFrameOnNegativeCoordinateDisplay() {
        for kind in PetKind.allCases {
            for mood in PetMood.allCases {
                for i in 0..<600 {
                    let t = Double(i) * 0.23
                    let frame = PetMotion.frame(kind: kind, mood: mood, time: t,
                                                in: display, spriteSize: sprite)
                    let bounds = PetMotion.safeBounds(display, spriteSize: sprite)
                    let rect = PetMotion.windowRect(center: frame.center,
                                                    spriteSize: sprite, bounds: bounds)
                    XCTAssertTrue(rect.intersection(display).equalTo(rect),
                                  "\(kind) \(mood) escaped at t=\(t): \(rect)")
                }
            }
        }
    }

    func testMotionIsContinuousAcrossCycleBoundary() {
        for kind in PetKind.allCases {
            for mood in PetMood.allCases {
                var previous = PetMotion.frame(kind: kind, mood: mood, time: 0,
                                               in: display, spriteSize: sprite)
                var maxStep: CGFloat = 0
                for i in 1...2400 {
                    let t = Double(i) * 0.05 // 120 s — covers every cycle
                    let next = PetMotion.frame(kind: kind, mood: mood, time: t,
                                               in: display, spriteSize: sprite)
                    let step = hypot(next.center.x - previous.center.x,
                                     next.center.y - previous.center.y)
                    maxStep = max(maxStep, step)
                    previous = next
                }
                // 50 ms steps should move at most a few points — no teleports.
                XCTAssertLessThan(maxStep, 20, "\(kind)/\(mood) teleported")
            }
        }
    }

    /// Over half an hour each mood shows its full repertoire.
    func testMoodsReachTheirSignatureActivities() {
        func repertoire(_ kind: PetKind, _ mood: PetMood) -> Set<PetActivity> {
            var seen: Set<PetActivity> = []
            for i in 0..<3600 {
                seen.insert(PetMotion.frame(kind: kind, mood: mood, time: Double(i) * 0.5,
                                            in: display, spriteSize: sprite).activity)
            }
            return seen
        }
        let expected: [(PetKind, PetMood, Set<PetActivity>)] = [
            (.cat, .sleepy, [.walk, .rest, .look, .groom, .stretch, .knead, .sleep]),
            (.cat, .curious, [.walk, .rest, .look, .groom, .stretch, .pounce, .chase]),
            (.cat, .playful, [.walk, .rest, .pounce, .chase, .zoom, .stretch]),
            (.fish, .sleepy, [.swim, .doze, .nibble]),
            (.fish, .curious, [.swim, .nibble, .dart, .loop, .roll]),
            (.fish, .playful, [.swim, .dart, .loop, .roll]),
        ]
        for (kind, mood, activities) in expected {
            let seen = repertoire(kind, mood)
            XCTAssertTrue(seen.isSuperset(of: activities),
                          "\(kind)/\(mood) never showed \(activities.subtracting(seen))")
        }

        // Fish must actually swim — both axes travel.
        var xs: Set<Int> = [], ys: Set<Int> = []
        for i in 0..<2000 {
            let f = PetMotion.frame(kind: .fish, mood: .curious, time: Double(i) * 0.1,
                                    in: display, spriteSize: sprite)
            xs.insert(Int(f.center.x))
            ys.insert(Int(f.center.y))
        }
        XCTAssertGreaterThan(xs.count, 100)
        XCTAssertGreaterThan(ys.count, 60)
    }

    /// Behavior is drawn from seeded plans: the sequence of things a pet does
    /// keeps changing from one stretch of time to the next, yet the same
    /// inputs always replay it exactly.
    func testBehaviorVariesButReplaysExactly() {
        for kind in PetKind.allCases {
            for mood in PetMood.allCases {
                func story(from start: Double) -> [PetActivity] {
                    var sequence: [PetActivity] = []
                    for i in 0..<600 {
                        let activity = PetMotion.frame(kind: kind, mood: mood, time: start + Double(i) * 0.5,
                                                       in: display, spriteSize: sprite).activity
                        if sequence.last != activity { sequence.append(activity) }
                    }
                    return sequence
                }
                let stories = [0.0, 300, 600, 900].map(story)
                XCTAssertEqual(Set(stories.map { $0.map(\.rawValue).joined(separator: ",") }).count, 4,
                               "\(kind)/\(mood) repeats itself")
                XCTAssertEqual(story(from: 300), stories[1])
            }
        }
    }

    /// Gait and tail phases must advance at a bounded rate however long the
    /// app has been running — `time × speed-dependent frequency` spins the
    /// limbs wildly after a few minutes of uptime.
    func testAnimationPhasesStaySmoothAtLongUptimes() {
        for kind in PetKind.allCases {
            for mood in PetMood.allCases {
                for start in [5.0, 3_600, 86_400] {
                    var previous = PetMotion.frame(kind: kind, mood: mood, time: start,
                                                   in: display, spriteSize: sprite)
                    for i in 1...900 {
                        let next = PetMotion.frame(kind: kind, mood: mood, time: start + Double(i) / 30,
                                                   in: display, spriteSize: sprite)
                        XCTAssertLessThan(abs(next.tailPhase - previous.tailPhase), 0.1,
                                          "\(kind)/\(mood) tail spun at t=\(start)")
                        if next.limbAmplitude > 0.05 {
                            XCTAssertLessThan(abs(next.limbPhase - previous.limbPhase), 0.2,
                                              "\(kind)/\(mood) gait spun at t=\(start)")
                        }
                        previous = next
                    }
                }
            }
        }
    }

    /// Turns and posture changes ease across frames — nothing mirrors, sits,
    /// or lies down in a single tick.
    func testTurnsAndPosturesNeverPop() {
        for kind in PetKind.allCases {
            for mood in PetMood.allCases {
                var previous = PetMotion.frame(kind: kind, mood: mood, time: 0,
                                               in: display, spriteSize: sprite)
                var sides: Set<Bool> = []
                for i in 1...(30 * 300) {
                    let next = PetMotion.frame(kind: kind, mood: mood, time: Double(i) / 30,
                                               in: display, spriteSize: sprite)
                    XCTAssertLessThan(abs(next.facing - previous.facing), 0.25,
                                      "\(kind)/\(mood) flipped at t=\(Double(i) / 30)")
                    // Every posture weight except the nibbling mouth, which
                    // is meant to snap open and shut.
                    for (a, b) in zip(next.pose.weights.dropLast(), previous.pose.weights.dropLast()) {
                        XCTAssertLessThan(abs(a - b), 0.15, "\(kind)/\(mood) posture popped at t=\(Double(i) / 30)")
                    }
                    if abs(next.facing) > 0.99 { sides.insert(next.facing > 0) }
                    previous = next
                }
                XCTAssertEqual(sides.count, 2, "\(kind)/\(mood) never turned around")
            }
        }
    }

    func testCatPosturesMatchTheirActivities() {
        for mood in PetMood.allCases {
            for i in 0..<3000 {
                let f = PetMotion.frame(kind: .cat, mood: mood, time: Double(i) * 0.2,
                                        in: display, spriteSize: sprite)
                switch f.activity {
                case .sleep:
                    // Past the settle-in, a sleeping cat is lying with its eyes shut.
                    if f.pose.lie > 0.99 { XCTAssertLessThan(f.eyeOpen, 0.01) }
                case .walk, .zoom:
                    XCTAssertEqual(f.pose.leap, 0)
                    XCTAssertEqual(f.center.y, PetMotion.safeBounds(display, spriteSize: sprite).minY)
                default:
                    break
                }
            }
        }
    }

    /// A blink closes and reopens through its window; it never snaps shut at
    /// the window's edge.
    func testBlinkIsContinuous() {
        for seed in [0.31, 0.57] {
            var previous = PetMotion.blinkOpen(at: 0, seed: seed)
            var closed = false
            for i in 1...(240 * 12) {
                let next = PetMotion.blinkOpen(at: Double(i) / 240, seed: seed)
                XCTAssertLessThan(abs(next - previous), 0.1)
                if next < 0.05 { closed = true }
                previous = next
            }
            XCTAssertTrue(closed, "the eyes never actually close")
        }
    }

    /// Paused motion leaves a grounded, calm still — never a cat frozen
    /// mid-pounce or mid-stride.
    func testSettledFramesAreGroundedAndCalm() {
        let floor = PetMotion.safeBounds(display, spriteSize: sprite).minY
        var sawLeap = false
        for i in 0..<2400 {
            let t = Double(i) * 0.1
            let live = PetMotion.frame(kind: .cat, mood: .playful, time: t, in: display, spriteSize: sprite)
            sawLeap = sawLeap || live.pose.leap > 0.5
            let still = PetMotion.settledFrame(kind: .cat, mood: .playful, time: t,
                                               in: display, spriteSize: sprite)
            XCTAssertEqual(still.center.y, floor)
            XCTAssertEqual(still.center.x, live.center.x)
            XCTAssertEqual(still.pose.leap, 0)
            XCTAssertEqual(still.pose.crouch, 0)
            XCTAssertEqual(still.pose.gallop, 0)
            XCTAssertEqual(still.pose.lookBack, 0)
            XCTAssertEqual(still.pose.groom, 0)
            XCTAssertEqual(still.limbAmplitude, 0)
            XCTAssertEqual(abs(still.facing), 1)
        }
        XCTAssertTrue(sawLeap)
        // A sleeping cat stays asleep when motion pauses.
        var sawSleep = false
        for i in 0..<3000 {
            let t = Double(i) * 0.2
            let live = PetMotion.frame(kind: .cat, mood: .sleepy, time: t, in: display, spriteSize: sprite)
            guard live.pose.lie > 0.9 else { continue }
            sawSleep = true
            let still = PetMotion.settledFrame(kind: .cat, mood: .sleepy, time: t,
                                               in: display, spriteSize: sprite)
            XCTAssertEqual(still.pose.lie, 1)
            XCTAssertEqual(still.eyeOpen, 0)
        }
        XCTAssertTrue(sawSleep)
        // A fish frozen mid-loop is level again.
        for i in 0..<2400 {
            let t = Double(i) * 0.1
            let still = PetMotion.settledFrame(kind: .fish, mood: .playful, time: t,
                                               in: display, spriteSize: sprite)
            XCTAssertEqual(still.rotation, 0)
            XCTAssertEqual(abs(still.facing), 1)
            XCTAssertEqual(still.pose.mouth, 0)
        }
    }

    func testNonFiniteAndNegativeInputsStaySafe() {
        for t in [TimeInterval.nan, .infinity, -.infinity, -50] {
            let frame = PetMotion.frame(kind: .fish, mood: .playful, time: t,
                                        in: display, spriteSize: sprite,
                                        cursor: CGPoint(x: CGFloat.nan, y: .infinity))
            XCTAssertTrue(frame.center.x.isFinite && frame.center.y.isFinite)
            XCTAssertTrue(frame.rotation.isFinite && frame.gaze.isFinite)
        }
        let tiny = PetMotion.safeBounds(CGRect(x: 0, y: 0, width: 10, height: 10),
                                        spriteSize: sprite)
        let frame = PetMotion.frame(kind: .cat, mood: .sleepy, time: 5,
                                    in: CGRect(x: 0, y: 0, width: 10, height: 10),
                                    spriteSize: sprite)
        let rect = PetMotion.windowRect(center: frame.center, spriteSize: sprite, bounds: tiny)
        XCTAssertTrue(rect.midX.isFinite && rect.midY.isFinite,
                      "center=\(frame.center) bounds=\(tiny) rect=\(rect)")
    }
}
