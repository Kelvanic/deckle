import XCTest
@testable import Deckle

/// Stored lists must survive entries this version can't read — for example
/// papers saved by a newer Deckle before a downgrade.
final class SettingsRecoveryTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "DeckleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func paperJSON(id: String, engine: Int) -> String {
        """
        {"id":"\(id)","name":"\(id)","tintRed":0.9,"tintGreen":0.9,"tintBlue":0.9,
         "wash":0.3,"weave":0,"blotch":0,"engineVersion":\(engine),"seed":7}
        """
    }

    @MainActor
    func testUnreadablePaperKeepsTheRestAndPreservesOriginalBytes() throws {
        try withDefaults { defaults in
            let stored = Data("[\(paperJSON(id: "custom-ok", engine: 4)),\(paperJSON(id: "custom-future", engine: 99))]".utf8)
            defaults.set(stored, forKey: "customPapers")

            let state = AppState(defaults: defaults)
            XCTAssertEqual(state.customPapers.map(\.id), ["custom-ok"])
            XCTAssertEqual(defaults.data(forKey: AppState.unreadableKey(for: "customPapers")), stored)

            // Saving must not destroy the preserved copy.
            state.customPapers.append(CustomPaper(seed: 1))
            XCTAssertEqual(defaults.data(forKey: AppState.unreadableKey(for: "customPapers")), stored)
        }
    }

    @MainActor
    func testPreservedPapersAreRecoveredOnceReadable() throws {
        try withDefaults { defaults in
            defaults.set(Data("[\(paperJSON(id: "custom-live", engine: 4))]".utf8), forKey: "customPapers")
            let backup = Data("[\(paperJSON(id: "custom-live", engine: 4)),\(paperJSON(id: "custom-back", engine: 3))]".utf8)
            defaults.set(backup, forKey: AppState.unreadableKey(for: "customPapers"))

            let state = AppState(defaults: defaults)
            XCTAssertEqual(state.customPapers.map(\.id), ["custom-live", "custom-back"])
            XCTAssertNil(defaults.data(forKey: AppState.unreadableKey(for: "customPapers")))
            XCTAssertEqual(AppState(defaults: defaults).customPapers.map(\.id), ["custom-live", "custom-back"],
                           "recovered papers must be written back to the live list")
        }
    }

    @MainActor
    func testCorruptListsArePreservedAndOtherSettingsStillLoad() throws {
        try withDefaults { defaults in
            let garbage = Data("not json".utf8)
            defaults.set(garbage, forKey: "ruleApps")
            defaults.set(garbage, forKey: "deskSetups")
            defaults.set(0.3, forKey: "intensity")

            let state = AppState(defaults: defaults)
            XCTAssertTrue(state.ruleApps.isEmpty)
            XCTAssertTrue(state.deskSetups.isEmpty)
            XCTAssertEqual(state.intensity, 0.3)
            XCTAssertEqual(defaults.data(forKey: AppState.unreadableKey(for: "ruleApps")), garbage)
            XCTAssertEqual(defaults.data(forKey: AppState.unreadableKey(for: "deskSetups")), garbage)
        }
    }
}
