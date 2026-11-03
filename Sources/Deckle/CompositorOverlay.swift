import AppKit
import Darwin

/// A directly drawn WindowServer window, independent of AppKit's layer tree.
/// Native full-screen zoom animations omit the layer-backed panel even when
/// its position, alpha and Space stay unchanged. This path keeps the same paper
/// visible during the animation (verified with the real texture, not a snapshot
/// of screen content). Window creation follows SketchyBar's window.c.
@MainActor
final class CompositorOverlay {
    private let api: API
    private let connection: Int32
    private(set) var windowID: CGWindowID = 0
    private var context: CGContext?
    private var drawnTile: NSImage?
    private let bounds: CGRect
    private(set) var isVisible = false

    init?(screen: NSScreen, sharing: NSWindow.SharingType) {
        guard let api = API.shared, let displayID = screen.displayID,
              OverlaySpace.shared != nil else { return nil }
        self.api = api
        connection = api.connection()
        let frame = CGDisplayBounds(displayID)
        bounds = CGRect(origin: .zero, size: frame.size)
        var rect = bounds
        var regionRef: Unmanaged<CFTypeRef>?
        guard api.region(&rect, &regionRef) == 0,
              let region = regionRef?.takeRetainedValue(),
              let empty = api.emptyRegion()?.takeRetainedValue() else { return nil }

        // Nonactivating, click-through, no shadow, excluded from window cycling.
        var tags: UInt64 = (1 << 1) | (1 << 16) | (1 << 9) | (1 << 3) | (1 << 18)
        // AppKit pairs sharingType .none with WindowServer tag 37. Setting
        // only the sharing state leaves this direct window in CleanShot captures.
        if sharing == .none { tags |= UInt64(1) << 37 }
        var clear: UInt64 = 1 << 10 // mutually exclusive opaque-for-events tag
        var id: CGWindowID = 0
        guard api.create(connection, 2, region, empty, 13 | (1 << 18), &tags,
                         Float(frame.minX), Float(frame.minY), 64, &id, nil) == 0,
              id != 0 else { return nil }
        windowID = id
        guard api.resolution(connection, id, Double(screen.backingScaleFactor)) == 0,
              api.setTags(connection, id, &tags, 64) == 0,
              api.clearTags(connection, id, &clear, 64) == 0,
              api.opacity(connection, id, false) == 0,
              api.sharing(connection, id, Int32(sharing.rawValue)) == 0,
              api.level(connection, id, Int32(NSWindow.Level.screenSaver.rawValue)) == 0,
              let context = api.context(connection, id, nil)?.takeRetainedValue() else {
            _ = api.release(connection, id)
            windowID = 0
            return nil
        }
        self.context = context
        context.interpolationQuality = .none
    }

    deinit {
        context = nil
        if windowID != 0 { _ = api.release(connection, windowID) }
    }

    private var previewRegions: [CGRect] = []

    func setPreviewRegions(_ regions: [CGRect]) {
        guard regions != previewRegions else { return }
        let dirty = previewRegions + regions
        previewRegions = regions
        if let tile = drawnTile { paint(tile: tile, dirty: dirty) }
    }

    func draw(tile: NSImage) {
        guard tile !== drawnTile else { return }
        paint(tile: tile, dirty: nil)
        drawnTile = tile
    }

    private func paint(tile: NSImage, dirty: [CGRect]?) {
        guard let context,
              let image = tile.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        context.saveGState()
        if let dirty { context.clip(to: dirty) }
        context.clear(bounds)
        context.draw(image, in: CGRect(origin: .zero, size: tile.size), byTiling: true)
        for rect in previewRegions { context.clear(rect) }
        context.restoreGState()
        context.flush()
        _ = api.flush(connection, windowID, nil)
    }

    func setAlpha(_ alpha: CGFloat) {
        _ = api.alpha(connection, windowID, Float(alpha))
    }

    func show() {
        _ = api.order(connection, windowID, 1, 0)
        OverlaySpace.shared?.attach(windowID: windowID)
        isVisible = true
    }

