import AppKit
import SwiftUI
import QuartzCore

/// Animated stage for the Pets tab: the same rig the desktop uses, contained
/// in the menu. Runs only while its host window is visible.
struct PetPreview: NSViewRepresentable {
    let kind: PetKind
    let mood: PetMood
    let motionEnabled: Bool

    func makeNSView(context: Context) -> PetStageView { PetStageView() }

    func updateNSView(_ view: PetStageView, context: Context) {
        view.kind = kind
        view.mood = mood
        view.motionEnabled = motionEnabled
    }

    static func dismantleNSView(_ view: PetStageView, coordinator: ()) {
        view.stop()
    }
}

/// A small paper diorama: a torn paper floor for Miso, folded waves for
/// Tide, and the live rig wandering inside it with the desktop's own math.
@MainActor
final class PetStageView: NSView {
    var kind: PetKind = .cat { didSet { if kind != oldValue { rebuild() } } }
    var mood: PetMood = .curious { didSet { if mood != oldValue { applyPose() } } }
    var motionEnabled = true { didSet { if motionEnabled != oldValue { synchronize() } } }

    private var rig = PetRig(kind: .cat)
    private let backdrop = CAShapeLayer()
    private let foreground = CAShapeLayer()
    private var timer: Timer?
    private var elapsed: TimeInterval = 0
    private var lastTick: TimeInterval = 0
    private var visibilityObservation: NSKeyValueObservation?
    private var windowObservers: [NSObjectProtocol] = []

    override var intrinsicContentSize: NSSize { NSSize(width: 300, height: 120) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.addSublayer(backdrop)
        layer?.addSublayer(rig.root)
        layer?.addSublayer(foreground)
    }

    required init?(coder: NSCoder) { nil }

