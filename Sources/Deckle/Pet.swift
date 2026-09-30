import AppKit

/// The two paper companions. New pets belong here so persistence, previews,
/// and the desktop rig share one identity.
enum PetKind: String, CaseIterable, Identifiable {
    case cat, fish

    var id: String { rawValue }

    var name: String {
        switch self {
        case .cat: return "Miso"
        case .fish: return "Tide"
        }
    }

    var species: String {
        switch self {
        case .cat: return "Paper cat"
        case .fish: return "Paper fish"
        }
    }

    var behaviorSummary: String {
        switch self {
        case .cat: return "Wanders the bottom of the screen: sits, grooms, looks around, naps, pounces, and chases its tail."
        case .fish: return "Drifts in slow loops, darts, nibbles, dozes, loops the loop, and rolls like a folded card."
        }
    }
}

enum PetMood: String, CaseIterable, Identifiable {
    case sleepy, curious, playful

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sleepy: return "Sleepy"
        case .curious: return "Curious"
        case .playful: return "Playful"
        }
    }
}

enum PetSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// Multiplier on the base artwork canvas.
    var scale: CGFloat {
        switch self {
        case .small: return 0.75
        case .medium: return 1
        case .large: return 1.3
        }
    }
}

/// What the rig is doing at a sampled instant. Used by tests to verify each
/// species and mood actually reaches its signature behavior.
enum PetActivity: String, CaseIterable {
    // Miso
    case walk, zoom, rest, look, groom, stretch, knead, sleep, pounce, chase
    // Tide
    case swim, hover, dart, loop, nibble, doze, roll
}

/// Continuous body posture. Each weight is 0 … 1 and eases across phase
/// joins, so the rig blends between postures instead of snapping. All zero
/// is a plain standing (or swimming) pose.
struct PetPose: Equatable {
    var sit: CGFloat = 0
    /// Lying in a loaf (cat) or dozing (fish).
    var lie: CGFloat = 0
    var stretch: CGFloat = 0
    var crouch: CGFloat = 0
    /// Pounce height: 0 on the walkway … 1 at the top of the leap.
    var leap: CGFloat = 0
    /// Head turned back over the shoulder.
    var lookBack: CGFloat = 0
    /// A front paw raised to the mouth for a wash.
    var groom: CGFloat = 0
    /// Front paws treading while loafing.
    var knead: CGFloat = 0
    /// A bounding sprint gait.
    var gallop: CGFloat = 0
    /// Mouth open mid-nibble (fish).
    var mouth: CGFloat = 0

    static let stand = PetPose()

    /// Every weight, in declaration order — for blending and pop tests.
    var weights: [CGFloat] { [sit, lie, stretch, crouch, leap, lookBack, groom, knead, gallop, mouth] }

    func mixed(with other: PetPose, amount: CGFloat) -> PetPose {
        let a = min(1, max(0, amount.isFinite ? amount : 0))
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * a }
        return PetPose(sit: mix(sit, other.sit), lie: mix(lie, other.lie),
                       stretch: mix(stretch, other.stretch), crouch: mix(crouch, other.crouch),
                       leap: mix(leap, other.leap), lookBack: mix(lookBack, other.lookBack),
                       groom: mix(groom, other.groom), knead: mix(knead, other.knead),
                       gallop: mix(gallop, other.gallop), mouth: mix(mouth, other.mouth))
    }
}

/// A resolved pose for one instant. Pure value so tests can pin determinism.
struct PetMotionFrame: Equatable {
    var center: CGPoint
    /// 1 facing right … -1 facing left. A turn passes through 0, so the
    /// paper cut-out flips edge-on like a card instead of mirroring in a frame.
    var facing: CGFloat
    /// Whole-body tilt in screen space (radians, counter-clockwise positive).
    var rotation: CGFloat
    /// Gait cycles. For the cat this is distance walked divided by stride,
    /// so paws plant instead of skating.
    var limbPhase: Double
    /// 0–1 gait/fin amplitude (0 while resting).
    var limbAmplitude: Double
    /// Tail cycles on a steady clock; the rig varies amplitude only.
    var tailPhase: Double
    /// Seconds on the pet's own clock, for breathing, licks, and bubbles.
    var clock: Double
    /// 1 open … 0 closed, matching Echo's blink convention.
    var eyeOpen: CGFloat
    /// Where the cursor sits relative to the pet, each -1 … 1 in screen space:
    /// horizontally (right positive) and vertically (above positive).
    var gaze: CGFloat
    var gazeLift: CGFloat
    var pose: PetPose
    var activity: PetActivity

    var facingRight: Bool { facing >= 0 }

