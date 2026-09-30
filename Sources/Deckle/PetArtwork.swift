import AppKit
import QuartzCore

/// Layered paper-cut artwork built once from retained shape layers and posed
/// by `PetRig`. Every part is a canvas-sized layer with an explicit pivot, so
/// all paths share one canvas space (y up) and anchor-based rotations work —
/// a zero-bounds shape layer would silently pivot every transform around the
/// canvas corner. Details are clipped to their silhouettes with path booleans
/// at build time; nothing is masked, rasterized, or rebuilt per frame.
enum PetArtwork {
    /// Design canvas for both species; window size = canvas × PetSize.scale.
    static let canvas = CGSize(width: 160, height: 120)
    /// The line the cat's paws rest on, in canvas points.
    static let ground: CGFloat = 9

    // MARK: Layers

    /// A canvas-sized container that rotates and scales about `pivot`.
    static func group(pivot: CGPoint? = nil) -> CALayer {
        let pivot = pivot ?? CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: canvas)
        layer.anchorPoint = CGPoint(x: pivot.x / canvas.width, y: pivot.y / canvas.height)
        layer.position = pivot
        return layer
    }

    static func shape(_ path: CGPath, fill: NSColor?) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.frame = CGRect(origin: .zero, size: canvas)
        layer.path = path
        layer.fillColor = fill?.cgColor
        layer.lineJoin = .round
        layer.lineCap = .round
        return layer
    }

    static func line(_ path: CGPath, color: NSColor, width: CGFloat) -> CAShapeLayer {
        let layer = shape(path, fill: nil)
        layer.strokeColor = color.cgColor
        layer.lineWidth = width
        return layer
    }

    /// One cut piece of paper in its own pivoting group, over a crisp
    /// under-shadow a hair below it — the piece reads as resting on whatever
    /// lies beneath. Details added to the group ride along with the piece.
    static func piece(_ path: CGPath, fill: NSColor, shade: NSColor,
                      pivot: CGPoint? = nil, depth: CGFloat = 1.3) -> CALayer {
        let group = self.group(pivot: pivot)
        if depth > 0 {
            let shadow = shape(path, fill: shade)
            shadow.setAffineTransform(CGAffineTransform(translationX: 0, y: -depth))
            group.addSublayer(shadow)
        }
        group.addSublayer(shape(path, fill: fill))
        return group
    }

    // MARK: Paths

    static func ellipse(_ center: CGPoint, _ width: CGFloat, _ height: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: center.x - width / 2, y: center.y - height / 2,
                                 width: width, height: height), transform: nil)
    }

    /// A tapered paper strip along a smooth Catmull-Rom centreline, with
    /// round ends. `widths` gives the strip width at each point.
    static func ribbon(_ points: [CGPoint], widths: [CGFloat]) -> CGPath {
        guard points.count >= 2, widths.count == points.count else { return CGMutablePath() }
        let perSegment = 14
        let samples = perSegment * (points.count - 1)
        var centre: [CGPoint] = []
        var width: [CGFloat] = []
        for i in 0...samples {
            let u = CGFloat(i) / CGFloat(perSegment)
            let segment = min(points.count - 2, Int(u))
            let f = u - CGFloat(segment)
            let p0 = points[max(0, segment - 1)]
            let p1 = points[segment]
            let p2 = points[segment + 1]
            let p3 = points[min(points.count - 1, segment + 2)]
            centre.append(catmullRom(p0, p1, p2, p3, f))
            width.append(widths[segment] + (widths[segment + 1] - widths[segment]) * f)
        }
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for i in centre.indices {
            let a = centre[max(0, i - 1)]
            let b = centre[min(centre.count - 1, i + 1)]
            let length = max(0.0001, hypot(b.x - a.x, b.y - a.y))
            let normal = CGPoint(x: -(b.y - a.y) / length, y: (b.x - a.x) / length)
            let half = width[i] / 2
            left.append(CGPoint(x: centre[i].x + normal.x * half, y: centre[i].y + normal.y * half))
            right.append(CGPoint(x: centre[i].x - normal.x * half, y: centre[i].y - normal.y * half))
        }
        let strip = CGMutablePath()
        strip.addLines(between: left + right.reversed())
        strip.closeSubpath()
        let startCap = ellipse(centre[0], width[0], width[0])
        let endCap = ellipse(centre[centre.count - 1], width[width.count - 1], width[width.count - 1])
        return strip.union(startCap).union(endCap)
    }

    private static func catmullRom(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint,
                                   _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let t2 = t * t
        let t3 = t2 * t
        func axis(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
            let linear = (c - a) * t
            let quadratic = (2 * a - 5 * b + 4 * c - d) * t2
            let cubic = (3 * b - a - 3 * c + d) * t3
            return 0.5 * (2 * b + linear + quadratic + cubic)
        }
        return CGPoint(x: axis(p0.x, p1.x, p2.x, p3.x), y: axis(p0.y, p1.y, p2.y, p3.y))
    }

    /// A pleated paper fan: wedges radiating from `pivot` between two angles
    /// (degrees, counter-clockwise from +x). `radius` maps 0…1 across the fan
    /// to the outer edge; each wedge's rim bows outward like a folded pleat.
    static func fan(pivot: CGPoint, from start: CGFloat, to end: CGFloat, pleats: Int,
                    radius: (CGFloat) -> CGFloat) -> [CGPath] {
        (0..<pleats).map { index in
            let u0 = CGFloat(index) / CGFloat(pleats)
            let u1 = CGFloat(index + 1) / CGFloat(pleats)
            let a0 = (start + (end - start) * u0) * .pi / 180
            let a1 = (start + (end - start) * u1) * .pi / 180
            let r0 = radius(u0)
            let r1 = radius(u1)
            let mid = (a0 + a1) / 2
            let bow = (r0 + r1) / 2 * 1.08
            let path = CGMutablePath()
            path.move(to: pivot)
            path.addLine(to: CGPoint(x: pivot.x + cos(a0) * r0, y: pivot.y + sin(a0) * r0))
            path.addQuadCurve(to: CGPoint(x: pivot.x + cos(a1) * r1, y: pivot.y + sin(a1) * r1),
                              control: CGPoint(x: pivot.x + cos(mid) * bow, y: pivot.y + sin(mid) * bow))
            path.closeSubpath()
            return path
        }
    }

    /// A pleated fan as one paper piece: shared under-shadow, alternating
    /// tones, and a pale crease down every fold.
    static func fanPiece(_ wedges: [CGPath], tones: (NSColor, NSColor), crease: NSColor,
                         shade: NSColor, pivot: CGPoint, depth: CGFloat = 1.1) -> CALayer {
        let outline = wedges.dropFirst().reduce(wedges.first ?? CGMutablePath()) { $0.union($1) }
        let group = self.group(pivot: pivot)
        let shadow = shape(outline, fill: shade)
        shadow.setAffineTransform(CGAffineTransform(translationX: 0, y: -depth))
        group.addSublayer(shadow)
        let folds = CGMutablePath()
        for (index, wedge) in wedges.enumerated() {
            group.addSublayer(shape(wedge, fill: index.isMultiple(of: 2) ? tones.0 : tones.1))
            if index > 0 {
                // The fold between this pleat and the last one.
                folds.addPath(foldLine(wedge, pivot: pivot))
            }
        }
        group.addSublayer(line(folds, color: crease, width: 0.6))
        return group
    }

    /// The first edge of a wedge from `fan`, pulled back from the pivot so
    /// the fold lines fan out rather than meet in a dark knot.
    private static func foldLine(_ wedge: CGPath, pivot: CGPoint) -> CGPath {
        var tip = pivot
        wedge.applyWithBlock { element in
            if element.pointee.type == .addLineToPoint, tip == pivot {
                tip = element.pointee.points[0]
            }
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: pivot.x + (tip.x - pivot.x) * 0.3, y: pivot.y + (tip.y - pivot.y) * 0.3))
        path.addLine(to: CGPoint(x: pivot.x + (tip.x - pivot.x) * 0.94, y: pivot.y + (tip.y - pivot.y) * 0.94))
        return path
    }

    static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

