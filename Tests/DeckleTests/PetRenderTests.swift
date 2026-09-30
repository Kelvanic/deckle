import XCTest
import SwiftUI
import ImageIO
@testable import Deckle

/// Opt-in review renders of the Pets tab and the desktop artwork itself.
/// Set DECKLE_RENDER_DIR to write PNGs and GIFs; skipped otherwise.
final class PetRenderTests: XCTestCase {
    private func outputDirectory() throws -> URL {
        guard let directory = ProcessInfo.processInfo.environment["DECKLE_RENDER_DIR"]
        else { throw XCTSkip("Opt-in review renders") }
        return URL(fileURLWithPath: directory)
    }

    @MainActor
    func testRenderPetsTabForReview() async throws {
        let directory = try outputDirectory()
        let suite = "DecklePetRender.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        state.petsEnabled = true

        for (name, kind, scheme) in [
            ("studio-pets", PetKind.cat, ColorScheme.light),
            ("studio-pets-dark", .cat, .dark),
            ("studio-pets-fish", .fish, .light),
            ("studio-pets-fish-dark", .fish, .dark),
        ] as [(String, PetKind, ColorScheme)] {
            state.petKind = kind
            let host = NSHostingView(rootView: MenuView(initialMode: .pets)
                .environmentObject(state).environment(\.colorScheme, scheme))
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 300_000_000)
            try writePNG(host, to: directory.appendingPathComponent(name + ".png"))
        }
    }

    /// Contact sheets of every posture at 3×, on light and dark screens —
    /// the pets appear over arbitrary content, so both must read.
    @MainActor
    func testRenderArtworkSheetsForReview() throws {
        let directory = try outputDirectory()
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
        for kind in PetKind.allCases {
            var frames: [PetMotionFrame] = []
            if kind == .cat {
                var base = PetMotionFrame.portrait(.cat)
                base.pose = .stand
                base.gaze = 0
                base.gazeLift = 0
                base.activity = .walk
                for phase in [0.0, 0.25, 0.5, 0.75] {
                    var walk = base
                    walk.limbPhase = phase
                    walk.limbAmplitude = 1
                    walk.tailPhase = phase
                    frames.append(walk)
                }
                for pose in [PetPose(sit: 1), PetPose(lie: 1), PetPose(stretch: 1),
                             PetPose(crouch: 1), PetPose(leap: 1), PetPose(sit: 0.5)] {
                    var still = base
                    still.pose = pose
                    still.eyeOpen = pose.lie > 0 ? 0 : (pose.stretch > 0 ? 0.4 : 1)
                    still.clock = 1.2
                    frames.append(still)
                }
                var turn = base
                turn.facing = 0.35
                frames.append(turn)
                var left = base
                left.facing = -1
                left.pose = PetPose(sit: 1)
                left.gaze = 1
                left.gazeLift = 0.6
                frames.append(left)
                // Seeded habits: look back, groom (two licks), knead, chase, gallop.
                for (pose, clock, eyes) in [(PetPose(sit: 1, lookBack: 0.5), 0.0, 1.0),
                                            (PetPose(sit: 1, lookBack: 1), 0.0, 1.0),
                                            (PetPose(sit: 1, groom: 1), 0.11, 0.2),
                                            (PetPose(sit: 1, groom: 1), 0.33, 0.2),
                                            (PetPose(lie: 1, knead: 1), 0.2, 0.35),
                                            (PetPose(crouch: 0.35, leap: 0.3, lookBack: 0.8), 0.0, 1.0)] {
                    var habit = base
                    habit.pose = pose
                    habit.clock = clock
                    habit.eyeOpen = CGFloat(eyes)
                    frames.append(habit)
                }
                for phase in [0.0, 0.5] {
                    var sprint = base
                    sprint.pose = PetPose(gallop: 1)
                    sprint.limbPhase = phase
                    sprint.limbAmplitude = 1
                    sprint.activity = .zoom
                    frames.append(sprint)
                }
            } else {
                for t in [0.0, 3.0, 9.0, 21.0, 40.0, 66.0] {
                    frames.append(PetMotion.frame(kind: .fish, mood: .curious, time: t,
                                                  in: bounds, spriteSize: PetArtwork.canvas))
                }
                var hover = PetMotion.frame(kind: .fish, mood: .sleepy, time: 5,
                                            in: bounds, spriteSize: PetArtwork.canvas)
                hover.limbAmplitude = 0.3
                frames.append(hover)
                var blink = frames[0]
                blink.eyeOpen = 0
                frames.append(blink)
                var turn = frames[0]
                turn.facing = 0.3
                frames.append(turn)
                var left = frames[1]
                left.facing = -1
                frames.append(left)
                // Seeded tricks: loop-de-loop, nibble, doze, barrel roll.
                for turn in [CGFloat.pi / 2, .pi, 3 * .pi / 2] {
                    var loop = PetMotionFrame.portrait(.fish)
                    loop.rotation = turn
                    frames.append(loop)
                }
                var nibble = PetMotionFrame.portrait(.fish)
                nibble.pose = PetPose(mouth: 1)
                frames.append(nibble)
                var doze = PetMotionFrame.portrait(.fish)
                doze.pose = PetPose(lie: 1)
                doze.eyeOpen = 0
                doze.limbAmplitude = 0.12
                frames.append(doze)
                var roll = PetMotionFrame.portrait(.fish)
                roll.facing = -0.4
                frames.append(roll)
            }
            for dark in [false, true] {
                let image = try sheet(kind: kind, frames: frames, dark: dark)
                let name = "pet-\(kind.rawValue)-sheet\(dark ? "-dark" : "").png"
                try writePNG(image, to: directory.appendingPathComponent(name))
            }
        }
    }

    /// Real motion, sampled at explicit times so the proof cannot freeze.
    @MainActor
    func testRenderStageMotionForReview() throws {
        let directory = try outputDirectory()
        // Real time at 15 fps, starting just before the first seeded trick:
        // Miso's zoomies or tail chase, Tide's loop-de-loop.
        for (kind, mood, tricks, seconds, name) in [
            (PetKind.cat, PetMood.playful, Set<PetActivity>([.zoom, .chase]), 12.0, "pets-cat-motion"),
            (.fish, .playful, Set<PetActivity>([.loop]), 9.0, "pets-fish-motion"),
        ] {
            let stage = PetStageView(frame: CGRect(x: 0, y: 0, width: 342, height: 118))
            stage.kind = kind
            stage.mood = mood
            let window = NSWindow(contentRect: stage.frame, styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            let backing = NSView(frame: stage.frame)
            backing.wantsLayer = true
            backing.layer?.backgroundColor = (kind == .cat
                ? NSColor(srgbRed: 0.84, green: 0.91, blue: 0.78, alpha: 1)
                : NSColor(srgbRed: 201 / 255, green: 233 / 255, blue: 246 / 255, alpha: 1)).cgColor
            backing.addSubview(stage)
            window.contentView = backing
            defer { stage.stop(); window.close() }
            stage.layoutSubtreeIfNeeded()
            let first = stride(from: 0.0, to: 900, by: 0.25).first { t in
                tricks.contains(PetMotion.frame(kind: kind, mood: mood, time: t, in: stage.bounds,
                                                spriteSize: stage.spriteSize).activity)
            }
            let start = max(0, (first ?? 0) - 2.5)
            let url = directory.appendingPathComponent(name + ".gif")
            let fps = 15.0
            let count = Int(seconds * fps)
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
                url as CFURL, "com.compuserve.gif" as CFString, count, nil))
            CGImageDestinationSetProperties(destination,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            for i in 0..<count {
                stage.show(time: start + Double(i) / fps)
                let frame = try XCTUnwrap(backing.bitmapImageRepForCachingDisplay(in: backing.bounds))
                backing.cacheDisplay(in: backing.bounds, to: frame)
                CGImageDestinationAddImage(destination, try XCTUnwrap(frame.cgImage),
                    [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps]] as CFDictionary)
            }
            XCTAssertTrue(CGImageDestinationFinalize(destination))
        }
    }

    @MainActor
    private func sheet(kind: PetKind, frames: [PetMotionFrame], dark: Bool) throws -> NSView {
        let scale: CGFloat = 2
        let cell = CGSize(width: PetArtwork.canvas.width * scale, height: PetArtwork.canvas.height * scale)
        let columns = 4
        let rows = (frames.count + columns - 1) / columns
        let board = NSView(frame: CGRect(x: 0, y: 0, width: cell.width * CGFloat(columns),
                                         height: cell.height * CGFloat(rows)))
        board.wantsLayer = true
        board.layer?.backgroundColor = (dark ? NSColor(white: 0.11, alpha: 1) : NSColor(white: 0.97, alpha: 1)).cgColor
        for (index, frame) in frames.enumerated() {
            let column = index % columns
            let row = rows - 1 - index / columns
            let view = PetRigView(kind: kind)
            view.frame = CGRect(x: CGFloat(column) * cell.width, y: CGFloat(row) * cell.height,
                                width: cell.width, height: cell.height)
            view.wantsLayer = true
            view.layer?.borderColor = NSColor.gray.withAlphaComponent(0.25).cgColor
            view.layer?.borderWidth = 1
            board.addSubview(view)
            view.layoutSubtreeIfNeeded()
            view.pose(frame)
        }
        return board
    }

    @MainActor
    private func writePNG(_ view: NSView, to url: URL) throws {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}