    /// The calm still shown under Reduce Motion or Low Power Mode: same
    /// place and posture, squared to a side, limbs neutral, eyes open unless
    /// asleep. A cat caught mid-leap or mid-sprint settles into a sit.
    func settled() -> PetMotionFrame {
        var still = self
        still.facing = facing >= 0 ? 1 : -1
        still.rotation = 0
        still.limbPhase = 0
        still.limbAmplitude = 0
        still.tailPhase = 0
        still.clock = 0
        still.gaze = 0
        still.gazeLift = 0
        let asleep = pose.lie >= 0.5
        still.eyeOpen = asleep ? 0 : 1
        switch activity {
        case _ where asleep:
            still.pose = PetPose(lie: 1)
        case .walk, .zoom, .pounce, .chase, .stretch:
            still.pose = PetPose(sit: 1)
        default:
            still.pose = PetPose(sit: pose.sit >= 0.5 ? 1 : 0)
        }
        return still
    }

    /// A composed portrait for companion cards: the cat sitting, the fish
    /// mid-glide, both facing into the card.
    static func portrait(_ kind: PetKind) -> PetMotionFrame {
        PetMotionFrame(
            center: .zero, facing: 1, rotation: 0,
            limbPhase: 0, limbAmplitude: kind == .fish ? 0.4 : 0,
            tailPhase: kind == .fish ? 0.1 : 0.2, clock: 0,
            eyeOpen: 1, gaze: 0.25, gazeLift: 0.2,
            pose: kind == .cat ? PetPose(sit: 1) : .stand,
            activity: kind == .cat ? .rest : .swim)
    }
}

/// A seeded, repeatable stream of choices (splitmix64). Pets draw their
/// plans from it, so behavior looks random yet every frame stays a pure
/// function of its inputs — never `hashValue` or a system random source.
struct PetDice {
    private var state: UInt64

    init(_ seeds: UInt64...) {
        var state: UInt64 = 0x243F_6A88_85A3_08D3
        for seed in seeds { state = PetDice.mix(state ^ seed) }
        self.state = state
    }

    static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0 ..< 1.
    mutating func unit() -> Double {
        state = PetDice.mix(state)
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }

    mutating func range(_ bounds: ClosedRange<Double>) -> Double {
        bounds.lowerBound + (bounds.upperBound - bounds.lowerBound) * unit()
    }

    /// A weighted choice; options must not be empty.
    mutating func pick<T>(_ options: [(T, Double)]) -> T {
        let total = options.reduce(0) { $0 + max(0, $1.1) }
        var roll = unit() * total
        for option in options where option.1 > 0 {
            if roll < option.1 { return option.0 }
            roll -= option.1
        }
        return options[options.count - 1].0
    }
}

/// Deterministic pet motion: a pure function of kind, mood, elapsed time,
/// the display's visible frame, the sprite size, and the cursor position.
/// Behavior is drawn from seeded plans, so it never repeats in a way you'd
/// notice, but the same inputs always give the same pose — no wall-clock
/// reads and no system randomness, which keeps tests honest.
enum PetMotion {
    static func frame(
        kind: PetKind, mood: PetMood, time: TimeInterval,
        in frame: CGRect, spriteSize: CGSize, cursor: CGPoint? = nil
    ) -> PetMotionFrame {
        let bounds = safeBounds(frame, spriteSize: spriteSize)
        let t = time.isFinite ? max(0, time) : 0
        switch kind {
        case .cat: return catFrame(mood: mood, t: t, bounds: bounds, sprite: spriteSize, cursor: cursor)
        case .fish: return fishFrame(mood: mood, t: t, bounds: bounds, sprite: spriteSize, cursor: cursor)
        }
    }

    /// The still used when motion is paused: grounded, squared, and calm.
    static func settledFrame(
        kind: PetKind, mood: PetMood, time: TimeInterval,
        in frame: CGRect, spriteSize: CGSize
    ) -> PetMotionFrame {
        var still = self.frame(kind: kind, mood: mood, time: time,
                               in: frame, spriteSize: spriteSize).settled()
        if kind == .cat {
            still.center.y = safeBounds(frame, spriteSize: spriteSize).minY
        }
        return still
    }

    /// The rectangle the sprite's center may travel within: the visible
    /// frame shrunk by half the sprite plus a margin, so the artwork never
    /// clips into the menu bar or Dock.
    static func safeBounds(_ frame: CGRect, spriteSize: CGSize) -> CGRect {
        guard frame.width.isFinite, frame.height.isFinite,
              frame.minX.isFinite, frame.minY.isFinite else {
            return CGRect(x: 0, y: 0, width: max(1, spriteSize.width), height: max(1, spriteSize.height))
        }
        let insetX = max(0, spriteSize.width / 2 + 8)
        let insetY = max(0, spriteSize.height / 2 + 8)
        let inset = frame.insetBy(dx: insetX, dy: insetY)
        // insetBy returns the null rect when the sprite is bigger than the
        // display — collapse to the frame's centre instead.
        if inset.isNull || inset.isEmpty {
            return CGRect(x: frame.midX, y: frame.midY, width: 0, height: 0)
        }
        return inset
    }

