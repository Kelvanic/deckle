import AppKit

/// Visible portions of image windows below Deckle, in Quartz display coordinates.
/// Front-to-back traversal keeps the paper on apps that cover an editor or pin.
enum CleanShotPreview {
    static let bundleID = "pl.maketheweb.cleanshotx"

    static func regions(in rows: [[String: Any]], below overlay: CGWindowID,
                        on display: CGRect, owner: pid_t) -> [CGRect] {
        guard let index = rows.firstIndex(where: {
            ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == overlay
        }) else { return [] }
        var covered: [CGRect] = []
        var clear: [CGRect] = []
        for row in rows.dropFirst(index + 1) {
            guard let dict = row[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  (row[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
            let rect = bounds.intersection(display)
            guard !rect.isNull, !rect.isEmpty else { continue }
            let level = row[kCGWindowLayer as String] as? Int
            // Stage Manager's Dock owns a full-display, transparent host.
            // Its bounding box is not an opaque window over every pinned image.
            if rect.contains(display), level == Int(CGWindowLevelForKey(.dockWindow)),
               let pid = row[kCGWindowOwnerPID as String] as? Int32,
               NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.dock" { continue }
            let name = row[kCGWindowName as String] as? String
            let isCleanShot = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == owner
            // CleanShot uses floating level for pins; the editor is a normal
            // window. Its full-display selection HUD must keep capturing paper.
            if isCleanShot && (level == NSWindow.Level.floating.rawValue ||
                (level == 0 && (name == nil || name == "CleanShot"))) {
                var visible = [rect]
                for occluder in covered where !visible.isEmpty {
                    visible = visible.flatMap { subtract(occluder, from: $0) }
                }
                clear += visible.map { CGRect(x: $0.minX - display.minX,
                    y: display.maxY - $0.maxY, width: $0.width, height: $0.height) }
            }
            covered.append(rect)
            if rect.contains(display) { break }
        }
        return clear
    }

    private static func subtract(_ cut: CGRect, from rect: CGRect) -> [CGRect] {
        let i = rect.intersection(cut)
        guard !i.isNull, !i.isEmpty else { return [rect] }
        return [
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: i.minY - rect.minY),
            CGRect(x: rect.minX, y: i.maxY, width: rect.width, height: rect.maxY - i.maxY),
            CGRect(x: rect.minX, y: i.minY, width: i.minX - rect.minX, height: i.height),
            CGRect(x: i.maxX, y: i.minY, width: rect.maxX - i.maxX, height: i.height)
        ].filter { !$0.isEmpty }
    }
}