    private func rebuild() {
        rig.root.removeFromSuperlayer()
        rig = PetRig(kind: kind)
        layer?.insertSublayer(rig.root, above: backdrop)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        layoutScenery()
        applyPose()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layoutScenery()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard let window else { return }
        // Same gate as Echo: window visibility, not occlusion — Deckle's own
        // screen-saver-level windows can mark the menu occluded.
        visibilityObservation = window.observe(\.isVisible, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.synchronize() }
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
            windowObservers.append(center.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.synchronize() }
            })
        }
        synchronize()
    }

    override func viewDidHide() { super.viewDidHide(); synchronize() }
    override func viewDidUnhide() { super.viewDidUnhide(); synchronize() }

    func stop() {
        timer?.invalidate()
        timer = nil
        visibilityObservation?.invalidate()
        visibilityObservation = nil
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers = []
    }

    /// Deterministic seam for review renders and tests: pose the stage at an
    /// explicit time on the pet's clock.
    func show(time: TimeInterval) {
        elapsed = max(0, time)
        applyPose()
    }

    private func synchronize() {
        let visible = window?.isVisible == true && window?.isMiniaturized == false
            && !isHiddenOrHasHiddenAncestor
        guard visible, motionEnabled else {
            timer?.invalidate()
            timer = nil
            applyPose()
            return
        }
        guard timer == nil else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        let tick = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
        tick.tolerance = 1 / 120
        timer = tick
        RunLoop.main.add(tick, forMode: .common)
    }

    private func advance() {
        guard window?.isVisible == true, !isHiddenOrHasHiddenAncestor else {
            synchronize()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        elapsed += min(0.1, max(0, now - lastTick))
        lastTick = now
        applyPose()
    }

    /// The pet's size inside the stage; review renders reuse it.
    var spriteSize: CGSize {
        let height = min(bounds.height - 22, bounds.width * 0.3)
        return CGSize(width: height * PetArtwork.canvas.width / PetArtwork.canvas.height, height: height)
    }

    /// The pet wanders inside the stage itself — the same PetMotion math the
    /// desktop uses, bounded by this view.
    private func applyPose() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let sprite = spriteSize
        guard sprite.width > 0, sprite.height > 0 else { return }
        let frame = motionEnabled
            ? PetMotion.frame(kind: kind, mood: mood, time: elapsed, in: bounds, spriteSize: sprite)
            : PetMotion.settledFrame(kind: kind, mood: mood, time: elapsed, in: bounds, spriteSize: sprite)
        let rect = PetMotion.windowRect(center: frame.center, spriteSize: sprite,
                                        bounds: PetMotion.safeBounds(bounds, spriteSize: sprite))
        rig.place(in: rect)
        rig.apply(frame)
    }

    /// Scenery is two static paper cut-outs rebuilt only on resize or an
    /// appearance change.
    private func layoutScenery() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Paws rest on this line: the sprite's lowest travel, plus the
        // artwork's own ground offset inside the canvas.
        let sprite = spriteSize
        let floorLine = bounds.minY + 8 + PetArtwork.ground * sprite.height / PetArtwork.canvas.height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [backdrop, foreground] {
            layer.frame = bounds
            layer.shadowOpacity = 0
        }
        switch kind {
        case .cat:
            let floor = Self.tornStrip(width: bounds.width, top: floorLine + 4, seed: 3)
            backdrop.path = floor
            backdrop.fillColor = (dark
                ? NSColor(srgbRed: 0.17, green: 0.25, blue: 0.20, alpha: 1)
                : NSColor(srgbRed: 0.75, green: 0.85, blue: 0.68, alpha: 1)).cgColor
            foreground.path = Self.tornStrip(width: bounds.width, top: floorLine - 5, seed: 11)
            foreground.fillColor = (dark
                ? NSColor(srgbRed: 0.14, green: 0.21, blue: 0.17, alpha: 1)
                : NSColor(srgbRed: 0.68, green: 0.80, blue: 0.60, alpha: 1)).cgColor
        case .fish:
            backdrop.path = Self.waveStrip(width: bounds.width, top: 26, phase: 0.2)
            backdrop.fillColor = (dark
                ? NSColor(srgbRed: 0.15, green: 0.27, blue: 0.31, alpha: 1)
                : NSColor(srgbRed: 0.72, green: 0.87, blue: 0.94, alpha: 1)).cgColor
            foreground.path = Self.waveStrip(width: bounds.width, top: 12, phase: 1.4)
            foreground.fillColor = (dark
                ? NSColor(srgbRed: 0.12, green: 0.23, blue: 0.27, alpha: 1)
                : NSColor(srgbRed: 0.62, green: 0.81, blue: 0.90, alpha: 1)).cgColor
        }
        CATransaction.commit()
    }

    /// A strip of paper with a hand-torn top edge; deterministic per seed.
    private static func tornStrip(width: CGFloat, top: CGFloat, seed: UInt32) -> CGPath {
        var state = seed &* 2654435761
        func jitter() -> CGFloat {
            state = state &* 1664525 &+ 1013904223
            return CGFloat(state >> 8) / CGFloat(1 << 24) - 0.5
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -2, y: -2))
        path.addLine(to: CGPoint(x: -2, y: top))
        var x: CGFloat = -2
        while x < width + 2 {
            x += 5 + abs(jitter()) * 6
            path.addLine(to: CGPoint(x: x, y: top + jitter() * 2.4))
        }
        path.addLine(to: CGPoint(x: width + 2, y: -2))
        path.closeSubpath()
        return path
    }

    /// A folded paper wave: a soft swell along the top edge.
    private static func waveStrip(width: CGFloat, top: CGFloat, phase: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -2, y: -2))
        path.addLine(to: CGPoint(x: -2, y: top))
        let steps = Int(width / 4) + 2
        for i in 0...steps {
            let x = CGFloat(i) * 4 - 2
            path.addLine(to: CGPoint(x: x, y: top + sin(x / 26 + phase) * 3.2))
        }
        path.addLine(to: CGPoint(x: width + 2, y: -2))
        path.closeSubpath()
        return path
    }
}