    /// The on-screen window rect for a pose — the sprite centered on the
    /// motion sample, fully contained in the travel bounds.
    static func windowRect(center: CGPoint, spriteSize: CGSize, bounds: CGRect) -> CGRect {
        var c = center
        if !c.x.isFinite { c.x = bounds.midX }
        if !c.y.isFinite { c.y = bounds.midY }
        let halfW = spriteSize.width / 2
        let halfH = spriteSize.height / 2
        c.x = min(max(c.x, bounds.minX), max(bounds.minX, bounds.maxX))
        c.y = min(max(c.y, bounds.minY), max(bounds.minY, bounds.maxY))
        return CGRect(x: c.x - halfW, y: c.y - halfH, width: spriteSize.width, height: spriteSize.height)
    }

    // MARK: Cat — seeded wandering with real dwells

    /// Things Miso might do between strolls. Each mood weights them.
    private enum CatHabit {
        case sit, look, groom, stretch, nap, pounce, chase, zoom
    }

    private struct CatTemperament {
        /// Walking pace, in sprite widths per second.
        let pace: Double
        /// Chance of strolling somewhere new before each habit.
        let wander: Double
        /// Seconds per plan, before the time the walkway itself needs.
        let span: Double
        let habits: [(CatHabit, Double)]
        let nap: ClosedRange<Double>
    }

    private static func temperament(_ mood: PetMood) -> CatTemperament {
        switch mood {
        case .sleepy:
            return CatTemperament(pace: 0.22, wander: 0.55, span: 70,
                                  habits: [(.sit, 3), (.look, 1), (.groom, 2), (.stretch, 2),
                                           (.nap, 3.5), (.pounce, 0.2)],
                                  nap: 14...24)
        case .curious:
            return CatTemperament(pace: 0.3, wander: 0.75, span: 50,
                                  habits: [(.sit, 2.5), (.look, 3), (.groom, 1.2), (.stretch, 1),
                                           (.nap, 0.5), (.pounce, 1), (.chase, 0.6), (.zoom, 0.4)],
                                  nap: 10...16)
        case .playful:
            return CatTemperament(pace: 0.38, wander: 0.8, span: 40,
                                  habits: [(.sit, 0.8), (.look, 1), (.groom, 0.6), (.stretch, 1),
                                           (.nap, 0.15), (.pounce, 3), (.chase, 2), (.zoom, 1.8)],
                                  nap: 8...12)
        }
    }

    /// One step of a plan, between two walkway fractions (equal when Miso
    /// stays put).
    private struct CatStep {
        let activity: PetActivity
        let duration: Double
        let from: Double
        let to: Double

        var moves: Bool { abs(to - from) > 0.000_1 }
        var heading: Double { to >= from ? 1 : -1 }

        /// The posture this step settles into and hands to the next one.
        var endPose: PetPose {
            switch activity {
            case .rest, .look, .groom: return PetPose(sit: 1)
            case .sleep, .knead: return PetPose(lie: 1)
            default: return .stand
            }
        }

        /// Posture partway through the step, before blending in from the
        /// previous step. Every flourish starts and ends on its end pose.
        func pose(at p: Double) -> PetPose {
            let into = p * duration
            switch activity {
            case .rest:
                return PetPose(sit: 1)
            case .sleep:
                return PetPose(lie: 1)
            case .look:
                // Two glances back over the shoulder.
                let first = PetMotion.envelope((p - 0.06) / 0.46, edge: 0.3)
                let second = PetMotion.envelope((p - 0.62) / 0.3, edge: 0.35) * 0.85
                return PetPose(sit: 1, lookBack: CGFloat(max(first, second)))
            case .groom:
                return PetPose(sit: 1, groom: CGFloat(PetMotion.envelope(p, edge: 0.2)))
            case .knead:
                return PetPose(lie: 1, knead: CGFloat(PetMotion.envelope(p, edge: 0.25)))
            case .stretch:
                return PetPose(stretch: CGFloat(PetMotion.envelope(p, edge: 0.3)))
            case .zoom:
                let gallop = PetMotion.smooth(into / 0.6) * PetMotion.smooth((duration - into) / 0.6)
                return PetPose(gallop: CGFloat(gallop))
            case .pounce:
                let crouchIn = PetMotion.smooth(p / 0.2)
                let release = 1 - PetMotion.smooth((p - 0.46) / 0.12)
                let land = p > 0.82 ? sin(.pi * min(1, (p - 0.82) / 0.18)) * 0.45 : 0
                return PetPose(crouch: CGFloat(max(crouchIn * release, land)),
                               leap: CGFloat(sin(.pi * PetMotion.pounceFlight(p))))
            case .chase:
                // Spinning after its own tail in little hops.
                let body = PetMotion.envelope(p, edge: 0.15)
                let hops = abs(sin(6 * .pi * p)) * 0.3 * body
                return PetPose(crouch: CGFloat(0.35 * body), leap: CGFloat(hops),
                               lookBack: CGFloat(0.8 * body))
            default:
                return .stand
            }
        }