/// Applies sampled motion frames to retained artwork. The host positions and
/// scales `root` with `place(in:)`; the rig only writes to layers below it,
/// so a pose never undoes the size the host chose. Every write is a
/// transform or opacity change on an existing layer — no per-frame allocation.
struct PetRig {
    let kind: PetKind
    let root: CALayer
    private let pose: CALayer
    private let flip: CALayer
    private let figure: Figure

    private enum Figure {
        case cat(CatFigure)
        case fish(FishFigure)
    }

    init(kind: PetKind) {
        self.kind = kind
        root = PetArtwork.group()
        pose = PetArtwork.group()
        flip = PetArtwork.group()
        root.addSublayer(pose)
        pose.addSublayer(flip)
        switch kind {
        // Overlays (z's, bubbles) rise straight up in screen space: never
        // mirrored with the pet, never tilted with its body.
        case .cat:
            let cat = CatFigure()
            flip.addSublayer(cat.body)
            root.addSublayer(cat.overlay)
            figure = .cat(cat)
        case .fish:
            let fish = FishFigure()
            flip.addSublayer(fish.body)
            root.addSublayer(fish.overlay)
            figure = .fish(fish)
        }
    }

    /// Fits `content` (canvas coordinates; the whole canvas by default) into
    /// `rect` with a uniform scale, centred.
    func place(in rect: CGRect, showing content: CGRect? = nil) {
        let canvas = CGRect(origin: .zero, size: PetArtwork.canvas)
        let content = content.flatMap { $0.isNull || $0.isEmpty ? nil : $0 } ?? canvas
        let scale = min(rect.width / content.width, rect.height / content.height)
        guard scale.isFinite, scale > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.position = CGPoint(x: rect.midX - (content.midX - canvas.midX) * scale,
                                y: rect.midY - (content.midY - canvas.midY) * scale)
        root.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        CATransaction.commit()
    }

    /// The drawn extent of the current pose in canvas coordinates: every
    /// visible shape's bounds mapped through the rig's own transforms. Soft
    /// shadows are excluded — they may feather past the canvas edge.
    func artworkBounds() -> CGRect {
        var extent = CGRect.null
        func visit(_ layer: CALayer) {
            guard !layer.isHidden, layer.opacity > 0.01 else { return }
            if let shape = layer as? CAShapeLayer, let path = shape.path, !path.isEmpty {
                // Map the path itself, not its box: a rotated box's bounds
                // overstate a rotated shape by a wide margin.
                let origin = shape.convert(CGPoint.zero, to: root)
                let unitX = shape.convert(CGPoint(x: 1, y: 0), to: root)
                let unitY = shape.convert(CGPoint(x: 0, y: 1), to: root)
                var toRoot = CGAffineTransform(a: unitX.x - origin.x, b: unitX.y - origin.y,
                                               c: unitY.x - origin.x, d: unitY.y - origin.y,
                                               tx: origin.x, ty: origin.y)
                if let mapped = path.copy(using: &toRoot) {
                    var box = mapped.boundingBoxOfPath
                    if shape.strokeColor != nil {
                        box = box.insetBy(dx: -shape.lineWidth, dy: -shape.lineWidth)
                    }
                    extent = extent.union(box)
                }
            }
            layer.sublayers?.forEach(visit)
        }
        visit(pose)
        return extent
    }

    func apply(_ frame: PetMotionFrame) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let facing = frame.facing.isFinite ? min(1, max(-1, frame.facing)) : 1
        // Mid-turn the cut-out is edge-on; never collapse to a singular transform.
        let width = facing >= 0 ? max(0.03, facing) : min(-0.03, facing)
        flip.setAffineTransform(CGAffineTransform(scaleX: width, y: 1))
        let tilt = frame.rotation.isFinite ? frame.rotation : 0
        // A fish pitched steeply through a loop foreshortens, as if turning
        // into the screen, so its length still fits the canvas.
        let length = kind == .fish ? 1 - 0.2 * abs(sin(tilt)) : 1
        pose.setAffineTransform(CGAffineTransform(rotationAngle: tilt).scaledBy(x: length, y: 1))
        switch figure {
        case .cat(let cat): cat.apply(frame, facing: facing)
        case .fish(let fish): fish.apply(frame, facing: facing)
        }
        CATransaction.commit()
    }
}

private func wave(_ cycles: Double, offset: Double = 0) -> CGFloat {
    CGFloat(sin((cycles + offset) * 2 * .pi))
}

private func finite(_ value: CGFloat) -> CGFloat {
    value.isFinite ? value : 0
}

/// Sum of amount × posture-weight pairs. Posture recipes read as a list, and
/// short typed terms keep the Xcode 15 type checker fast on the release runner.
private func weigh(_ terms: (CGFloat, CGFloat)...) -> CGFloat {
    terms.reduce(0) { $0 + $1.0 * $1.1 }
}

private func rotate(_ layer: CALayer, _ angle: CGFloat, dx: CGFloat = 0, dy: CGFloat = 0,
                    sx: CGFloat = 1, sy: CGFloat = 1) {
    layer.setAffineTransform(CGAffineTransform(translationX: finite(dx), y: finite(dy))
        .rotated(by: finite(angle))
        .scaledBy(x: finite(sx) == 0 ? 1 : sx, y: finite(sy) == 0 ? 1 : sy))
}

// MARK: - Miso, the paper cat

private final class CatFigure {
    let body: CALayer
    /// Unflipped extras that must never mirror (the sleeping z's).
    let overlay: CALayer

    private let groundShadow: CALayer
    private let torso: CALayer
    /// Chest, shoulders, and front legs: bends up at the waist to sit.
    private let front: CALayer
    private let chest: CALayer
    private let haunch: CALayer
    private let head: CALayer
    private let earNear: CALayer
    private let earFar: CALayer
    private let look: CALayer
    private let eyes: [CALayer]
    private let closedEyes: CALayer
    private let yawn: CALayer
    private let tongue: CALayer
    private let tail: CALayer
    private let tailTip: CALayer
    /// Far hind, far front, near hind, near front.
    private let legs: [CALayer]
    private let snores: [CALayer]

