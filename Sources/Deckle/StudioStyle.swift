import SwiftUI

/// Ink, warm paper, and a cool blue stage for the little paper companion.
enum StudioStyle {
    static let sky = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.18, green: 0.32, blue: 0.36, alpha: 1)
            : NSColor(srgbRed: 201 / 255, green: 233 / 255, blue: 246 / 255, alpha: 1)
    })
    static let panel = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.16, green: 0.17, blue: 0.17, alpha: 1)
            : NSColor(srgbRed: 0.98, green: 0.97, blue: 0.94, alpha: 1)
    })

    static let rust = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.90, green: 0.57, blue: 0.39, alpha: 1)
            : NSColor(srgbRed: 0.70, green: 0.29, blue: 0.13, alpha: 1)
    })
}

/// Isolates spectral thumbnail work from unrelated UI state changes.
struct PaperSample: View, Equatable {
    let preset: TexturePreset
    let size: CGSize

    var body: some View {
        Group {
            if preset.isQuietReading {
                // Quiet swatches use actual overlay strength, never boosted grain.
                ZStack {
                    Color(nsColor: preset.isDark
                          ? NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1) : .white)
                    Image(nsImage: TextureRenderer.compositeTile(for: preset, backingScale: 1))
                        .resizable(resizingMode: .tile)
                        .opacity(0.22)
                }
            } else {
                Image(nsImage: TextureRenderer.preview(for: preset, size: size))
                    .resizable()
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .accessibilityHidden(true)
    }
}

/// Hover and press feedback stays on the composed label, outside texture rendering.
struct StudioButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        StudioButtonLabel(configuration: configuration, reduceMotion: reduceMotion, isEnabled: isEnabled)
    }

    private struct StudioButtonLabel: View {
        let configuration: ButtonStyle.Configuration
        let reduceMotion: Bool
        let isEnabled: Bool
        @State private var hovered = false

        var body: some View {
            configuration.label
                .brightness(hovered && isEnabled ? 0.025 : 0)
                .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? 0.98 : 1)
                .offset(y: hovered && isEnabled && !configuration.isPressed && !reduceMotion ? -1 : 0)
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { hovered = $0 }
        }
    }
}

struct StudioActionStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.vertical, 10)
            .foregroundStyle(prominent ? Color(nsColor: .windowBackgroundColor) : Color.primary)
            .background(prominent ? Color.primary : StudioStyle.sky.opacity(0.45))
            .clipShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

extension StudioStyle {
    static let sage = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.22, green: 0.31, blue: 0.25, alpha: 1)
            : NSColor(srgbRed: 0.84, green: 0.91, blue: 0.78, alpha: 1)
    })
    static let lilac = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.30, green: 0.26, blue: 0.38, alpha: 1)
            : NSColor(srgbRed: 0.89, green: 0.85, blue: 0.96, alpha: 1)
    })
}

struct StudioBanner: View {
    let eyebrow: String
    let title: String
    let detail: String
    let symbol: String
    var color: Color = StudioStyle.sky
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .tracking(-0.6)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                ForEach(0..<3) { index in
                    RoundedRectangle(cornerRadius: 7)
                        .fill(StudioStyle.panel.opacity(index == 2 ? 1 : 0.65))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.13)))
                        .frame(width: 43, height: 56)
                        .rotationEffect(.degrees(Double(index - 1) * (hovered && !reduceMotion ? 19 : 11)))
                        .offset(x: CGFloat(index - 1) * 8, y: index == 1 ? -3 : 3)
                }
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .medium))
                    .rotationEffect(.degrees(hovered && !reduceMotion ? -8 : 0))
            }
            .frame(width: 72, height: 76)
            .accessibilityHidden(true)
        }
        .padding(16)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7), value: hovered)
    }
}

/// Full-width segmented choice. A native segmented Picker keeps its intrinsic
/// width on macOS and leaves a gap inside full-width control panels.
struct StudioSegmentedPicker<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.label)
                        .font(.system(size: 11, weight: selected ? .semibold : .medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        // Window color keeps contrast on the lighter dark-mode rust.
                        .foregroundStyle(selected ? Color(nsColor: .windowBackgroundColor) : Color.primary)
                        .background(selected ? StudioStyle.rust : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        .opacity(isEnabled ? 1 : 0.45)
        // Callers label the group; each segment keeps its own label.
        .accessibilityElement(children: .contain)
    }
}

struct StudioSectionTitle: View {
    let number: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(StudioStyle.rust)
                .padding(5)
                .background(StudioStyle.rust.opacity(0.09), in: RoundedRectangle(cornerRadius: 5))
            Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
        }
    }
}