        /// 0 … 1 share of this step's walkway travel completed at `p`.
        func travel(at p: Double) -> Double {
            switch activity {
            case .walk, .zoom: return PetMotion.smooth(p)
            case .pounce: return PetMotion.smooth(PetMotion.pounceFlight(p))
            default: return 0
            }
        }
    }

    private struct CatPlan {
        let steps: [CatStep]
        /// Every plan ends on a walk home, so its heading is always defined.
        var endHeading: Double { steps.last(where: { $0.moves })?.heading ?? 1 }
    }

    /// Plans have a fixed length for a given mood and geometry, so the plan
    /// for any instant is found directly — no replay from the start.
    private static func catPlanLength(_ mood: PetMood, walkway: Double, spriteWidth: Double) -> Double {
        let habit = temperament(mood)
        return habit.span + 0.8 * walkway / max(1, habit.pace * spriteWidth)
    }

    /// Where plan `block` starts, which is also where the one before it ends.
    private static func catHome(_ mood: PetMood, block: Int) -> Double {
        var dice = PetDice(moodSeed(mood), 0xCA7_4043, UInt64(bitPattern: Int64(block)))
        return dice.range(0.25...0.75)
    }

    private static func catPlan(_ mood: PetMood, block: Int, walkway: Double, spriteWidth: Double) -> CatPlan {
        let habit = temperament(mood)
        let length = catPlanLength(mood, walkway: walkway, spriteWidth: spriteWidth)
        var dice = PetDice(moodSeed(mood), 0xCA7_91A2, UInt64(bitPattern: Int64(block)))
        let start = catHome(mood, block: block)
        let end = catHome(mood, block: block + 1)
        let pace = max(1, habit.pace * spriteWidth)
        let sprint = max(1, 1.1 * spriteWidth)
        let minimumRest = 2.5
        func stroll(_ a: Double, _ b: Double, _ speed: Double) -> Double {
            max(1.4, abs(b - a) * walkway / speed)
        }
        // The walk home always moves, so the next plan knows which way
        // Miso is facing when it begins.
        func homeward(from a: Double) -> [CatStep] {
            var legs: [CatStep] = []
            var at = a
            if abs(end - at) < 0.06 {
                let detour = at < 0.5 ? at + 0.18 : at - 0.18
                legs.append(CatStep(activity: .walk, duration: stroll(at, detour, pace), from: at, to: detour))
                at = detour
            }
            legs.append(CatStep(activity: .walk, duration: stroll(at, end, pace), from: at, to: end))
            return legs
        }

        var steps: [CatStep] = []
        var at = start
        var used: Double = 0
        for _ in 0..<16 where length - used > 10 {
            var episode: [CatStep] = []
            var here = at
            func stay(_ activity: PetActivity, _ duration: Double) {
                episode.append(CatStep(activity: activity, duration: duration, from: here, to: here))
            }
            if dice.unit() < habit.wander {
                let reach = dice.range(0.12...0.42)
                var target = here + (dice.unit() < 0.5 ? reach : -reach)
                if target < 0.06 || target > 0.94 { target = here - (target - here) }
                target = min(0.94, max(0.06, target))
                episode.append(CatStep(activity: .walk, duration: stroll(here, target, pace), from: here, to: target))
                here = target
            }
            switch dice.pick(habit.habits) {
            case .sit:
                stay(.rest, dice.range(3...7))
            case .look:
                stay(.look, dice.range(3.5...5.5))
            case .groom:
                stay(.groom, dice.range(4.5...6.5))
            case .stretch:
                stay(.stretch, dice.range(3.5...5))
            case .nap:
                stay(.knead, dice.range(2.5...3.5))
                stay(.sleep, dice.range(habit.nap))
                stay(.rest, 3)
            case .pounce:
                let hop = min(0.2, spriteWidth * 0.5 / max(1, walkway))
                let target = here < 0.5 ? here + hop : here - hop
                episode.append(CatStep(activity: .pounce, duration: 3.4, from: here, to: target))
                here = target
                stay(.rest, dice.range(2...3.5))
            case .chase:
                stay(.chase, 4)
                stay(.rest, dice.range(2...3))
            case .zoom:
                let target = here < 0.5 ? dice.range(0.72...0.94) : dice.range(0.06...0.28)
                episode.append(CatStep(activity: .zoom, duration: max(1.2, abs(target - here) * walkway / sprint),
                                       from: here, to: target))
                here = target
                stay(.rest, dice.range(2.5...4))
            }
            let cost = episode.reduce(0) { $0 + $1.duration }
            let home = homeward(from: here).reduce(0) { $0 + $1.duration }
            guard used + cost + home + minimumRest <= length else { continue }
            steps += episode
            used += cost
            at = here
        }
        let legs = homeward(from: at)
        steps += legs
        used += legs.reduce(0) { $0 + $1.duration }
        steps.append(CatStep(activity: .rest, duration: max(minimumRest, length - used), from: end, to: end))
        return CatPlan(steps: steps)
    }