    private static let hip = CGPoint(x: 52, y: 26)
    private static let waist = CGPoint(x: 76, y: 25)
    private static let neck = CGPoint(x: 106, y: 56)
    private static let tailRoot = CGPoint(x: 40, y: 50)
    private static let tailJoint = CGPoint(x: 22, y: 70)
    private static let legRoots = [CGPoint(x: 47, y: 36), CGPoint(x: 95, y: 36),
                                   CGPoint(x: 56, y: 35), CGPoint(x: 104, y: 35)]
    private static let snoreOrigin = CGPoint(x: 132, y: 72)

    init() {
        let a = PetArtwork.self
        let ginger = a.color(0.918, 0.608, 0.341)
        let gingerShade = a.color(0.816, 0.490, 0.251)
        let stripe = a.color(0.776, 0.431, 0.212)
        let cream = a.color(0.980, 0.925, 0.835)
        let creamShade = a.color(0.902, 0.824, 0.706)
        let ink = a.color(0.165, 0.129, 0.110)
        let pink = a.color(0.925, 0.565, 0.529)
        let blush = a.color(0.957, 0.522, 0.451, 0.42)
        let shade = a.color(0.310, 0.161, 0.071, 0.30)
        let ground = PetArtwork.ground

        body = a.group()
        overlay = a.group()

        // Soft contact shadow — a blurred ellipse drawn from its path alone,
        // so the blur never depends on animated content.
        groundShadow = a.group(pivot: CGPoint(x: 76, y: ground))
        let blob = CALayer()
        blob.frame = CGRect(origin: .zero, size: PetArtwork.canvas)
        blob.shadowPath = a.ellipse(CGPoint(x: 76, y: ground), 84, 7)
        blob.shadowColor = NSColor.black.cgColor
        blob.shadowOpacity = 0.26
        blob.shadowRadius = 2.6
        blob.shadowOffset = .zero
        groundShadow.addSublayer(blob)

        torso = a.group(pivot: Self.hip)
        front = a.group(pivot: Self.waist)

        // Tail: two jointed strips so it can wave, with tabby rings.
        let tailBase = a.ribbon([Self.tailRoot, CGPoint(x: 30, y: 56), Self.tailJoint], widths: [8.5, 7.5, 7])
        let tailEnd = a.ribbon([Self.tailJoint, CGPoint(x: 18, y: 84), CGPoint(x: 27, y: 95)],
                               widths: [7, 6.4, 5.4])
        tail = a.piece(tailBase, fill: ginger, shade: shade, pivot: Self.tailRoot)
        tailTip = a.piece(tailEnd, fill: ginger, shade: shade, pivot: Self.tailJoint)
        let rings = CGMutablePath()
        rings.addPath(a.ribbon([CGPoint(x: 13, y: 78), CGPoint(x: 25, y: 80)], widths: [2.4, 2.4]))
        rings.addPath(a.ribbon([CGPoint(x: 14, y: 89), CGPoint(x: 25, y: 85)], widths: [2.4, 2.4]))
        tailTip.addSublayer(a.shape(tailEnd.intersection(rings), fill: stripe))
        let baseRing = a.ribbon([CGPoint(x: 22, y: 58), CGPoint(x: 32, y: 66)], widths: [2.4, 2.4])
        tail.addSublayer(a.shape(tailBase.intersection(baseRing), fill: stripe))
        tail.addSublayer(tailTip)

        // Legs: tapered strips with mitten paws, far pair a shade darker.
        // Hidden tops stay short so folded legs never poke out behind the
        // rump; the near front leg sits over the chest, its crease the elbow.
        var legs: [CALayer] = []
        for (index, root) in Self.legRoots.enumerated() {
            let far = index < 2
            let hind = index % 2 == 0
            let overChest = index == 3
            let knee = hind ? CGPoint(x: root.x - 2.5, y: root.y - 12) : CGPoint(x: root.x, y: root.y - 12)
            let foot = CGPoint(x: root.x + (hind ? 0.5 : 1), y: ground + 4)
            let top = CGPoint(x: root.x, y: root.y + (hind ? 6 : (overChest ? 8 : 12)))
            let strip = a.ribbon([top, knee, foot],
                                 widths: hind ? [12, 9, 8] : (overChest ? [11, 8.5, 8] : [10, 8.5, 8]))
            let leg = a.piece(strip, fill: far ? gingerShade : ginger, shade: shade, pivot: root)
            if overChest {
                let elbow = CGMutablePath()
                elbow.move(to: CGPoint(x: root.x - 3.2, y: root.y + 9))
                elbow.addQuadCurve(to: CGPoint(x: root.x - 4.2, y: root.y - 9),
                                   control: CGPoint(x: root.x - 6.4, y: root.y))
                leg.addSublayer(a.line(elbow, color: shade, width: 0.9))
            }
            let paw = a.ellipse(CGPoint(x: foot.x + 1.5, y: ground + 3), 11, 6.5)
            leg.addSublayer(a.shape(paw, fill: far ? creamShade : cream))
            let toes = CGMutablePath()
            toes.move(to: CGPoint(x: foot.x + 2.6, y: ground + 0.8))
            toes.addLine(to: CGPoint(x: foot.x + 2.6, y: ground + 3))
            toes.move(to: CGPoint(x: foot.x + 5.2, y: ground + 1.2))
            toes.addLine(to: CGPoint(x: foot.x + 5.2, y: ground + 3.1))
            leg.addSublayer(a.line(toes, color: shade, width: 0.6))
            legs.append(leg)
        }
        self.legs = legs

        // Chest and shoulders: the front half of the loaf, with a fluffy bib.
        let chestPath = CGMutablePath()
        chestPath.move(to: CGPoint(x: 52, y: 58))
        chestPath.addCurve(to: CGPoint(x: 97, y: 59), control1: CGPoint(x: 66, y: 62), control2: CGPoint(x: 84, y: 57))
        chestPath.addCurve(to: CGPoint(x: 117, y: 43), control1: CGPoint(x: 110, y: 61), control2: CGPoint(x: 118, y: 52))
        chestPath.addCurve(to: CGPoint(x: 105, y: 25), control1: CGPoint(x: 116, y: 33), control2: CGPoint(x: 112, y: 26))
        chestPath.addCurve(to: CGPoint(x: 72, y: 23), control1: CGPoint(x: 92, y: 22), control2: CGPoint(x: 80, y: 22))
        chestPath.addCurve(to: CGPoint(x: 52, y: 58), control1: CGPoint(x: 62, y: 26), control2: CGPoint(x: 50, y: 46))
        chestPath.closeSubpath()
        chest = a.piece(chestPath, fill: ginger, shade: shade, pivot: CGPoint(x: 90, y: 22))
        let chestStripes = CGMutablePath()
        for (x, lean) in [(CGFloat(80), CGFloat(-2)), (91, -1.5)] {
            chestStripes.addPath(a.ribbon([CGPoint(x: x, y: 66), CGPoint(x: x + lean, y: 54),
                                           CGPoint(x: x + lean * 1.8, y: 47)], widths: [5.5, 3.6, 1.2]))
        }
        chest.addSublayer(a.shape(chestPath.intersection(chestStripes), fill: stripe))
        let bib = CGMutablePath()
        bib.move(to: CGPoint(x: 108, y: 60))
        bib.addQuadCurve(to: CGPoint(x: 103, y: 50), control: CGPoint(x: 102, y: 57))
        bib.addQuadCurve(to: CGPoint(x: 102.5, y: 40), control: CGPoint(x: 99.5, y: 45))
        bib.addQuadCurve(to: CGPoint(x: 106, y: 29), control: CGPoint(x: 100.5, y: 33))
        bib.addQuadCurve(to: CGPoint(x: 111, y: 22), control: CGPoint(x: 106, y: 24))
        bib.addLine(to: CGPoint(x: 126, y: 22))
        bib.addLine(to: CGPoint(x: 126, y: 60))
        bib.closeSubpath()
        let bibShape = chestPath.intersection(bib)
        let bibShadow = a.shape(bibShape, fill: shade)
        bibShadow.setAffineTransform(CGAffineTransform(translationX: -0.8, y: -0.5))
        chest.addSublayer(bibShadow)
        chest.addSublayer(a.shape(bibShape, fill: cream))

        // Haunch: the rump and thigh, cut as its own piece so its curve reads
        // as the hind leg in every posture and hides the waist joint.
        let haunchPath = CGMutablePath()
        haunchPath.move(to: CGPoint(x: 52, y: 23))
        haunchPath.addCurve(to: CGPoint(x: 36, y: 41), control1: CGPoint(x: 42, y: 23), control2: CGPoint(x: 36, y: 31))
        haunchPath.addCurve(to: CGPoint(x: 56, y: 60.5), control1: CGPoint(x: 36, y: 54), control2: CGPoint(x: 46, y: 61))
        haunchPath.addCurve(to: CGPoint(x: 68, y: 55), control1: CGPoint(x: 61, y: 60), control2: CGPoint(x: 65, y: 58))
        haunchPath.addCurve(to: CGPoint(x: 81, y: 40), control1: CGPoint(x: 75, y: 53), control2: CGPoint(x: 81, y: 47))
        haunchPath.addCurve(to: CGPoint(x: 70, y: 22.5), control1: CGPoint(x: 80, y: 31), control2: CGPoint(x: 76, y: 24))
        haunchPath.closeSubpath()
        haunch = a.piece(haunchPath, fill: ginger, shade: shade, pivot: CGPoint(x: 58, y: 23), depth: 0.8)
        let haunchStripes = CGMutablePath()
        for (x, lean) in [(CGFloat(47), CGFloat(-3)), (58, -2.5)] {
            haunchStripes.addPath(a.ribbon([CGPoint(x: x, y: 67), CGPoint(x: x + lean, y: 55),
                                            CGPoint(x: x + lean * 1.8, y: 48)], widths: [5.5, 3.4, 1.1]))
        }
        haunch.addSublayer(a.shape(haunchPath.intersection(haunchStripes), fill: stripe))

        // Head, drawn in three-quarter view so both eyes read at small sizes.
        head = a.group(pivot: Self.neck)
        let skull = CGMutablePath()
        skull.move(to: CGPoint(x: 103, y: 71))
        skull.addCurve(to: CGPoint(x: 120, y: 88), control1: CGPoint(x: 103, y: 81), control2: CGPoint(x: 110, y: 88))
        skull.addCurve(to: CGPoint(x: 137, y: 72), control1: CGPoint(x: 130, y: 88), control2: CGPoint(x: 137, y: 81))
        skull.addCurve(to: CGPoint(x: 133, y: 59), control1: CGPoint(x: 137, y: 66), control2: CGPoint(x: 136, y: 62))
        skull.addCurve(to: CGPoint(x: 120, y: 54), control1: CGPoint(x: 129, y: 55), control2: CGPoint(x: 124, y: 54))
        skull.addCurve(to: CGPoint(x: 107, y: 59), control1: CGPoint(x: 116, y: 54), control2: CGPoint(x: 110, y: 55))
        skull.addCurve(to: CGPoint(x: 103, y: 71), control1: CGPoint(x: 104, y: 62), control2: CGPoint(x: 103, y: 66))
        skull.closeSubpath()

        earFar = a.piece(Self.ear(base: CGPoint(x: 105, y: 79), tip: CGPoint(x: 104, y: 99),
                                  end: CGPoint(x: 117, y: 86)),
                         fill: gingerShade, shade: shade, pivot: CGPoint(x: 111, y: 82))
        earNear = a.piece(Self.ear(base: CGPoint(x: 124, y: 87), tip: CGPoint(x: 137, y: 99),
                                   end: CGPoint(x: 137, y: 77)),
                          fill: ginger, shade: shade, pivot: CGPoint(x: 131, y: 82))
        earNear.addSublayer(a.shape(Self.ear(base: CGPoint(x: 127.5, y: 86), tip: CGPoint(x: 135.5, y: 95),
                                             end: CGPoint(x: 134.5, y: 81)), fill: pink))
        head.addSublayer(earFar)

        let face = a.piece(skull, fill: ginger, shade: shade, pivot: Self.neck)
        let brow = CGMutablePath()
        for (x, length) in [(CGFloat(116), CGFloat(7)), (120.5, 9), (125, 7)] {
            brow.addPath(a.ribbon([CGPoint(x: x, y: 90), CGPoint(x: x + (x - 120.5) * 0.15, y: 90 - length)],
                                  widths: [2.6, 0.8]))
        }
        face.addSublayer(a.shape(skull.intersection(brow), fill: stripe))
        let cheeks = CGMutablePath()
        cheeks.addPath(a.ellipse(CGPoint(x: 111, y: 64), 7, 4))
        cheeks.addPath(a.ellipse(CGPoint(x: 132.5, y: 64), 6, 4))
        face.addSublayer(a.shape(skull.intersection(cheeks), fill: blush))
        let muzzle = skull.intersection(a.ellipse(CGPoint(x: 122.5, y: 61.5), 16, 10))
        face.addSublayer(a.shape(muzzle, fill: cream))
        head.addSublayer(earNear)
        head.addSublayer(face)

        // Eyes: ink ovals with a catchlight, blinking about their own centres
        // and shifting together toward the cursor.
        look = a.group()
        var eyes: [CALayer] = []
        for center in [CGPoint(x: 114.5, y: 71.5), CGPoint(x: 128, y: 71.5)] {
            let eye = a.group(pivot: center)
            eye.addSublayer(a.shape(a.ellipse(center, 5.4, 7), fill: ink))
            eye.addSublayer(a.shape(a.ellipse(CGPoint(x: center.x + 1.1, y: center.y + 1.6), 2, 2),
                                    fill: .white))
            look.addSublayer(eye)
            eyes.append(eye)
        }
        self.eyes = eyes
        let lids = CGMutablePath()
        for x in [CGFloat(114.5), 128] {
            lids.move(to: CGPoint(x: x - 3.4, y: 71.5))
            lids.addQuadCurve(to: CGPoint(x: x + 3.4, y: 71.5), control: CGPoint(x: x, y: 67.8))
        }
        closedEyes = a.line(lids, color: ink, width: 1.3)
        head.addSublayer(look)
        head.addSublayer(closedEyes)

        let nose = CGMutablePath()
        nose.move(to: CGPoint(x: 120.2, y: 66))
        nose.addQuadCurve(to: CGPoint(x: 125.8, y: 66), control: CGPoint(x: 123, y: 67.4))
        nose.addQuadCurve(to: CGPoint(x: 123, y: 63.2), control: CGPoint(x: 125.4, y: 64.2))
        nose.addQuadCurve(to: CGPoint(x: 120.2, y: 66), control: CGPoint(x: 120.6, y: 64.2))
        nose.closeSubpath()
        head.addSublayer(a.shape(nose, fill: pink))
        yawn = a.group(pivot: CGPoint(x: 123, y: 59.5))
        yawn.addSublayer(a.shape(a.ellipse(CGPoint(x: 123, y: 59.3), 5, 5.8), fill: a.color(0.62, 0.25, 0.24)))
        yawn.addSublayer(a.shape(a.ellipse(CGPoint(x: 123, y: 57.6), 3, 2), fill: pink))
        head.addSublayer(yawn)
        tongue = a.group(pivot: CGPoint(x: 123, y: 60))
        tongue.addSublayer(a.shape(a.ellipse(CGPoint(x: 123.4, y: 58.2), 3.4, 4.2), fill: pink))
        tongue.opacity = 0
        head.addSublayer(tongue)
        let mouth = CGMutablePath()
        mouth.move(to: CGPoint(x: 123, y: 63.3))
        mouth.addLine(to: CGPoint(x: 123, y: 61.6))
        mouth.move(to: CGPoint(x: 119.8, y: 61.8))
        mouth.addQuadCurve(to: CGPoint(x: 123, y: 61.6), control: CGPoint(x: 121.4, y: 60.2))
        mouth.addQuadCurve(to: CGPoint(x: 126.2, y: 61.8), control: CGPoint(x: 124.6, y: 60.2))
        head.addSublayer(a.line(mouth, color: ink.withAlphaComponent(0.75), width: 0.8))
        let whiskers = CGMutablePath()
        for (dy, reach) in [(CGFloat(1.6), CGFloat(14)), (-1.4, 13)] {
            whiskers.move(to: CGPoint(x: 131, y: 62 + dy * 0.4))
            whiskers.addQuadCurve(to: CGPoint(x: 131 + reach, y: 62 + dy * 2.2),
                                  control: CGPoint(x: 137, y: 62 + dy * 1.4))
            whiskers.move(to: CGPoint(x: 114.5, y: 62 + dy * 0.4))
            whiskers.addQuadCurve(to: CGPoint(x: 114.5 - reach * 0.8, y: 62 + dy * 2),
                                  control: CGPoint(x: 109, y: 62 + dy * 1.4))
        }
        head.addSublayer(a.line(whiskers, color: ink.withAlphaComponent(0.42), width: 0.6))

        // Sleep z's, stroked like hand-cut letters, rising from the head.
        var snores: [CALayer] = []
        for size in [CGFloat(5), 6.5, 8] {
            let z = CGMutablePath()
            z.move(to: CGPoint(x: -size / 2, y: size / 2))
            z.addLine(to: CGPoint(x: size / 2, y: size / 2))
            z.addLine(to: CGPoint(x: -size / 2, y: -size / 2))
            z.addLine(to: CGPoint(x: size / 2, y: -size / 2))
            let letter = a.group(pivot: .zero)
            letter.addSublayer(a.line(z, color: a.color(0.30, 0.36, 0.52, 0.85), width: 1.4))
            letter.opacity = 0
            overlay.addSublayer(letter)
            snores.append(letter)
        }
        self.snores = snores

        // Back to front: tail, hind legs, the chest with its far front leg,
        // the haunch over the waist joint, the head, then the near front leg
        // — last, so a grooming paw comes up in front of the face. It rides
        // the waist bend by computation, like the head.
        front.addSublayer(legs[1])
        front.addSublayer(chest)
        torso.addSublayer(tail)
        torso.addSublayer(legs[0])
        torso.addSublayer(legs[2])
        torso.addSublayer(front)
        torso.addSublayer(haunch)
        torso.addSublayer(head)
        torso.addSublayer(legs[3])
        body.addSublayer(groundShadow)
        body.addSublayer(torso)
    }

