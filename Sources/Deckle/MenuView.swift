import SwiftUI
import AppKit

/// A paper-first desk, a searchable library, pets, and a controls surface.
/// One mode at a time — desk, library, pets, or controls replace content.
struct MenuView: View {
    enum Mode: String {
        case desk, library, pets
    }

    @EnvironmentObject private var state: AppState
    @ObservedObject private var updater = UpdateManager.shared
    @State private var searchText = ""
    @State private var isShowingAllPapers = false
    @State private var mode: Mode
    @ObservedObject private var mill = PaperMill.shared
    @State private var isDetailsExpanded = false
    @State private var selectedControlTab: QuickControlsView.ControlTab = .grain
    @State private var dismissedUpdateVersion: String?
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(initialMode: Mode = .desk) {
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        MenuPopover(preferredWidth: 370, onHide: { state.isComparingOriginal = false }) {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 12) {
            topHeaderBar
            HStack(spacing: 0) {
                studioTab("Your desk", selected: mode == .desk && !isDetailsExpanded) {
                    state.isComparingOriginal = false
                    searchText = ""
                    isShowingAllPapers = false
                    mode = .desk
                    isDetailsExpanded = false
                }
                studioTab("Library", selected: mode == .library && !isDetailsExpanded) {
                    state.isComparingOriginal = false
                    isShowingAllPapers = true
                    mode = .library
                    isDetailsExpanded = false
                }
                studioTab("Pets", selected: mode == .pets && !isDetailsExpanded) {
                    state.isComparingOriginal = false
                    searchText = ""
                    mode = .pets
                    isDetailsExpanded = false
                }
            }
            .padding(3)
            .background(StudioStyle.sky.opacity(0.35))
            .clipShape(Capsule())

            if case .available(let version) = updater.status, dismissedUpdateVersion != version {
                updateBanner(version: version)
            } else if updater.status == .installing {
                installingBanner
            } else if case .failed(let message) = updater.status {
                updateFailedBanner(message)
            }

            if isDetailsExpanded {
                QuickControlsView(isExpanded: $isDetailsExpanded, selectedTab: $selectedControlTab)
            } else if mode == .pets {
                PetsView()
            } else if isLibraryFocused {
                searchBar
                PresetCollectionView(
                    searchText: $searchText,
                    isShowingAllGrid: $isShowingAllPapers,
                    onOpenMill: { paper, isNew in
                        if isNew { PaperMill.shared.compose(from: paper) }
                        else { PaperMill.shared.open(editing: paper) }
                    }
                )
            } else {
                HeroCardView()
                Divider()
                DeskSetupsView()
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 370)
        .tint(StudioStyle.rust)
        // Native popover geometry follows the final content size directly.
        .animation(nil, value: isLibraryFocused)
        .animation(nil, value: isDetailsExpanded)
        .onDisappear { state.isComparingOriginal = false }
        .onChange(of: state.textureID) { _ in state.isComparingOriginal = false }
    }

    private func studioTab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(selected ? Color(nsColor: .windowBackgroundColor) : Color.primary)
                .background(selected ? Color.primary : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(StudioButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var topHeaderBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Deckle")
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                Text("LESS GLASS. MORE FEELING.")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                state.isComparingOriginal = false
                PaperMill.shared.toggle()
            } label: {
                Label(mill.isOpen ? "Close Mill" : "Paper Mill", systemImage: "scissors")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Create and edit custom papers")
            Button {
                state.isComparingOriginal = false
                isDetailsExpanded.toggle()
                selectedControlTab = .grain
                isSearchFocused = false
            } label: {
                Image(systemName: isDetailsExpanded ? "xmark" : "slider.horizontal.3")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
                    .background(isDetailsExpanded ? StudioStyle.rust.opacity(0.10) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .topTrailing) {
                        if isUpdateAvailable { Circle().fill(StudioStyle.rust).frame(width: 5, height: 5) }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDetailsExpanded ? "Close controls" : "Controls and settings")
            .help("Grain, snooze, displays, app rules and settings")
        }
    }

    private var isUpdateAvailable: Bool {
        if case .available = updater.status { return true }
        return false
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isLibraryFocused: Bool {
        mode == .library || isSearching || isShowingAllPapers
    }

    // MARK: - 2. Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSearchFocused ? Color.accentColor : .secondary)
                .accessibilityHidden(true)

            TextField("Search all papers & textures…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isSearchFocused)
                .onChange(of: isSearchFocused) { focused in
                    if focused {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    isSearchFocused = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSearchFocused ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.activate(ignoringOtherApps: true)
            isSearchFocused = true
        }
    }

    // MARK: - 3. Update & Notification Banners

    private func updateBanner(version: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Deckle \(version) is available")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)

                Text("A new version is ready to install.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button(action: {
                updater.installLatest(userInitiated: true)
            }) {
                Text("Update")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 3, y: 1)
            }
            .buttonStyle(.plain)

            Button(action: {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    dismissedUpdateVersion = version
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(5)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss notification")
            .accessibilityLabel("Dismiss update notice")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.accentColor.opacity(0.08), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
    }

    private var installingBanner: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text("Installing update…")
                    .font(.system(size: 12, weight: .semibold))
                Text("Deckle will relaunch automatically.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    /// A bounced update attempt must explain itself: this is where the user
    /// learns *why* in-place install was impossible, not just that it was.
    private func updateFailedBanner(_ message: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                // Offer the manual download only when an update genuinely
                // exists; a network blip shouldn't advertise releases.
                if updater.latestKnownVersion != nil {
                    Button("Open release page") {
                        updater.openReleases()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                }
            }

            Spacer(minLength: 4)

            Button(action: {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    // Record the version first: restoring `.available` must
                    // not replace this banner with a second banner.
                    dismissedUpdateVersion = updater.latestKnownVersion
                    updater.acknowledgeFailure()
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(5)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss update message")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - 8. Footer

    private var footer: some View {
        VStack(spacing: 8) {
            // Shortcuts & External Links Line
            HStack {
                HStack(spacing: 4) {
                    Text("⌥⌘P")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text(HotKey.isRegistered ? "toggles anywhere" : "unavailable")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityLabel(HotKey.isRegistered
                                    ? "Option Command P toggles the paper from any app"
                                    : "The Option Command P shortcut is unavailable")

                Spacer()

                HStack(spacing: 8) {
                    Link("★ GitHub", destination: URL(string: "https://github.com/YellowFoxH4XOR/deckle")!)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Button("Quit") {
                        NSApp.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .keyboardShortcut("q")
                }
            }
        }
        .padding(.top, 4)
    }

}
