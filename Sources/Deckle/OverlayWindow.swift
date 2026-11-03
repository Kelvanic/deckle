import AppKit

/// A borderless, transparent, click-through window that sits above everything
/// (including the menu bar) and simply draws the paper texture.
final class OverlayWindow: NSPanel {
    private let textureView = TextureView()

    init(screen: NSScreen) {
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

    func apply(texture: TexturePreset, adjustments: TextureRenderer.GrainAdjustments) {
        textureView.apply(texture: texture, adjustments: adjustments)
    }
}

/// Shows the texture as a CALayer pattern background instead of drawing it.
/// A drawn view forces AppKit to allocate window-sized backing stores
/// (~30 MB per buffer on a Retina display); a pattern background color is
/// tiled by the CoreAnimation render server from a single logical tile
/// (256×256 points, rendered at the view's backing scale), so the overlay
/// costs kilobytes of process memory regardless of screen size.
final class TextureView: NSView {
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
        layer?.backgroundColor = NSColor(patternImage: tile).cgColor
    }
}