    /// Where the cat is in its plan, independent of screen geometry.
    private struct CatSample {
        var fraction: Double
        /// Gait cycles so far this plan: distance walked over stride length.
        var strides: Double
        var facing: Double
        var pose: PetPose
        var activity: PetActivity
        var progress: Double
    }

    private static let turnDuration = 0.45

    private static func catSample(mood: PetMood, t: Double, walkway: Double, spriteWidth: Double) -> CatSample {
        let length = catPlanLength(mood, walkway: walkway, spriteWidth: spriteWidth)
        let block = Int(max(0, t) / length)
        let local = max(0, t) - Double(block) * length
        let plan = catPlan(mood, block: block, walkway: walkway, spriteWidth: spriteWidth)
        var facing = catPlan(mood, block: block - 1, walkway: walkway, spriteWidth: spriteWidth).endHeading
        // Every plan ends sitting, so the next one starts from a sit.
        var previousPose = PetPose(sit: 1)
        var strides: Double = 0
        var elapsed: Double = 0
        for (index, step) in plan.steps.enumerated() {
            let end = elapsed + step.duration
            let stride = max(1, spriteWidth * (step.activity == .zoom ? 0.45 : 0.2))
            if local < end || index == plan.steps.count - 1 {
                let into = max(0, local - elapsed)
                let p = min(1, into / step.duration)
                let travel = step.travel(at: p)
                var face = facing
                if step.moves, step.heading != facing {
                    // Turn in place during the eased start of a reversal.
                    face = facing + (step.heading - facing) * smooth(into / turnDuration)
                }
                if step.activity == .chase {
                    face *= cos(4 * .pi * smooth(p))
                }
                let blend = smooth(into / min(0.9, step.duration * 0.3))
                return CatSample(
                    fraction: step.from + (step.to - step.from) * travel,
                    strides: strides + abs(step.to - step.from) * travel * walkway / stride,
                    facing: face,
                    pose: previousPose.mixed(with: step.pose(at: p), amount: CGFloat(blend)),
                    activity: step.activity,
                    progress: p)
            }
            strides += abs(step.to - step.from) * walkway / stride
            if step.moves { facing = step.heading }
            previousPose = step.endPose
            elapsed = end
        }
        return CatSample(fraction: 0.5, strides: 0, facing: facing,
                         pose: PetPose(sit: 1), activity: .rest, progress: 0)
    }

    private static func catFrame(mood: PetMood, t: Double, bounds: CGRect,
                                 sprite: CGSize, cursor: CGPoint?) -> PetMotionFrame {
        let walkway = Double(bounds.width)
        let spriteWidth = Double(sprite.width)
        let sample = catSample(mood: mood, t: t, walkway: walkway, spriteWidth: spriteWidth)
        let x = bounds.minX + bounds.width * CGFloat(sample.fraction)
        let leapHeight = min(bounds.height * 0.25, sprite.height * 0.42)
        let y = bounds.minY + leapHeight * sample.pose.leap
        // Nose up on the way into a pounce, nose down on the landing.
        var rotation: CGFloat = 0
        if sample.activity == .pounce {
            rotation = CGFloat(0.16 * sin(2 * .pi * pounceFlight(sample.progress)) * sample.facing)
        }
        // Speed by symmetric difference — only used to size the gait swing.
        let e = 0.04
        let before = catSample(mood: mood, t: max(0, t - e), walkway: walkway, spriteWidth: spriteWidth)
        let after = catSample(mood: mood, t: t + e, walkway: walkway, spriteWidth: spriteWidth)
        let speed = abs(after.fraction - before.fraction) * walkway / (2 * e)
        let pose = sample.pose
        let blink = Double(blinkOpen(at: t, seed: kindSeed(.cat)))
        // Kneading cats half-close their eyes; licking ones close them.
        let dozing = Double(pose.lie) * (1 - 0.4 * Double(pose.knead))
        let awake = blink * (1 - dozing) * (1 - 0.6 * Double(pose.stretch)) * (1 - 0.8 * Double(pose.groom))
        let striding = sample.activity == .walk || sample.activity == .zoom
        let center = CGPoint(x: x, y: y)
        let gaze = cursorGaze(cursor: cursor, center: center)
        return PetMotionFrame(
            center: center,
            facing: CGFloat(sample.facing),
            rotation: rotation,
            limbPhase: sample.strides,
            limbAmplitude: striding ? min(1, speed / (spriteWidth * 0.16)) : 0,
            tailPhase: t * 0.45,
            clock: t,
            eyeOpen: CGFloat(max(0, min(1, awake))),
            gaze: gaze.dx,
            gazeLift: gaze.dy,
            pose: pose,
            activity: sample.activity)
    }

    /// Share of a pounce spent airborne: crouch, then leap over 0.5…0.8.
    static func pounceFlight(_ p: Double) -> Double {
        min(1, max(0, (p - 0.5) / 0.3))
    }

    // MARK: Fish — lissajous drifting with seeded tricks

