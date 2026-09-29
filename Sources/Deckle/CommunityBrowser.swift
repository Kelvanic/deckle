import SwiftUI
import AppKit

/// Browses community-contributed papers from the deckle-papers repo:
/// a static index.json served by GitHub — no backend, contributions are PRs.
@MainActor
final class CommunityBrowser: ObservableObject {
    static let shared = CommunityBrowser()

    struct Entry: Codable, Identifiable {
        let file: String
        let name: String
        let author: String
        let description: String
        var id: String { file }
    }

    enum Status: Equatable {
        case idle, loading, loaded, failed(String)
    }

    @Published var entries: [Entry] = []
    @Published var status: Status = .idle
    @Published var installing: Set<String> = []

    private var window: NSWindow?
    private static let base = "https://raw.githubusercontent.com/YellowFoxH4XOR/deckle-papers/main"

    func open() {
        MenuDismiss.dismiss()
        if window == nil {
            let hosting = NSHostingController(rootView: CommunityView(browser: self))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Community Papers"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.center()
            self.window = window
        }
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if status == .idle { Task { await load() } }
    }

    func load() async {
        status = .loading
        do {
            let url = URL(string: "\(Self.base)/index.json")!
            let (data, _) = try await URLSession.shared.data(from: url)
            entries = try JSONDecoder().decode([Entry].self, from: data)
            status = .loaded
        } catch {
            status = .failed("Couldn't load the community index")
        }
    }

    func install(_ entry: Entry) async {
        // Only fetch files listed by the index, never arbitrary paths.
        let file = entry.file.replacingOccurrences(of: "..", with: "")
        guard let url = URL(string: "\(Self.base)/papers/\(file)") else { return }
        installing.insert(entry.id)
        defer { installing.remove(entry.id) }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              var paper = try? JSONDecoder().decode(CustomPaper.self, from: data) else { return }
        paper.id = "custom-\(UUID().uuidString.lowercased())"
        AppState.shared.customPapers.append(paper)
        AppState.shared.textureID = paper.id
    }
}

struct CommunityView: View {
    @ObservedObject var browser: CommunityBrowser

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioBanner(eyebrow: "Community papers", title: "Good paper gets shared.",
                         detail: "Small recipes from other desks. Find a finish to make your own.",
                         symbol: "person.2", color: StudioStyle.sage)
            switch browser.status {
            case .idle, .loading:
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Gathering papers…").font(.system(size: 13, weight: .medium))
                    Text("Opening the community collection.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            case .failed(let message):
                VStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 25)).foregroundStyle(.secondary)
                    Text(message).font(.system(size: 17, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text("Your saved papers are still available in the library.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Try again") { Task { await browser.load() } }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, minHeight: 170)
            case .loaded:
                HStack {
                    Text("THE COLLECTION").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
                    Spacer()
                    Text("\(browser.entries.count) papers").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if browser.entries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "tray").font(.system(size: 26)).foregroundStyle(.secondary)
                        Text("The shelf is waiting.").font(.system(size: 17, weight: .semibold, design: .rounded))
                        Text("Share the first paper using the community link below.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(browser.entries) { entry in
                                CommunityPaperRow(entry: entry, installing: browser.installing.contains(entry.id)) {
                                    Task { await browser.install(entry) }
                                }
                            }
                        }
                    }
                    .frame(minHeight: 180, maxHeight: 340)
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Made something lovely?").font(.system(size: 12, weight: .semibold))
                    Text("Share a recipe with the community.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Link(destination: URL(string: "https://github.com/YellowFoxH4XOR/deckle-papers")!) {
                    Label("Contribute", systemImage: "arrow.up.right")
                        .font(.system(size: 11, weight: .medium))
                }
                // Link ignores the container tint and would fall back to system blue.
                .foregroundStyle(StudioStyle.rust)
            }
            .padding(12)
            .background(StudioStyle.panel, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(18)
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(StudioStyle.rust)
    }
}

private struct CommunityPaperRow: View {
    let entry: CommunityBrowser.Entry
    let installing: Bool
    let install: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Metadata-only index: this is a document icon, not a fabricated texture preview.
            Image(systemName: "doc.text")
                .font(.system(size: 24, weight: .light))
                .frame(width: 46, height: 60)
                .background(StudioStyle.sage.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.name).font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("by " + entry.author).font(.system(size: 10)).foregroundStyle(StudioStyle.rust)
                Text(entry.description).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: install) {
                Text(installing ? "Adding…" : "Install")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(StudioStyle.sky, in: Capsule())
            }
            .buttonStyle(StudioButtonStyle())
            .disabled(installing)
        }
        .padding(12)
        .background(StudioStyle.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.07)))
    }
}
