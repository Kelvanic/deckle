import SwiftUI
import AppKit
import ServiceManagement

/// Expandable fine-tuning panel for Grain parameters, Snooze timer,
/// Multi-Display toggles, App Rules, and Preferences.
struct QuickControlsView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var updater = UpdateManager.shared
    @Binding var isExpanded: Bool
    @Binding var selectedTab: ControlTab
    /// Review renders pass the packaged version; under XCTest, Bundle.main is the test host.
    var versionOverride: String? = nil
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum ControlTab: String, CaseIterable, Identifiable {
        case grain = "Grain"
        case snooze = "Snooze"
        case displays = "Displays"
        case appRules = "App Rules"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .grain: return "slider.horizontal.2.square"
            case .snooze: return "moon.stars.fill"
            case .displays: return "display.2"
            case .appRules: return "app.badge.checkmark"
            case .settings: return "gearshape"
            }
        }
    }

    private var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private var pageTitle: String {
        switch selectedTab {
        case .grain: return L("Dial in the detail.")
        case .snooze: return L("Take a little break.")
        case .displays: return L("Make room for paper.")
        case .appRules: return L("Right place. Right feel.")
        case .settings: return L("At home on your Mac.")
        }
    }

    private var pageDetail: String {
        switch selectedTab {
        case .grain: return L("Tune the size and presence of your paper's grain.")
        case .snooze: return L("A bare screen for a while. Your paper returns automatically.")
        case .displays: return L("Choose which screens get the paper treatment.")
        case .appRules: return L("Let your paper follow the way you work.")
        case .settings: return L("Launch, capture privacy, and updates — all in one place.")
        }
    }

    private var pageColor: Color {
        switch selectedTab {
        case .grain, .displays: return StudioStyle.sky
        case .snooze, .appRules: return StudioStyle.lilac
        case .settings: return StudioStyle.sage
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StudioBanner(eyebrow: L("Controls / ") + L(selectedTab.rawValue), title: pageTitle,
                         detail: pageDetail, symbol: selectedTab.icon, color: pageColor)

            // Every destination fits without a hidden last tab or decorative overflow fade.
            HStack(spacing: 4) {
                ForEach(ControlTab.allCases) { tab in
                    Button { selectedTab = tab } label: {
                        VStack(spacing: 5) {
                            Image(systemName: tab.icon).font(.system(size: 14, weight: .medium))
                            Text(L(tab.rawValue)).font(.system(size: 9, weight: .medium)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(selectedTab == tab ? Color(nsColor: .windowBackgroundColor) : Color.primary)
                        .background(selectedTab == tab ? Color.primary : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(StudioButtonStyle())
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(3)
            .background(StudioStyle.panel, in: RoundedRectangle(cornerRadius: 14))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selectedTab)

            VStack(alignment: .leading, spacing: 12) {
                switch selectedTab {
                case .grain: grainControls
                case .snooze: snoozeControls
                case .displays: displaysControls
                case .appRules: appRulesControls
                case .settings: settingsControls
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StudioStyle.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.07)))
            if !state.isEnabled && (selectedTab == .grain || selectedTab == .appRules || selectedTab == .snooze) {
                Label(L("Enable paper on Your desk to adjust these controls."), systemImage: "pause.circle")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .tint(StudioStyle.rust)
    }

    // MARK: - Grain Controls

    private var grainControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Scale Segmented Picker
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L("Grain Scale"))
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(L(grainScaleLabel))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                StudioSegmentedPicker(options: [
                    (L("Fine"), 0.5), (L("Normal"), 1.0), (L("Coarse"), 2.0), (L("Grainy"), 4.0)
                ], selection: $state.grainScale)
                .accessibilityLabel(L("Grain scale"))
            }

            Divider()

            // Strength Slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L("Grain Visibility"))
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(Int(state.grainStrength * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Slider(value: $state.grainStrength, in: 0.25...2.0)
                    .tint(StudioStyle.rust)
                    .accessibilityLabel(L("Grain visibility"))
                    .accessibilityValue(LF("%@ percent", String(Int(state.grainStrength * 100))))
            }
        }
        .disabled(!state.isEnabled)
    }

    private var grainScaleLabel: String {
        switch state.grainScale {
        case 0.5: return L("0.5× (Fine)")
        case 1.0: return L("1.0× (Standard)")
        case 2.0: return L("2.0× (Coarse)")
        case 4.0: return L("4.0× (Heavy)")
        default: return String(format: "%.1f×", state.grainScale)
        }
    }

    // MARK: - Snooze Controls

    private var snoozeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.isSnoozed, let until = state.snoozeUntil {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Currently Snoozed"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.orange)
                        HStack(spacing: 4) {
                            Text(L("Resuming in"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(timerInterval: Date()...until, countsDown: true)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }

                    Spacer()

                    Button(L("Resume Now")) {
                        state.cancelSnooze()
                        state.isEnabled = true
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Temporarily hide overlay:"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach([15, 30, 60, 120], id: \.self) { minutes in
                            Button(action: { state.snooze(minutes: minutes) }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(minutes >= 60 ? minutes / 60 : minutes)")
                                            .font(.system(size: 23, weight: .semibold, design: .rounded))
                                        Text(minutes >= 60 ? (minutes == 60 ? L("hour") : L("hours")) : L("minutes"))
                                            .font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "moon.zzz").font(.system(size: 18)).foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(StudioStyle.lilac.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(StudioButtonStyle())
                        }
                    }
                }
                .disabled(!state.isEnabled)
            }
        }
    }

    // MARK: - Display Controls

    private var displaysControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Active Displays"))
                .font(.system(size: 12, weight: .semibold))

            ForEach(NSScreen.screens, id: \.self) { screen in
                if let displayID = screen.displayID {
                    HStack {
                        Image(systemName: "display")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        Toggle(screen.localizedName, isOn: displayBinding(String(displayID)))
                            .toggleStyle(.checkbox)
                            .font(.system(size: 12))
                    }
                    .padding(10)
                    .background(StudioStyle.sky.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func displayBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !state.excludedDisplays.contains(id) },
            set: { include in
                if include {
                    state.excludedDisplays.remove(id)
                } else {
                    state.excludedDisplays.insert(id)
                }
            }
        )
    }

    // MARK: - App Rules Controls

    private var appRulesControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            StudioSegmentedPicker(options: [
                (L("Everywhere"), AppState.AppRuleMode.everywhere),
                (L("Except…"), .except),
                (L("Only…"), .only)
            ], selection: $state.appRuleMode)
            .accessibilityLabel(L("Where the paper shows"))

            if state.appRuleMode != .everywhere {
                if state.ruleApps.isEmpty {
                    Text(L("No applications configured yet."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(state.ruleApps) { app in
                                HStack {
                                    Text(app.name)
                                        .font(.system(size: 11))
                                    Spacer()
                                    Button {
                                        state.ruleApps.removeAll { $0.bundleID == app.bundleID }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.tertiary)
                                            .font(.system(size: 12))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(LF("Remove %@", app.name))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                }

                HStack {
                    Button(L("Add App…")) { addRuleApp() }
                        .controlSize(.small)

                    Spacer()

                    Text(state.appRuleMode == .except
                         ? L("Hides in listed apps")
                         : L("Shows only in listed apps"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .disabled(!state.isEnabled)
    }

    private func addRuleApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.message = L("Choose apps for the rule list")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            if !state.ruleApps.contains(where: { $0.bundleID == id }) {
                state.ruleApps.append(.init(bundleID: id, name: name))
            }
        }
    }

    // MARK: - Settings Controls

    private var settingsControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(L("Language"), selection: $state.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.label).tag(language)
                }
            }
            .pickerStyle(.menu)
            .font(.system(size: 12))

            Divider()

            // App version and update status row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Deckle v\(versionOverride ?? updater.currentVersion)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)

                    Text(L("Paper for your Mac · macOS 13+"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                updateStatusBadge
            }
            .padding(.bottom, 2)

            Divider()

            // macOS offers no guaranteed capture opt-out: system screenshots
            // honour sharingType .none, but ScreenCaptureKit apps may not
            // (Apple DTS, developer forums thread 792152).
            Toggle(L("Hide from macOS screenshots"), isOn: $state.hideFromCapture)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .help(L("Screenshots and recordings made with macOS leave the texture out. Some screen-sharing and recording apps can still capture it."))

            Toggle(L("Launch automatically at login"), isOn: launchAtLoginBinding)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .disabled(!isBundled)

            Toggle(L("Install updates automatically"), isOn: $updater.autoInstall)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

            Divider()

            HStack {
                Button(action: {
                    if case .available = updater.status {
                        updater.installLatest(userInitiated: true)
                    } else {
                        Task { await updater.check(userInitiated: true) }
                    }
                }) {
                    HStack(spacing: 5) {
                        if updater.status == .checking || updater.status == .installing {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text(L(updateButtonTitle))
                    }
                }
                .controlSize(.small)
                .disabled(updater.status == .checking || updater.status == .installing)

                Spacer()

                Button(L("Quit Deckle")) {
                    NSApp.terminate(nil)
                }
                .controlSize(.small)
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var updateStatusBadge: some View {
        switch updater.status {
        case .checking:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(L("Checking…"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .upToDate:
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(L("Up to date"))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 10, weight: .medium))
        case .available(let version):
            HStack(spacing: 3) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text(LF("v%@ ready", version))
                    .foregroundStyle(Color.accentColor)
            }
            .font(.system(size: 10, weight: .bold))
        case .installing:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(L("Installing…"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        case .failed(let message):
            Text(L("Update issue"))
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .help(message)
        case .idle:
            EmptyView()
        }
    }

    private var updateButtonTitle: String {
        switch updater.status {
        case .checking: return L("Checking…")
        case .installing: return L("Installing…")
        case .available: return L("Install Update")
        case .upToDate: return L("Check Again")
        case .failed: return L("Retry Check")
        case .idle: return L("Check for Updates")
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enable in
                do {
                    if enable {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    launchAtLogin = enable
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
        )
    }
}