    private struct FishTemperament {
        /// Speed of the underlying lissajous drift.
        let drift: Double
        /// Seconds per plan.
        let span: Double
        /// Plain drifting between tricks, in seconds.
        let gaps: ClosedRange<Double>
        let tricks: [(PetActivity, Double)]
        let doze: ClosedRange<Double>
    }

    private static func fishTemperament(_ mood: PetMood) -> FishTemperament {
        switch mood {
        case .sleepy:
            return FishTemperament(drift: 0.45, span: 60, gaps: 5...12,
                                   tricks: [(.doze, 4), (.nibble, 1), (.dart, 0.5), (.roll, 0.3), (.loop, 0.2)],
                                   doze: 14...22)
        case .curious:
            return FishTemperament(drift: 1, span: 40, gaps: 3...8,
                                   tricks: [(.nibble, 3), (.dart, 2), (.roll, 1), (.loop, 1), (.doze, 0.8)],
                                   doze: 10...14)
        case .playful:
            return FishTemperament(drift: 1.9, span: 28, gaps: 1.5...4.5,
                                   tricks: [(.dart, 3), (.loop, 2.5), (.roll, 2), (.nibble, 1), (.doze, 0.2)],
                                   doze: 8...10)
        }
    }

    private struct FishTrick {
        let activity: PetActivity
        /// Absolute start time on the pet's clock.
        let start: Double
        let duration: Double
        /// Share of a nibble or doze spent slowing to a hover.
        let hold: Double
    }

    private static func fishPlan(_ mood: PetMood, block: Int) -> [FishTrick] {
        let habit = fishTemperament(mood)
        var dice = PetDice(moodSeed(mood), 0xF15_0B1A, UInt64(bitPattern: Int64(block)))
        let origin = Double(block) * habit.span
        var tricks: [FishTrick] = []
        var clock = dice.range(habit.gaps)
        while clock < habit.span {
            let activity = dice.pick(habit.tricks)
            var hold: Double = 0
            let duration: Double
            switch activity {
            case .dart: duration = 4
            case .loop: duration = 2.8
            case .nibble: duration = 4.2; hold = 0.55
            case .doze: duration = dice.range(habit.doze); hold = 0.7
            default: duration = 2
            }
            guard clock + duration < habit.span - 0.5 else { break }
            tricks.append(FishTrick(activity: activity, start: origin + clock, duration: duration, hold: hold))
            clock += duration + dice.range(habit.gaps)
        }
        return tricks
    }

    /// Where along its drifting path the fish is, after tricks bend time.
    private struct FishMoment {
        /// Path time: real time plus a warp that is zero outside tricks.
        var time: Double
        var trick: FishTrick?
        var progress: Double
    }

    /// A dart speeds the fish along its own path, then lets it glide slow;
    /// a nibble or doze slows it to a hover, then it hurries to catch up.
    /// Each warp integrates to zero, so the path never jumps.
    private static func fishMoment(_ mood: PetMood, t: Double) -> FishMoment {
        let span = fishTemperament(mood).span
        let block = Int(max(0, t) / span)
        for trick in fishPlan(mood, block: block)
        where t >= trick.start && t < trick.start + trick.duration {
            let u = (t - trick.start) / trick.duration
            let d = trick.duration
            switch trick.activity {
            case .dart:
                let split = 0.25
                let burst = 2.2
                let glide = burst * split / (1 - split)
                let warp = burst * bumpArea(u, from: 0, width: split) - glide * bumpArea(u, from: split, width: 1 - split)
                return FishMoment(time: t + d * warp, trick: trick, progress: u)
            case .nibble, .doze:
                let hold = trick.hold
                let hurry = 0.95 * hold / (1 - hold)
                let warp = -0.95 * bumpArea(u, from: 0, width: hold) + hurry * bumpArea(u, from: hold, width: 1 - hold)
                return FishMoment(time: t + d * warp, trick: trick, progress: u)
            default:
                return FishMoment(time: t, trick: trick, progress: u)
            }
        }
        return FishMoment(time: t, trick: nil, progress: 0)
    }

    /// Area under a sin² bump spanning `from ... from + width`, up to `u`.
    private static func bumpArea(_ u: Double, from: Double, width: Double) -> Double {
        let v = min(max(u - from, 0), width)
        return v / 2 - width / (4 * .pi) * sin(2 * .pi * v / width)
    }

    private struct FishState {
        var position: CGPoint
        var moment: FishMoment
        /// Direction the current trick is performed in.
        var heading: CGFloat = 1
        /// Whole-body turn from a loop-de-loop, radians.
        var loop: Double = 0
        var mouth: Double = 0
        var doze: Double = 0
        /// Progress through a barrel roll, 0 outside one.
        var roll: Double = 0
    }