    /// An ear with a softly rounded tip: base → tip → end, closed along the skull.
    private static func ear(base: CGPoint, tip: CGPoint, end: CGPoint) -> CGPath {
        let path = CGMutablePath()
        let inA = CGPoint(x: tip.x + (base.x - tip.x) * 0.16, y: tip.y + (base.y - tip.y) * 0.16)
        let inB = CGPoint(x: tip.x + (end.x - tip.x) * 0.16, y: tip.y + (end.y - tip.y) * 0.16)
        path.move(to: base)
        path.addQuadCurve(to: inA, control: CGPoint(x: (base.x + inA.x) / 2 - 0.8, y: (base.y + inA.y) / 2))
        path.addQuadCurve(to: inB, control: tip)
        path.addQuadCurve(to: end, control: CGPoint(x: (inB.x + end.x) / 2 + 0.8, y: (inB.y + end.y) / 2))
        path.closeSubpath()
        return path
    }

    func apply(_ f: PetMotionFrame, facing: CGFloat) {
        let sit = f.pose.sit
        let lie = f.pose.lie
        let stretch = f.pose.stretch
        let crouch = f.pose.crouch
        let leap = f.pose.leap
        let amp = CGFloat(f.limbAmplitude)
        let awake = 1 - lie
        let side: CGFloat = facing >= 0 ? 1 : -1
        let forwardGaze = finite(f.gaze) * side
        let lift = finite(f.gazeLift)

        // Torso: settles onto the rump to sit, loafs down, and crouches.
        let stride = CGFloat(f.limbPhase)
        let bob = abs(sin(stride * 2 * .pi)) * 0.9 * amp
        let wiggle = wave(f.clock * 3.1) * 0.035 * crouch
        let drop = weigh((11, sit), (14, lie), (6, crouch)) - bob
        let gallop = f.pose.gallop
        let rock = wave(f.limbPhase) * 0.07 * gallop * amp
        let torsoAngle = weigh((0.1, sit), (-0.12, stretch), (-0.02, crouch)) + wiggle + rock
        rotate(torso, torsoAngle, dy: -drop)

        // Front half bends at the waist: up to sit, down into a play bow.
        let gait = wave(f.limbPhase, offset: 0.25) * 0.05 * gallop * amp
        let bend = weigh((0.86, sit), (-0.22, stretch), (-0.04, lie), (-0.04, crouch), (0.06, leap)) + gait
        let shift = CGPoint(x: 5 * sit, y: 0)
        rotate(front, bend, dx: shift.x, dy: shift.y)
        let breath = 0.012 + 0.022 * lie
        chest.setAffineTransform(CGAffineTransform(scaleX: 1, y: 1 + breath * wave(f.clock / 3.4)))
        haunch.setAffineTransform(CGAffineTransform(scaleX: 1, y: 1 + breath * 0.6 * wave(f.clock / 3.4)))

        // Head rides on the chest (computed, so it can sit above the haunch in
        // z-order), levels itself, and tips toward the cursor.
        let lever = CGPoint(x: Self.neck.x - Self.waist.x, y: Self.neck.y - Self.waist.y)
        let turned = CGPoint(x: lever.x * cos(bend) - lever.y * sin(bend),
                             y: lever.x * sin(bend) + lever.y * cos(bend))
        let neckAt = CGPoint(x: Self.waist.x + turned.x + shift.x, y: Self.waist.y + turned.y + shift.y)
        let tilt = (0.12 * lift * (0.4 + sit) + 0.05 * forwardGaze) * awake
        let groom = f.pose.groom
        let lick = wave(f.clock * 2.2)
        let lookBack = f.pose.lookBack
        let headAngle = bend + tilt + weigh((-0.95, sit), (0.42, stretch), (-0.12, lie), (0.05, crouch),
                                            (-0.3 + 0.06 * lick, groom), (0.1, lookBack))
        // Looking back mirrors the head about the neck, turning edge-on midway.
        let turn = cos(.pi * lookBack)
        let nod = wave(stride, offset: 0.1) * 0.5 * amp
        rotate(head, headAngle,
               dx: neckAt.x - Self.neck.x + 2 * stretch,
               dy: neckAt.y - Self.neck.y + weigh((-4, lie), (-2, crouch)) + nod,
               sx: turn >= 0 ? max(0.03, turn) : min(-0.03, turn))
        look.setAffineTransform(CGAffineTransform(translationX: 1.5 * forwardGaze, y: 1.1 * lift))
        let open = max(0, min(1, f.eyeOpen))
        for eye in eyes {
            eye.setAffineTransform(CGAffineTransform(scaleX: 1, y: max(0.08, open)))
            eye.opacity = Float(min(1, open * 4))
        }
        closedEyes.opacity = Float(1 - min(1, open * 4))
        yawn.opacity = Float(stretch)
        yawn.setAffineTransform(CGAffineTransform(scaleX: max(0.05, stretch), y: max(0.05, stretch)))
        tongue.opacity = Float(groom * max(0, lick))

        // Ears flatten into a pounce, relax in sleep, and twitch now and then.
        let twitchPhase = (f.clock + 1.3).truncatingRemainder(dividingBy: 6.7)
        let twitch = CGFloat(twitchPhase < 0.36 ? sin(twitchPhase / 0.36 * .pi) : 0) * awake
        rotate(earNear, weigh((0.35, crouch), (0.12, lie), (0.25, gallop), (-0.22, twitch)))
        rotate(earFar, weigh((0.3, crouch), (0.1, lie), (0.2, gallop)))

        // Legs: a lateral-sequence walk, then posture-specific folds. Front
        // legs cancel the waist bend so they stay planted when sitting.
        // A sprint blends the walk into a bound: fronts together, hinds together.
        let walkOffsets: [Double] = [0, 0.25, 0.5, 0.75]
        let boundOffsets: [Double] = [0, 0.5, 0.08, 0.58]
        let knead = f.pose.knead
        for (index, leg) in legs.enumerated() {
            let hind = index % 2 == 0
            let offset = walkOffsets[index] + (boundOffsets[index] - walkOffsets[index]) * Double(gallop)
            let cycle = f.limbPhase + offset
            let swing = wave(cycle) * (0.42 + 0.2 * gallop) * amp
            let step = max(0, CGFloat(cos(cycle * 2 * .pi))) * 2.4 * amp
            var angle = swing
            // Positive reach lengthens the leg (paw further from the joint).
            var reach: CGFloat = -step
            if hind {
                angle += weigh((1.25, sit), (1.25, lie), (0.08, stretch), (-0.1, crouch), (-0.8, leap))
                reach += weigh((1, sit), (2, lie), (-1, stretch), (-6, crouch))
            } else {
                angle += weigh((0.08, sit), (1.35, lie), (1.15, stretch), (0.15, crouch), (0.7, leap))
                angle -= bend + torsoAngle
                reach += weigh((1, sit), (-6, lie), (-5, stretch), (-6, crouch))
                // Kneading: the front paws tread in turn.
                reach += wave(f.clock * 1.3, offset: index == 1 ? 0 : 0.5) * 2.5 * knead
                if index == 3 {
                    // Grooming: the near paw comes up to the mouth for licks.
                    angle += (2.35 + 0.12 * lick) * groom
                    reach -= 9 * groom
                }
            }
            var pose = CGAffineTransform(rotationAngle: finite(angle)).translatedBy(x: 0, y: -finite(reach))
            if index == 3 {
                // Carry the near front leg through the waist bend it sits outside of.
                let root = Self.legRoots[3]
                let arm = CGPoint(x: root.x - Self.waist.x, y: root.y - Self.waist.y)
                let swung = CGPoint(x: arm.x * cos(bend) - arm.y * sin(bend),
                                    y: arm.x * sin(bend) + arm.y * cos(bend))
                let carried = CGPoint(x: Self.waist.x + swung.x + shift.x, y: Self.waist.y + swung.y + shift.y)
                pose = pose.concatenating(CGAffineTransform(rotationAngle: finite(bend)))
                    .concatenating(CGAffineTransform(translationX: finite(carried.x - root.x),
                                                     y: finite(carried.y - root.y)))
            }
            leg.setAffineTransform(pose)
        }

        // Tail: a delayed two-joint wave, wrapped low when sitting or asleep,
        // raised high in a stretch.
        let sway = 0.25 + 0.75 * awake
        let swish = wave(f.clock * 2.3) * 0.35 * crouch
        let tailSway = wave(f.tailPhase) * 0.1 * sway
        rotate(tail, tailSway + weigh((0.8, sit), (0.9, lie), (-0.3, stretch), (0.12, crouch), (-0.3, leap)))
        let tipSway = wave(f.tailPhase, offset: -0.18) * 0.24 * sway + swish
        rotate(tailTip, tipSway + weigh((-1.3, sit), (-0.7, lie), (0.25, stretch), (0.2, leap)))

        let spread = 1 + weigh((-0.22, sit), (0.06, lie), (-0.45, leap))
        rotate(groundShadow, 0, dx: -6 * sit, sx: max(0.3, spread))
        groundShadow.opacity = Float(max(0.25, 1 - 0.7 * leap))

        // Z's drift up and away from the sleeping head, in screen space.
        for (index, letter) in snores.enumerated() {
            let t = (f.clock / 2.6 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            let rise = CGFloat(t)
            let fade = CGFloat(sin(t * .pi))
            let x = 80 + (Self.snoreOrigin.x - 80 + 4 + rise * 14) * facing
            let y = Self.snoreOrigin.y + rise * 32
            letter.position = CGPoint(x: x, y: y)
            letter.setAffineTransform(CGAffineTransform(scaleX: 0.6 + 0.5 * rise, y: 0.6 + 0.5 * rise))
            letter.opacity = Float(max(0, lie - 0.5) * 2 * fade * (1 - min(1, f.eyeOpen * 4)))
        }
    }
}

// MARK: - Tide, the paper fish

private final class FishFigure {
    let body: CALayer
    /// Unflipped, untilted bubbles.
    let overlay: CALayer

