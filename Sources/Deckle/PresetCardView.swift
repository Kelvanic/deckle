import SwiftUI
import AppKit

/// Category filter options for browsing presets
enum PresetCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case light = "Light"
    case dark = "Dark"
    case custom = "My Papers"

    var id: String { rawValue }
}

/// A modern, tactile preset card for the paper library grid.
struct ModernPresetCard: View {
    let preset: TexturePreset
    let isSelected: Bool
    var isCustom: Bool = false
    var customPaper: CustomPaper? = nil
    var onOpenMill: ((CustomPaper, Bool) -> Void)? = nil
    let action: () -> Void

    @EnvironmentObject private var state: AppState

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                // Top Preview Image
                ZStack(alignment: .topTrailing) {
                    PaperSample(preset: preset, size: CGSize(width: 92, height: 52))
                        .equatable()
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Selected checkmark or custom indicator
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .padding(4)
                            .accessibilityHidden(true)
                    }
                }

                // Text labels
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.85))
                        .lineLimit(1)

                    Text(tagText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .padding(8)
            .frame(width: 108)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? StudioStyle.sky.opacity(0.5) : Color(nsColor: .controlBackgroundColor).opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? StudioStyle.rust : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(StudioButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            if let customPaper {
                Button("Edit in Paper Mill…") {
                    if let onOpenMill {
                        onOpenMill(customPaper, false)
                    } else {
                        PaperMill.shared.open(editing: customPaper)
                    }
                }
                Button("Export Paper…") {
                    PaperFiles.export(customPaper)
                }
                Divider()
                Button("Delete", role: .destructive) {
                    state.customPapers.removeAll { $0.id == customPaper.id }
                }
            } else {
                Button("Duplicate in Paper Mill…") {
                    let duplicate = CustomPaper(duplicating: preset)
                    if let onOpenMill {
                        onOpenMill(duplicate, true)
                    } else {
                        PaperMill.shared.compose(from: duplicate)
                    }
                }
            }
        }
        .help(preset.subtitle)
    }

    private var tagText: String {
        if isCustom {
            return "Custom"
        } else if preset.isQuietReading {
            return preset.id == "clear-veil" ? "No grain" : "Quiet reading"
        } else if preset.isDark {
            return "Dark paper"
        } else if preset.weave != nil {
            return "Woven"
        } else {
            return preset.subtitle.components(separatedBy: ",").first ?? "Smooth"
        }
    }
}

/// The paper library: a searchable multi-column grid with category filters.
/// MenuView shows it only while browsing all papers or searching.
struct PresetCollectionView: View {
    @EnvironmentObject private var state: AppState
    @Binding var searchText: String
    @Binding var isShowingAllGrid: Bool
    var onOpenMill: ((CustomPaper, Bool) -> Void)? = nil
    @State private var selectedCategory: PresetCategory = .all
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var normalizedQuery: String {
        PaperSearch.normalized(searchText)
    }

    private var isSearching: Bool { !normalizedQuery.isEmpty }

    private var gridViewportHeight: CGFloat {
        let rowCount = max(1, (filteredPresets.count + 2) / 3)
        let cardHeight: CGFloat = 108
        let rowSpacing: CGFloat = 8
        let contentHeight = CGFloat(rowCount) * cardHeight
            + CGFloat(max(0, rowCount - 1)) * rowSpacing
            + 4
        return min(isSearching ? 360 : 356, max(cardHeight + 4, contentHeight))
    }

    private var filteredPresets: [TexturePreset] {
        let customPresets = state.customPapers.map { TexturePreset(custom: $0) }

        if isSearching {
            let customIDs = Set(state.customPapers.map(\.id))
            return (TexturePreset.all + customPresets).filter { preset in
                PaperSearch.matches(preset, query: normalizedQuery, isCustom: customIDs.contains(preset.id))
            }
        }

        switch selectedCategory {
        case .all:
            return TexturePreset.all + customPresets
        case .light:
            return TexturePreset.light + customPresets.filter { !$0.isDark }
        case .dark:
            return TexturePreset.dark + customPresets.filter(\.isDark)
        case .custom:
            return customPresets
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isShowingAllGrid && !isSearching {
                StudioBanner(eyebrow: "The paper library", title: "Find your kind of quiet.",
                             detail: "Light, dark, textured, or entirely your own.", symbol: "square.stack.3d.up", color: StudioStyle.sage)
            }
            // Header row; the menu's Your desk tab leaves the library.
            HStack {
                HStack(spacing: 6) {
                    if isSearching {
                        Text("Search Results")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("\(filteredPresets.count)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(StudioStyle.rust)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(StudioStyle.rust.opacity(0.12))
                            .clipShape(Capsule())
                    } else {
                        Text("Paper library")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                }

                Spacer()

                if isSearching {
                    Button("Clear") {
                        searchText = ""
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(StudioStyle.rust)
                    .buttonStyle(.plain)
                }

                Menu {
                    Button("New Paper…") {
                        if let onOpenMill {
                            onOpenMill(CustomPaper(), true)
                        } else {
                            PaperMill.shared.open()
                        }
                    }
                    Button("Import Papers…") { PaperFiles.importPapers() }
                    Button("Community Papers…") { CommunityBrowser.shared.open() }
                } label: {
                    // Menu takes its accessibility name from its label
                    // content; a modifier on the Menu itself is ignored.
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Paper actions")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Paper actions")
            }

            // Category Filter Pills (when in All Grid or searching)
            if isShowingAllGrid && !isSearching {
                HStack(spacing: 6) {
                    ForEach(PresetCategory.allCases) { category in
                        Button(action: {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                                selectedCategory = category
                            }
                        }) {
                            Text(category.rawValue)
                                .font(.system(size: 11, weight: selectedCategory == category ? .semibold : .regular))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(selectedCategory == category ? StudioStyle.rust : Color.primary.opacity(0.06))
                                )
                                .foregroundStyle(selectedCategory == category ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])
                    }

                    Spacer()

                    // Quick New Paper Button
                    Button(action: {
                        if let onOpenMill {
                            onOpenMill(CustomPaper(), true)
                        } else {
                            PaperMill.shared.open()
                        }
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .padding(5)
                            .background(Circle().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help("Create new custom paper")
                    .accessibilityLabel("New paper")
                }
            }

            if filteredPresets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text(isSearching ? "No papers matching \"\(normalizedQuery)\"" : "No papers found")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    if isSearching {
                        Button("Clear Search") {
                            searchText = ""
                        }
                        .controlSize(.small)
                    } else if selectedCategory == .custom {
                        Button("Create custom paper") {
                            if let onOpenMill {
                                onOpenMill(CustomPaper(), true)
                            } else {
                                PaperMill.shared.open()
                            }
                        }
                        .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 132)
                .background(StudioStyle.panel, in: RoundedRectangle(cornerRadius: 16))
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ],
                        spacing: 8
                    ) {
                        ForEach(filteredPresets) { preset in
                            let custom = state.customPapers.first { $0.id == preset.id }
                            ModernPresetCard(
                                preset: preset,
                                isSelected: preset.id == state.textureID,
                                isCustom: custom != nil,
                                customPaper: custom,
                                onOpenMill: onOpenMill
                            ) {
                                state.isComparingOriginal = false
                                state.textureID = preset.id
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: gridViewportHeight)
                .layoutPriority(1)
            }
        }
        // Filters are hidden while collapsed, so a hidden category must not persist.
        .onChange(of: isShowingAllGrid) { expanded in
            if !expanded { selectedCategory = .all }
        }
    }
}