    private static func fishState(_ mood: PetMood, t: Double, bounds: CGRect, sprite: CGSize) -> FishState {
        let drift = fishTemperament(mood).drift
        let ax = 0.055 * drift
        let ay = 0.035 * drift
        let moment = fishMoment(mood, t: t)
        var state = FishState(position: fishPosition(t: moment.time, bounds: bounds, ax: ax, ay: ay),
                              moment: moment)
        guard let trick = moment.trick else { return state }
        // Tricks play out in the direction Tide was swimming as they began.
        state.heading = fishVelocity(t: trick.start, bounds: bounds, ax: ax, ay: ay).dx >= 0 ? 1 : -1
        let u = moment.progress
        switch trick.activity {
        case .loop:
            let radius = min(sprite.height * 0.5, bounds.height * 0.2, bounds.width * 0.1)
            let turn = 2 * .pi * smooth(u)
            state.position.x += radius * CGFloat(sin(turn)) * state.heading
            state.position.y += radius * CGFloat(1 - cos(turn))
            state.loop = turn
        case .nibble:
            let pecking = min(1, max(0, (u - 0.12) / 0.42))
            let peck = pecking > 0 && pecking < 1 ? pow(sin(3 * .pi * pecking), 2) : 0
            state.position.x += CGFloat(4 * peck) * state.heading
            state.mouth = peck
        case .doze:
            let sleep = envelope(u / (trick.hold + 0.12), edge: 0.35)
            state.position.y -= min(12, bounds.height * 0.1) * CGFloat(sleep)
            state.doze = sleep
        case .roll:
            state.roll = u
            state.position.y += 6 * CGFloat(sin(.pi * u))
        default:
            break
        }
        return state
    }

    private static func fishFrame(mood: PetMood, t: Double, bounds: CGRect,
                                  sprite: CGSize, cursor: CGPoint?) -> PetMotionFrame {
        let drift = fishTemperament(mood).drift
        let ax = 0.055 * drift
        let ay = 0.035 * drift
        let state = fishState(mood, t: t, bounds: bounds, sprite: sprite)
        let e = 0.05
        let before = fishState(mood, t: max(0, t - e), bounds: bounds, sprite: sprite).position
        let after = fishState(mood, t: t + e, bounds: bounds, sprite: sprite).position
        let speed = hypot(after.x - before.x, after.y - before.y) / CGFloat(2 * e)
        // Heading and pitch follow the drifting path itself, never a loop or
        // peck offset — a loop-de-loop must not flip the fish around.
        let path = fishVelocity(t: state.moment.time, bounds: bounds, ax: ax, ay: ay)
        var facing = fishFacing(mood: mood, t: t, bounds: bounds, ax: ax, ay: ay)
        if state.roll > 0 {
            facing *= CGFloat(cos(2 * .pi * smooth(state.roll)))
        }
        // Pitch into climbs and dives, capped so near-vertical moments at the
        // turning points never stand the fish on its tail.
        var pitch = atan2(path.dy, max(abs(path.dx), 0.001)) * 0.55
        if !pitch.isFinite { pitch = 0 }
        pitch = min(0.35, max(-0.35, pitch))
        // Calm is a continuous weight, so hovering fades in without a pop.
        let calm = min(1, max(0, 1 - speed / 10))
        var center = state.position
        center.y += CGFloat(sin(t * 1.7)) * (1.2 + 1.8 * calm)
        let gaze = cursorGaze(cursor: cursor, center: center)
        // Tail and fins quicken with the warp, on clocks that stay smooth.
        let warp = state.moment.time - t
        let beat = mood == .playful ? 1.5 : 1.4
        let blink = Double(blinkOpen(at: t, seed: kindSeed(.fish)))
        return PetMotionFrame(
            center: center,
            facing: facing,
            rotation: pitch * facing * (1 - 0.7 * calm) + CGFloat(state.loop) * state.heading,
            limbPhase: 1.1 * (t + 0.3 * warp),
            limbAmplitude: Double(0.3 + 0.7 * min(1, speed / 34)) * (1 - 0.6 * state.doze),
            tailPhase: beat * (t + 0.4 * warp),
            clock: t,
            eyeOpen: CGFloat(blink * (1 - state.doze)),
            gaze: gaze.dx,
            gazeLift: gaze.dy,
            pose: PetPose(lie: CGFloat(state.doze), mouth: CGFloat(state.mouth)),
            activity: state.moment.trick?.activity ?? (speed < 4 ? .hover : .swim))
    }

    private static func fishPosition(t: Double, bounds: CGRect, ax: Double, ay: Double) -> CGPoint {
        let cx = bounds.midX
        let cy = bounds.midY
        let rx = max(1, bounds.width * 0.36)
        let ry = max(1, bounds.height * 0.3)
        // Two harmonic terms per axis → organic, non-repeating-feeling curves
        // that still return to the start each period.
        let x = cx + rx * CGFloat(0.72 * sin(ax * t) + 0.28 * sin(2 * ax * t + 1.3))
        let y = cy + ry * CGFloat(0.75 * sin(ay * t + 0.6) + 0.25 * sin(2 * ay * t))
        return CGPoint(x: x, y: y)
    }