    private let swimmer: CALayer
    private let tail: CALayer
    private let dorsal: CALayer
    private let pelvic: CALayer
    private let pectoral: CALayer
    private let eye: CALayer
    private let pupil: CALayer
    private let closedEye: CALayer
    private let mouthOpen: CALayer
    private let bubbles: [CALayer]

    private static let peduncle = CGPoint(x: 48, y: 60)
    private static let mouth = CGPoint(x: 142, y: 60)

    init() {
        let a = PetArtwork.self
        let blue = a.color(0.204, 0.475, 0.667)
        let blueDeep = a.color(0.141, 0.353, 0.522)
        let blueLight = a.color(0.600, 0.808, 0.906)
        let belly = a.color(0.898, 0.953, 0.961)
        let coral = a.color(0.933, 0.506, 0.369)
        let coralLight = a.color(0.976, 0.706, 0.573)
        let cream = a.color(0.992, 0.969, 0.925)
        let ink = a.color(0.090, 0.129, 0.180)
        let shade = a.color(0.039, 0.141, 0.227, 0.30)

        body = a.group()
        swimmer = a.group(pivot: CGPoint(x: 94, y: 60))

        let outline = CGMutablePath()
        outline.move(to: CGPoint(x: 48, y: 66))
        outline.addCurve(to: CGPoint(x: 98, y: 90), control1: CGPoint(x: 62, y: 80), control2: CGPoint(x: 78, y: 90))
        outline.addCurve(to: CGPoint(x: 142, y: 61), control1: CGPoint(x: 123, y: 90), control2: CGPoint(x: 142, y: 77))
        outline.addCurve(to: CGPoint(x: 100, y: 31), control1: CGPoint(x: 142, y: 45), control2: CGPoint(x: 123, y: 31))
        outline.addCurve(to: CGPoint(x: 48, y: 54), control1: CGPoint(x: 78, y: 31), control2: CGPoint(x: 62, y: 41))
        outline.closeSubpath()

        // The whole fish hovers a few millimetres off the screen: a soft
        // shadow of the body, drawn from its path so the blur is cheap.
        let hover = CALayer()
        hover.frame = CGRect(origin: .zero, size: PetArtwork.canvas)
        hover.shadowPath = outline
        hover.shadowColor = NSColor.black.cgColor
        hover.shadowOpacity = 0.16
        hover.shadowRadius = 4.5
        hover.shadowOffset = CGSize(width: 0, height: -9)
        swimmer.addSublayer(hover)

        // Fins are pleated fans, so every flutter reads as folded paper.
        tail = a.fanPiece(
            a.fan(pivot: Self.peduncle, from: 146, to: 214, pleats: 6) { u in
                34 - 8 * CGFloat(pow(Double(1 - abs(u * 2 - 1)), 1.6))
            },
            tones: (coral, coralLight), crease: cream.withAlphaComponent(0.7),
            shade: shade, pivot: Self.peduncle)
        dorsal = a.fanPiece(
            a.fan(pivot: CGPoint(x: 96, y: 64), from: 58, to: 142, pleats: 8) { u in 30 + 8 * u },
            tones: (coral, coralLight), crease: cream.withAlphaComponent(0.7),
            shade: shade, pivot: CGPoint(x: 96, y: 84))
        pelvic = a.fanPiece(
            a.fan(pivot: CGPoint(x: 92, y: 40), from: 226, to: 282, pleats: 3) { _ in 17 },
            tones: (coralLight, coral), crease: cream.withAlphaComponent(0.7),
            shade: shade, pivot: CGPoint(x: 92, y: 36))
        pectoral = a.fanPiece(
            a.fan(pivot: CGPoint(x: 110, y: 52), from: 192, to: 250, pleats: 5) { u in 19 - 4 * u },
            tones: (cream, coralLight), crease: coral.withAlphaComponent(0.55),
            shade: shade, pivot: CGPoint(x: 110, y: 52), depth: 0.9)

        let hull = a.piece(outline, fill: blue, shade: shade, pivot: CGPoint(x: 94, y: 60))
        // Scales: overlapping scallops, clipped above the belly and behind the gill.
        let scales = CGMutablePath()
        for (row, y) in [CGFloat(80), 72, 64, 56].enumerated() {
            for column in 0..<7 {
                let x = 62 + CGFloat(column) * 8.5 + (row.isMultiple(of: 2) ? 0 : 4.25)
                let arc = CGMutablePath()
                arc.addArc(center: CGPoint(x: x, y: y), radius: 4.6,
                           startAngle: .pi * 0.5, endAngle: .pi * 1.5, clockwise: false)
                scales.addPath(arc.copy(strokingWithWidth: 1.1, lineCap: .round, lineJoin: .round, miterLimit: 1))
            }
        }
        let scaleZone = CGMutablePath()
        scaleZone.addRect(CGRect(x: 40, y: 50, width: 72, height: 48))
        hull.addSublayer(a.shape(outline.intersection(scaleZone).intersection(scales),
                                 fill: blueLight.withAlphaComponent(0.55)))
        // Belly: a pale panel with a gently waved cut along its top.
        let bellyCut = CGMutablePath()
        bellyCut.move(to: CGPoint(x: 40, y: 50))
        bellyCut.addCurve(to: CGPoint(x: 90, y: 45), control1: CGPoint(x: 58, y: 44), control2: CGPoint(x: 74, y: 49))
        bellyCut.addCurve(to: CGPoint(x: 146, y: 50), control1: CGPoint(x: 108, y: 41), control2: CGPoint(x: 128, y: 53))
        bellyCut.addLine(to: CGPoint(x: 146, y: 20))
        bellyCut.addLine(to: CGPoint(x: 40, y: 20))
        bellyCut.closeSubpath()
        let bellyShape = outline.intersection(bellyCut)
        let bellyShadow = a.shape(bellyShape, fill: shade)
        bellyShadow.setAffineTransform(CGAffineTransform(translationX: 0, y: 0.9))
        hull.addSublayer(bellyShadow)
        hull.addSublayer(a.shape(bellyShape, fill: belly))
        // Gill fold: a dark crease with a pale edge beside it.
        let gill = CGMutablePath()
        gill.move(to: CGPoint(x: 114, y: 80))
        gill.addQuadCurve(to: CGPoint(x: 114, y: 44), control: CGPoint(x: 105, y: 62))
        hull.addSublayer(a.line(gill, color: blueDeep, width: 1.6))
        let gillEdge = CGMutablePath()
        gillEdge.move(to: CGPoint(x: 116, y: 79))
        gillEdge.addQuadCurve(to: CGPoint(x: 116, y: 45), control: CGPoint(x: 107.5, y: 62))
        hull.addSublayer(a.line(gillEdge, color: blueLight.withAlphaComponent(0.7), width: 0.8))
        hull.addSublayer(a.shape(outline.intersection(a.ellipse(CGPoint(x: 126, y: 53), 9, 5)),
                                 fill: coral.withAlphaComponent(0.55)))
        let smile = CGMutablePath()
        smile.move(to: CGPoint(x: 134.5, y: 55.5))
        smile.addQuadCurve(to: CGPoint(x: 140.5, y: 57), control: CGPoint(x: 137.5, y: 53.4))
        hull.addSublayer(a.line(smile, color: ink.withAlphaComponent(0.7), width: 1))
        // A little "o" for nibbling, opened by scale so it never pops.
        mouthOpen = a.group(pivot: CGPoint(x: 138.6, y: 57.2))
        mouthOpen.addSublayer(a.shape(a.ellipse(CGPoint(x: 138.6, y: 57.2), 5, 5.6), fill: ink))
        mouthOpen.addSublayer(a.shape(a.ellipse(CGPoint(x: 138.6, y: 56), 2.8, 2), fill: coral))
        mouthOpen.opacity = 0

        // A big friendly eye with a catchlight; the pupil tracks the cursor.
        let eyeCenter = CGPoint(x: 126, y: 67)
        eye = a.group(pivot: eyeCenter)
        let white = a.shape(a.ellipse(eyeCenter, 15, 15), fill: cream)
        white.strokeColor = blueDeep.cgColor
        white.lineWidth = 1
        eye.addSublayer(white)
        pupil = a.group(pivot: eyeCenter)
        pupil.addSublayer(a.shape(a.ellipse(CGPoint(x: eyeCenter.x + 1.4, y: eyeCenter.y), 8.6, 8.6), fill: ink))
        pupil.addSublayer(a.shape(a.ellipse(CGPoint(x: eyeCenter.x + 3, y: eyeCenter.y + 2), 2.8, 2.8), fill: .white))
        eye.addSublayer(pupil)
        let lid = CGMutablePath()
        lid.move(to: CGPoint(x: eyeCenter.x - 5.5, y: eyeCenter.y))
        lid.addQuadCurve(to: CGPoint(x: eyeCenter.x + 5.5, y: eyeCenter.y), control: CGPoint(x: eyeCenter.x, y: eyeCenter.y - 5))
        closedEye = a.line(lid, color: ink, width: 1.4)

        // A few bubbles that surface only while Tide idles.
        var bubbles: [CALayer] = []
        for size in [CGFloat(4.5), 6, 3.6] {
            let bubble = a.group(pivot: .zero)
            let ring = a.shape(a.ellipse(.zero, size, size), fill: blueLight.withAlphaComponent(0.25))
            ring.strokeColor = blueLight.withAlphaComponent(0.9).cgColor
            ring.lineWidth = 0.9
            bubble.addSublayer(ring)
            bubble.addSublayer(a.shape(a.ellipse(CGPoint(x: size * 0.18, y: size * 0.18), size * 0.3, size * 0.3),
                                       fill: .white.withAlphaComponent(0.9)))
            bubble.opacity = 0
            bubbles.append(bubble)
        }
        self.bubbles = bubbles

        swimmer.addSublayer(dorsal)
        swimmer.addSublayer(pelvic)
        swimmer.addSublayer(tail)
        swimmer.addSublayer(hull)
        swimmer.addSublayer(pectoral)
        swimmer.addSublayer(eye)
        swimmer.addSublayer(closedEye)
        swimmer.addSublayer(mouthOpen)
        body.addSublayer(swimmer)
        overlay = a.group()
        for bubble in bubbles { overlay.addSublayer(bubble) }
    }

