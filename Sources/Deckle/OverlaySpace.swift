import AppKit
import Darwin

/// WindowServer moves even stationary AppKit panels with a full-screen Space
/// during a swipe. A separately visible compositor space stays on the display.
@MainActor
final class OverlaySpace {
    static let shared = OverlaySpace()

    private typealias Connection = @convention(c) () -> Int32
    private typealias Create = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias Show = @convention(c) (Int32, CFArray) -> Void
    private typealias Attach = @convention(c) (Int32, Int32, CFArray, Int32) -> Void

    private let connection: Int32
    private let space: Int32
    private let addWindow: Attach

    private init?() {
        // Resolve the complete private API before creating anything. When
        // unavailable, the ordinary cross-Space AppKit panel still works.
        guard let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let main = dlsym(library, "SLSMainConnectionID"),
              let create = dlsym(library, "SLSSpaceCreate"),
              let level = dlsym(library, "SLSSpaceSetAbsoluteLevel"),
              let show = dlsym(library, "SLSShowSpaces"),
              let attach = dlsym(library, "SLSSpaceAddWindowsAndRemoveFromSpaces") else { return nil }
        connection = unsafeBitCast(main, to: Connection.self)()
        space = unsafeBitCast(create, to: Create.self)(connection, 1, 0)
        guard space > 0,
              unsafeBitCast(level, to: SetLevel.self)(connection, space, 0) == 0
        else { return nil }
        unsafeBitCast(show, to: Show.self)(connection, [NSNumber(value: space)] as CFArray)
        addWindow = unsafeBitCast(attach, to: Attach.self)
    }

    func attach(_ window: NSWindow) {
        attach(windowID: CGWindowID(window.windowNumber))
    }

    func attach(windowID: CGWindowID) {
        // Mask 7 removes prior memberships atomically (as in SketchyBar).
        // This SPI has no usable result on current macOS (successful moves
        // return a stale register value). Membership was verified separately.
        addWindow(connection, space, [NSNumber(value: windowID)] as CFArray, 7)
    }
}
