import XCTest
import SwiftUI
import ImageIO
@testable import Deckle

final class StudioRenderTests: XCTestCase {
    @MainActor
    func testRenderStudioForReview() async throws {
        guard let directory = ProcessInfo.processInfo.environment["DECKLE_RENDER_DIR"] else { throw XCTSkip("Opt-in review renders") }
        let suite = "DeckleStudioRender"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.removePersistentDomain(forName: suite)
        let state = AppState(defaults: defaults)
        for (name, scheme) in [("studio-desk", ColorScheme.light), ("studio-desk-dark", ColorScheme.dark)] {
            let view = MenuView().environmentObject(state).environment(\.colorScheme, scheme)
            let host = NSHostingView(rootView: view)
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            // Yield the main actor so finite entrance motion can finish before capture.
            try await Task.sleep(nanoseconds: 1_200_000_000)
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

        // A native animated render, separate from the user's menu and preferences.
        let ball = NSHostingView(rootView: PaperBallView()
            .frame(width: 140, height: 140).padding(20)
            .background(StudioStyle.sky).environment(\.colorScheme, .light))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 180, height: 180),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = ball
        defer { window.close() }
        window.orderFront(nil)
        let url = URL(fileURLWithPath: directory).appendingPathComponent("echo-motion.gif")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, 90, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for _ in 0..<90 {
            try await Task.sleep(nanoseconds: 33_333_333)
            let frame = try XCTUnwrap(ball.bitmapImageRepForCachingDisplay(in: ball.bounds))
            ball.cacheDisplay(in: ball.bounds, to: frame)
            CGImageDestinationAddImage(destination, try XCTUnwrap(frame.cgImage),
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 30]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    @MainActor
    func testRenderStudioPagesForReview() throws {
        guard let directory = ProcessInfo.processInfo.environment["DECKLE_RENDER_DIR"] else { throw XCTSkip("Opt-in review renders") }
        let suite = "DeckleStudioPagesRender"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        // XCTest's Bundle.main is the test host, so read the version the app bundle ships with.
        let infoPlist = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Support/Info.plist")
        let info = try XCTUnwrap(NSDictionary(contentsOf: infoPlist))
        let appVersion = try XCTUnwrap(info["CFBundleShortVersionString"] as? String)
        for tab in QuickControlsView.ControlTab.allCases {
            let view = QuickControlsView(isExpanded: .constant(true), selectedTab: .constant(tab), versionOverride: appVersion)
                .environmentObject(state).padding(14).frame(width: 370)
                .background(Color(nsColor: .windowBackgroundColor))
            try saveReview(view, name: "studio-controls-" + tab.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"), directory: directory)
        }
        try saveReview(QuickControlsView(isExpanded: .constant(true), selectedTab: .constant(.grain), versionOverride: appVersion)
            .environmentObject(state).padding(14).frame(width: 370)
            .background(Color(nsColor: .windowBackgroundColor)), name: "studio-controls-dark", directory: directory, scheme: .dark)
        var draft = CustomPaper()
        draft.name = "Sunday paper"
        draft.seed = 42
        try saveReview(PaperMillView(draft: draft, isNew: true, dismiss: {}, state: state)
            .frame(width: 430, height: 740).background(Color(nsColor: .windowBackgroundColor)),
                       name: "paper-mill", directory: directory)
        try saveReview(PaperMillView(draft: draft, isNew: true, dismiss: {}, state: state)
            .frame(width: 430, height: 740).background(Color(nsColor: .windowBackgroundColor)),
                       name: "paper-mill-dark", directory: directory, scheme: .dark)
        let browser = CommunityBrowser()
        browser.entries = [
            .init(file: "sample-1.json", name: "Quiet morning", author: "Sample maker", description: "A warm, restrained finish for reading and writing."),
            .init(file: "sample-2.json", name: "Garden notes", author: "Sample maker", description: "A gentle green tint with a little woven texture."),
            .init(file: "sample-3.json", name: "After hours", author: "Sample maker", description: "A deep, muted paper for a quieter desktop.")
        ]
        browser.status = .loaded
        try saveReview(CommunityView(browser: browser), name: "studio-community", directory: directory)
        try saveReview(CommunityView(browser: browser), name: "studio-community-dark", directory: directory, scheme: .dark)
        browser.entries = []
        try saveReview(CommunityView(browser: browser), name: "studio-community-empty", directory: directory)
        browser.status = .failed("Couldn't load the community index")
        try saveReview(CommunityView(browser: browser), name: "studio-community-offline", directory: directory)
    }

    @MainActor
    private func saveReview<V: View>(_ view: V, name: String, directory: String, scheme: ColorScheme = .light) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }

}
