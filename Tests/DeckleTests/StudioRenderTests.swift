import XCTest
import SwiftUI
@testable import Deckle

final class StudioRenderTests: XCTestCase {
    @MainActor
    func testRenderStudioForReview() throws {
        guard let directory = ProcessInfo.processInfo.environment["DECKLE_RENDER_DIR"] else { throw XCTSkip("Opt-in review renders") }
        let suite = "DeckleStudioRender"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(defaults: defaults)
        // Show the footer as a running app does, with ⌥⌘P registered.
        HotKey.register()
        for (name, scheme) in [("studio-desk", ColorScheme.light), ("studio-desk-dark", ColorScheme.dark)] {
            let view = MenuView().environmentObject(state).environment(\.colorScheme, scheme)
            let host = NSHostingView(rootView: view)
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
        }
        let library = PresetCollectionView(searchText: .constant(""), isShowingAllGrid: .constant(true))
            .environmentObject(state).padding(14).frame(width: 370)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: library)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent("studio-library.png"))

        // Paper Mill with a fresh default draft, at the editor's usual width.
        let mill = PaperMillView(draft: CustomPaper(id: "custom-render", seed: 0x5EED_0004), isNew: true, dismiss: {})
            .frame(width: 430, height: 860)
            .background(Color(nsColor: .windowBackgroundColor))
        let millHost = NSHostingView(rootView: mill)
        millHost.frame = CGRect(x: 0, y: 0, width: 430, height: 860)
        millHost.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        let millBitmap = try XCTUnwrap(millHost.bitmapImageRepForCachingDisplay(in: millHost.bounds))
        millHost.cacheDisplay(in: millHost.bounds, to: millBitmap)
        try XCTUnwrap(millBitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent("paper-mill.png"))
    }
}