    func apply(_ f: PetMotionFrame, facing: CGFloat) {
        let amp = CGFloat(f.limbAmplitude)
        let beat = f.tailPhase
        // The tail sweeps and folds; the body answers with a small yaw.
        let flick = wave(beat) * (0.1 + 0.24 * amp)
        let fold = 0.84 + 0.16 * pow(CGFloat(cos(beat * 2 * .pi)), 2)
        rotate(tail, flick, sx: fold)
        rotate(swimmer, -flick * 0.12)
        let flutter = wave(f.limbPhase)
        // Dozing folds the fins down and slows everything.
        let doze = f.pose.lie
        rotate(dorsal, flutter * 0.05 - flick * 0.1 - 0.12 * doze)
        rotate(pelvic, -flutter * 0.12)
        let paddle = flutter * (0.18 + 0.12 * amp) * (1 - 0.7 * doze)
        rotate(pectoral, paddle + 0.35 * doze, sx: 0.8 + 0.2 * abs(flutter))
        let mouth = max(0, min(1, f.pose.mouth))
        mouthOpen.opacity = Float(min(1, mouth * 3))
        mouthOpen.setAffineTransform(CGAffineTransform(scaleX: max(0.05, mouth), y: max(0.05, mouth)))

        let side: CGFloat = facing >= 0 ? 1 : -1
        pupil.setAffineTransform(CGAffineTransform(translationX: 1.8 * finite(f.gaze) * side,
                                                   y: 1.6 * finite(f.gazeLift)))
        let open = max(0, min(1, f.eyeOpen))
        eye.setAffineTransform(CGAffineTransform(scaleX: 1, y: max(0.08, open)))
        eye.opacity = Float(min(1, open * 4))
        closedEye.opacity = Float(1 - min(1, open * 4))

        // Bubbles leave the mouth wherever the pose carries it and rise
        // straight up, fading in only as the fish slows. Their climb is
        // capped so they never leave the canvas.
        let calm = max(0, min(1, (1 - (amp - 0.3) / 0.7)))
        let visible = max(0, calm - 0.35) / 0.65
        let tilt = finite(f.rotation)
        let lip = CGPoint(x: (Self.mouth.x + 2 - 80) * facing, y: Self.mouth.y + 3 - 60)
        let turned = CGPoint(x: lip.x * cos(tilt) - lip.y * sin(tilt),
                             y: lip.x * sin(tilt) + lip.y * cos(tilt))
        let start = CGPoint(x: 80 + turned.x, y: min(104, 60 + turned.y))
        let climb = max(0, min(36, 108 - start.y))
        for (index, bubble) in bubbles.enumerated() {
            let t = (f.clock / 3.2 + Double(index) * 0.37).truncatingRemainder(dividingBy: 1)
            let rise = CGFloat(t)
            let drift = (wave(f.clock * 0.9, offset: Double(index)) * 2.5 + rise * 4) * facing
            bubble.position = CGPoint(x: start.x + drift, y: start.y + rise * climb)
            bubble.opacity = Float(visible * CGFloat(sin(t * .pi)))
        }
    }
}
