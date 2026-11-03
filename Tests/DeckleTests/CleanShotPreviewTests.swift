import AppKit
import XCTest
@testable import Deckle

final class CleanShotPreviewTests: XCTestCase {
    private let display = CGRect(x: -200, y: 20, width: 200, height: 100)

    private func row(_ id: Int, _ owner: Int, _ level: Int, _ rect: CGRect,
                     name: String = "") -> [String: Any] {
        [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: owner,
         kCGWindowLayer as String: level, kCGWindowName as String: name,
         kCGWindowBounds as String: rect.dictionaryRepresentation]
    }

    func testOnlyUncoveredPartOfPinOnThisDisplayIsCleared() {
        let rows = [row(1, 10, 1000, display),
                    row(2, 20, 5, CGRect(x: -200, y: 30, width: 20, height: 10)),
                    row(3, 30, 3, CGRect(x: -215, y: 30, width: 55, height: 10))]
        XCTAssertEqual(CleanShotPreview.regions(in: rows, below: 1, on: display, owner: 30),
                       [CGRect(x: 20, y: 80, width: 20, height: 10)])
    }

    func testWindowsAbovePaperAndCleanShotSettingsDoNotPunchHoles() {
        let rows = [row(1, 30, 2000, display), row(2, 10, 1000, display),
                    row(3, 30, 0, display, name: "Settings")]
        XCTAssertEqual(CleanShotPreview.regions(in: rows, below: 2, on: display, owner: 30), [])
    }
}