    func hide() {
        _ = api.order(connection, windowID, 0, 0)
        isVisible = false
    }

    func close() {
        guard windowID != 0 else { return }
        hide()
        context = nil
        _ = api.release(connection, windowID)
        windowID = 0
    }

    /// Resolve everything before allocating a window; older systems can use
    /// the existing AppKit panel if any of these private entry points changes.
    private struct API {
        typealias Connection = @convention(c) () -> Int32
        typealias Region = @convention(c) (UnsafePointer<CGRect>, UnsafeMutablePointer<Unmanaged<CFTypeRef>?>) -> Int32
        typealias EmptyRegion = @convention(c) () -> Unmanaged<CFTypeRef>?
        typealias Create = @convention(c) (Int32, Int32, CFTypeRef, CFTypeRef, Int32, UnsafeMutablePointer<UInt64>, Float, Float, Int32, UnsafeMutablePointer<CGWindowID>, UnsafeMutableRawPointer?) -> Int32
        typealias Resolution = @convention(c) (Int32, CGWindowID, Double) -> Int32
        typealias Tags = @convention(c) (Int32, CGWindowID, UnsafeMutablePointer<UInt64>, Int32) -> Int32
        typealias Opacity = @convention(c) (Int32, CGWindowID, Bool) -> Int32
        typealias WindowInt = @convention(c) (Int32, CGWindowID, Int32) -> Int32
        typealias Context = @convention(c) (Int32, CGWindowID, CFDictionary?) -> Unmanaged<CGContext>?
        typealias Flush = @convention(c) (Int32, CGWindowID, UnsafeMutableRawPointer?) -> Int32
        typealias Alpha = @convention(c) (Int32, CGWindowID, Float) -> Int32
        typealias Order = @convention(c) (Int32, CGWindowID, Int32, CGWindowID) -> Int32
        typealias Release = @convention(c) (Int32, CGWindowID) -> Int32

        static let shared = API()
        let connection: Connection
        let region: Region
        let emptyRegion: EmptyRegion
        let create: Create
        let resolution: Resolution
        let setTags: Tags
        let clearTags: Tags
        let opacity: Opacity
        let sharing: WindowInt
        let level: WindowInt
        let context: Context
        let flush: Flush
        let alpha: Alpha
        let order: Order
        let release: Release

        private init?() {
            guard let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else { return nil }
            func resolve<T>(_ name: String, _ type: T.Type) -> T? {
                dlsym(library, name).map { unsafeBitCast($0, to: type) }
            }
            guard let connection = resolve("SLSMainConnectionID", Connection.self),
                  let region = resolve("CGSNewRegionWithRect", Region.self),
                  let emptyRegion = resolve("CGRegionCreateEmptyRegion", EmptyRegion.self),
                  let create = resolve("SLSNewWindowWithOpaqueShapeAndContext", Create.self),
                  let resolution = resolve("SLSSetWindowResolution", Resolution.self),
                  let setTags = resolve("SLSSetWindowTags", Tags.self),
                  let clearTags = resolve("SLSClearWindowTags", Tags.self),
                  let opacity = resolve("SLSSetWindowOpacity", Opacity.self),
                  let sharing = resolve("SLSSetWindowSharingState", WindowInt.self),
                  let level = resolve("SLSSetWindowLevel", WindowInt.self),
                  let context = resolve("SLWindowContextCreate", Context.self),
                  let flush = resolve("SLSFlushWindowContentRegion", Flush.self),
                  let alpha = resolve("SLSSetWindowAlpha", Alpha.self),
                  let order = resolve("SLSOrderWindow", Order.self),
                  let release = resolve("SLSReleaseWindow", Release.self) else { return nil }
            self.connection = connection
            self.region = region
            self.emptyRegion = emptyRegion
            self.create = create
            self.resolution = resolution
            self.setTags = setTags
            self.clearTags = clearTags
            self.opacity = opacity
            self.sharing = sharing
            self.level = level
            self.context = context
            self.flush = flush
            self.alpha = alpha
            self.order = order
            self.release = release
        }
    }
}
