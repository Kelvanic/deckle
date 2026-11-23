import SwiftUI
import AppKit

/// The selected paper is the main surface, like a labelled sample on a desk.
struct HeroCardView: View {
    @EnvironmentObject private var state: AppState

    private var status: String {
        if state.isComparingOriginal { return L("Comparing · bare screen") }
        if state.previewPaper != nil { return L("Paper Mill draft on screen") }
        if state.isSnoozed { return L("Snoozed") }
        return state.isEnabled ? L("Enabled · follows your app rules") : L("Paused")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("MAKE YOURSELF\nCOMFORTABLE."))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1.3)
                        Text(L("A softer\nside of screen."))
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .tracking(-1)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L("A little company for your cursor."))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 18)
                    Spacer(minLength: 0)
                    PaperBallView()
                        .frame(width: 140, height: 140)
                }
                .frame(height: 158)
                .background(StudioStyle.sky)
                HStack(spacing: 11) {
                    PaperSample(preset: state.texture, size: CGSize(width: 44, height: 44))
                        .equatable()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(state.texture.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(state.texture.displaySubtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Text(state.texture.isQuietReading ? L("22%\nSAMPLE") : L("PAPER\nSAMPLE"))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: true, vertical: true)
                }
                .padding(12)
                .background(StudioStyle.panel)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.07)))

            HStack(spacing: 6) {
                Circle().fill(state.shouldShowOverlay && !state.isComparingOriginal ? StudioStyle.rust : .secondary)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
                Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            HStack {
                Text(L("Paper intensity")).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(state.intensity * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $state.intensity, in: 0.05...0.45)
                .accessibilityLabel(L("Paper intensity"))
                .accessibilityValue(LF("%@ percent", String(Int(state.intensity * 100))))

            HStack {
                Text(L("Matte finish")).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int((state.matteStrength * 100).rounded()))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $state.matteStrength, in: 0...1)
                .tint(StudioStyle.rust)
                .accessibilityLabel(L("Matte finish"))
                .accessibilityValue(LF("%@ percent", String(Int((state.matteStrength * 100).rounded()))))

            HStack(spacing: 8) {
                Button {
                    state.isComparingOriginal = false
                    if state.shouldShowOverlay { state.isEnabled = false }
                    else { state.cancelSnooze(); state.isEnabled = true }
                } label: {
                    Label(state.shouldShowOverlay ? L("Pause paper") : L("Enable paper"),
                          systemImage: state.shouldShowOverlay ? "pause" : "play")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StudioActionStyle(prominent: true))
                .disabled(state.previewPaper != nil)
                Button {
                    state.isComparingOriginal.toggle()
                } label: {
                    Label(state.isComparingOriginal ? L("Back to paper") : L("Compare original"),
                          systemImage: "rectangle.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StudioActionStyle(prominent: false))
                .disabled(!state.shouldShowOverlay && state.previewPaper == nil && !state.isComparingOriginal)
                .help(L("Temporarily hide the paper. Closing the menu restores it."))
            }
            .controlSize(.small)
            .font(.system(size: 11))
        }
    }
}
