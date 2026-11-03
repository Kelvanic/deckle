import AppKit

/// Keeps the overlay's AppKit-facing lifecycle and settings. A directly drawn
/// compositor window presents the paper; this panel is the fallback when the
/// private entry points are unavailable.
final class OverlayWindow: NSPanel {
    private let textureView = TextureView()
    private let overlayScreen: NSScreen
    let renderScale: CGFloat
    private var compositor: CompositorOverlay?
    private var attemptedCompositor = false
    private var fadeTimer: Timer?

    init(screen: NSScreen) {
        overlayScreen = screen
        renderScale = screen.backingScaleFactor
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = .screenSaver
        // Join every app's Stage Manager set as well as every Space. The
        // nonactivating panel stays independent of the app being switched.
        // Keep it stationary during Mission Control and out of Cmd-`.
        collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        contentView = textureView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var isVisible: Bool { compositor?.isVisible ?? super.isVisible }
    var presentedWindowID: CGWindowID { compositor?.windowID ?? CGWindowID(windowNumber) }

    override var alphaValue: CGFloat {
        didSet { compositor?.setAlpha(alphaValue) }
    }

    private var previewRegions: [CGRect] = []
    func setPreviewRegions(_ regions: [CGRect]) {
        guard previewRegions != regions else { return }
        previewRegions = regions
        if let compositor { compositor.setPreviewRegions(regions); return }
        guard !regions.isEmpty else { textureView.layer?.mask = nil; return }
        let path = CGMutablePath()
        path.addRect(textureView.bounds)
        for region in regions { path.addRect(region) }
        let mask = CAShapeLayer()
        mask.path = path
        mask.fillRule = .evenOdd
        textureView.layer?.mask = mask
    }

    func setIntensity(_ value: CGFloat) {
        fadeTimer?.invalidate()
        fadeTimer = nil
        alphaValue = value
    }

    /// AppKit's NSWindow animator only animates its own server window. Drive
    /// both backends through the same setter; the timer exists only for a fade.
    func fade(to target: CGFloat, duration: TimeInterval = 0.4, completion: (() -> Void)? = nil) {
        fadeTimer?.invalidate()
        let initial = alphaValue
        let started = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let progress = min(1, (ProcessInfo.processInfo.systemUptime - started) / duration)
                let eased = progress * progress * (3 - 2 * progress)
                self.alphaValue = initial + (target - initial) * eased
                if progress == 1 {
                    timer.invalidate()
                    self.fadeTimer = nil
                    completion?()
                }
            }
        }
        fadeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    override func orderFrontRegardless() {
        if !attemptedCompositor {
            attemptedCompositor = true
            compositor = CompositorOverlay(screen: overlayScreen, sharing: sharingType)
            if let tile = textureView.renderedTile { compositor?.draw(tile: tile) }
        }
        if let compositor {
            compositor.setAlpha(alphaValue)
            compositor.show()
        } else {
            super.orderFrontRegardless()
            OverlaySpace.shared?.attach(self)
        }
    }

    override func orderOut(_ sender: Any?) {
        if let compositor { compositor.hide() }
        else { super.orderOut(sender) }
    }

    override func close() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        compositor?.close()
        compositor = nil
        super.close()
    }

    func apply(texture: TexturePreset, adjustments: TextureRenderer.GrainAdjustments) {
        textureView.apply(texture: texture, adjustments: adjustments)
        if let tile = textureView.renderedTile { compositor?.draw(tile: tile) }
    }
}

/// Fallback view: shows the texture as a CALayer pattern background.
/// A drawn view forces AppKit to allocate window-sized backing stores
/// (~30 MB per buffer on a Retina display); a pattern background color is
/// tiled by the CoreAnimation render server from a single logical tile
/// (256×256 points, rendered at the view's backing scale), so the overlay
/// costs kilobytes of process memory regardless of screen size.
final class TextureView: NSView {
    private(set) var renderedTile: NSImage?
    private var texture: TexturePreset?
    private var adjustments: TextureRenderer.GrainAdjustments = .none
    private var backingScale: CGFloat = 2

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(texture: TexturePreset, adjustments: TextureRenderer.GrainAdjustments) {
        let scale = window?.backingScaleFactor ?? backingScale
        guard texture != self.texture || adjustments != self.adjustments || scale != backingScale else {
            return
        }
        self.texture = texture
        self.adjustments = adjustments
        self.backingScale = scale
        render()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? backingScale
        guard scale != backingScale else { return }
        backingScale = scale
        render()
    }

    private func render() {
        guard let texture else { return }
        let tile = TextureRenderer.compositeTile(
            for: texture, adjustments: adjustments, backingScale: backingScale)
        renderedTile = tile
        layer?.backgroundColor = NSColor(patternImage: tile).cgColor
    }
}