    /// Analytic derivative of `fishPosition`, in points per path-second.
    private static func fishVelocity(t: Double, bounds: CGRect, ax: Double, ay: Double) -> CGVector {
        let rx = Double(max(1, bounds.width * 0.36))
        let ry = Double(max(1, bounds.height * 0.3))
        let dx = rx * (0.72 * ax * cos(ax * t) + 0.56 * ax * cos(2 * ax * t + 1.3))
        let dy = ry * (0.75 * ay * cos(ay * t + 0.6) + 0.5 * ay * cos(2 * ay * t))
        return CGVector(dx: dx, dy: dy)
    }

    /// Facing eased through each reversal: the sign of horizontal velocity
    /// averaged over a short window, which ramps linearly as a reversal
    /// passes through it. The fish rolls edge-on for the same ~0.6 s at any
    /// display size, mood, or warp instead of mirroring in one frame — a
    /// speed threshold would linger edge-on wherever the drift is slow.
    private static func fishFacing(mood: PetMood, t: Double, bounds: CGRect, ax: Double, ay: Double) -> CGFloat {
        let intervals = 12
        let window = 0.6
        let step = window / Double(intervals)
        func vx(_ offset: Double) -> Double {
            // Warps only rescale speed, so the path's own sign is the heading.
            let moment = fishMoment(mood, t: max(0, t + offset))
            return Double(fishVelocity(t: moment.time, bounds: bounds, ax: ax, ay: ay).dx)
        }
        // Share of the window spent moving right, locating each zero crossing
        // inside its interval so the result is continuous in time.
        var rightward: Double = 0
        var previous = vx(-window / 2)
        for i in 1...intervals {
            let next = vx(-window / 2 + Double(i) * step)
            if previous >= 0, next >= 0 {
                rightward += 1
            } else if previous >= 0 || next >= 0 {
                let crossing = previous / (previous - next)
                rightward += previous >= 0 ? crossing : 1 - crossing
            }
            previous = next
        }
        let average = 2 * rightward / Double(intervals) - 1
        return CGFloat(sin(min(1, max(-1, average)) * .pi / 2))
    }

    // MARK: Shared helpers

    /// Cosine ease — zero slope at both ends so phases join without pops.
    static func smooth(_ p: Double) -> Double {
        guard p.isFinite else { return 0 }
        return (1 - cos(.pi * min(1, max(0, p)))) / 2
    }

    /// Eases in over the first `edge` of a step and out over the last.
    static func envelope(_ p: Double, edge: Double) -> Double {
        smooth(p / edge) * smooth((1 - p) / edge)
    }

    private static func cursorGaze(cursor: CGPoint?, center: CGPoint) -> CGVector {
        guard let cursor, cursor.x.isFinite, cursor.y.isFinite,
              center.x.isFinite, center.y.isFinite else { return .zero }
        let dx = (cursor.x - center.x) / 320
        let dy = (cursor.y - center.y) / 320
        return CGVector(dx: min(1, max(-1, dx)), dy: min(1, max(-1, dy)))
    }

    /// Slow blink that never lands exactly on a rest boundary.
    static func blinkOpen(at t: Double, seed: Double) -> CGFloat {
        let cycle = 4.7 + seed * 0.9
        let phase = (t + seed * 2.13).truncatingRemainder(dividingBy: cycle)
        let open = abs(phase - cycle * 0.5) < 0.11 ? abs(phase - cycle * 0.5) / 0.11 : 1
        return CGFloat(max(0, min(1, open)))
    }

    private static func kindSeed(_ kind: PetKind) -> Double {
        kind == .cat ? 0.31 : 0.57
    }

    /// Stable per-mood seeds for the plan dice.
    private static func moodSeed(_ mood: PetMood) -> UInt64 {
        switch mood {
        case .sleepy: return 0x5EE9_1E57
        case .curious: return 0xC021_0050
        case .playful: return 0x91A7_F011
        }
    }
}

/// A connected display reduced to what placement decisions need.
struct PetDisplay: Equatable {
    var id: String
    var visibleFrame: CGRect
}

/// Where a pet should live right now. Pure so screen-geometry edge cases
/// (negative origins, disconnected preferred displays, exclusions) are
/// testable without a real monitor.
enum PetPlacement {
    /// Preferred display wins only when it is connected AND not excluded.
    /// A nil or disconnected preference falls back to the first eligible
    /// display; excluded displays always lose.
    static func destination(
        preferredID: String?, displays: [PetDisplay], excluded: Set<String>
    ) -> PetDisplay? {
        let eligible = displays.filter { display in
            !excluded.contains(display.id)
                && display.visibleFrame.width > 0
                && display.visibleFrame.height > 0
                && display.visibleFrame.minX.isFinite
                && display.visibleFrame.minY.isFinite
        }
        if let preferredID,
           let preferred = eligible.first(where: { $0.id == preferredID }) {
            return preferred
        }
        return eligible.first
    }
}