/// The Pets mode: a live stage, the two companions, mood/size/display, and
/// one explicit bring/hide action.
struct PetsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var motionPausedReason: String? {
        if reduceMotion { return "Resting in place — Reduce Motion is on." }
        if lowPower { return "Resting in place while Low Power Mode is on." }
        return nil
    }

    private func tone(_ kind: PetKind) -> Color {
        kind == .cat ? StudioStyle.sage : StudioStyle.sky
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            hero

            // Companion picker — illustrated cards, check + border for selection.
            HStack(spacing: 8) {
                ForEach(PetKind.allCases) { kind in
                    petCard(kind)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mood").font(.system(size: 12, weight: .semibold))
                    StudioSegmentedPicker(options: PetMood.allCases.map { ($0.label, $0) },
                                          selection: $state.petMood)
                    .accessibilityLabel("Pet mood")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Size").font(.system(size: 12, weight: .semibold))
                    StudioSegmentedPicker(options: PetSize.allCases.map { ($0.label, $0) },
                                          selection: $state.petSize)
                    .accessibilityLabel("Pet size")
                }
                HStack {
                    Text("Display").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Picker("Display", selection: $state.petDisplayID) {
                        Text("Main display").tag(String?.none)
                        ForEach(NSScreen.screens, id: \.self) { screen in
                            if let id = screen.displayID, !state.excludedDisplays.contains(String(id)) {
                                Text(screen.localizedName).tag(String?(String(id)))
                            }
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                }

                if let reason = motionPausedReason {
                    Label(reason, systemImage: "moon.zzz")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Button {
                    state.petsEnabled.toggle()
                } label: {
                    Label(state.petsEnabled
                          ? "Hide \(state.petKind.name)"
                          : "Bring \(state.petKind.name) to my desk",
                          systemImage: state.petsEnabled ? "eye.slash" : "pawprint")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StudioActionStyle(prominent: true))
                .controlSize(.small)

                Text("Pets are click-through and need no extra permissions. "
                     + "They honor your display and app-rule settings, and rest "
                     + "when Reduce Motion or Low Power Mode is on.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(StudioStyle.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.07)))
        }
        .onAppear {
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    /// One card like the desk hero: a titled paper diorama over a status strip.
    private var hero: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("DESKTOP PETS")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                Text("A little life on your desk.")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .tracking(-0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            PetPreview(kind: state.petKind, mood: state.petMood,
                       motionEnabled: motionPausedReason == nil)
                .frame(height: 118)
                .accessibilityElement()
                .accessibilityLabel("\(state.petKind.name), \(state.petKind.species), preview")
                .accessibilityValue(state.petsEnabled ? "On your desk" : "Waiting")
            HStack(spacing: 6) {
                Circle()
                    .fill(state.petsEnabled ? Color(nsColor: .systemGreen) : .secondary)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(state.petsEnabled
                     ? "\(state.petKind.name) is on your desk"
                     : "\(state.petKind.name) is waiting in the menu")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(state.petMood.label) · \(state.petSize.label)".uppercased())
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(StudioStyle.panel)
        }
        .background(tone(state.petKind))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.07)))
    }

    @ViewBuilder
    private func petCard(_ kind: PetKind) -> some View {
        let selected = state.petKind == kind
        Button {
            state.petKind = kind
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    PetPortrait(kind: kind)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .frame(height: 84)
                        .background(RoundedRectangle(cornerRadius: 12).fill(tone(kind)))
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(nsColor: .windowBackgroundColor), StudioStyle.rust)
                            .padding(6)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.name).font(.system(size: 13, weight: .semibold))
                    Text(kind.species).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
            .padding(4)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? StudioStyle.rust : Color.primary.opacity(0.08),
                            lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(StudioButtonStyle())
        .accessibilityLabel("\(kind.name), \(kind.species)")
        .accessibilityHint(kind.behaviorSummary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A still portrait of the artwork for companion cards. The rig is built
/// once per view; SwiftUI updates only re-pose it.
struct PetPortrait: NSViewRepresentable {
    let kind: PetKind

    func makeNSView(context: Context) -> PetRigView {
        let view = PetRigView(kind: kind)
        view.fitsArtwork = true
        view.pose(.portrait(kind))
        return view
    }

    func updateNSView(_ view: PetRigView, context: Context) {
        view.setKind(kind)
        view.pose(.portrait(kind))
    }
}
