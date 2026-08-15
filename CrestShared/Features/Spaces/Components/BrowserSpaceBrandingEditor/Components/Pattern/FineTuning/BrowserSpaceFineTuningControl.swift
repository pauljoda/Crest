import SwiftUI

struct BrowserSpaceFineTuningControl: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var branding: BrowserSpaceBranding
    @Binding var isExpanded: Bool
    let showsTextureControl: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggleExpansion) {
                HStack(spacing: CrestSpacing.small) {
                    Label("Fine Tune", systemImage: "slider.horizontal.3")
                        .font(CrestTypography.controlTitle)
                    Spacer(minLength: CrestSpacing.medium)
                    Image(systemName: "chevron.right")
                        .font(CrestTypography.metadata.weight(.semibold))
                        .foregroundStyle(CrestColor.textSecondary)
                        .rotationEffect(
                            .degrees(
                                isExpanded
                                    ? BrowserSpaceForgeMetrics.expandedChevronRotation
                                    : 0))
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: BrowserSettingsControlPolicy.minimumTouchTarget,
                    alignment: .leading
                )
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fine Tune")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("space-branding-fine-tuning")

            if isExpanded {
                BrowserSpaceFineTuningFields(
                    branding: $branding,
                    showsTextureControl: showsTextureControl
                )
                .padding(.top, CrestSpacing.small)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func toggleExpansion() {
        withAnimation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.pane,
                reduceMotion: reduceMotion
            )
        ) {
            isExpanded.toggle()
        }
    }
}

#Preview("Fine Tuning Control — Expanded") {
    @Previewable @State var branding = BrowserSpaceBrandingPreviewFixture.gradientBranding
    @Previewable @State var isExpanded = true

    BrowserSpaceFineTuningControl(
        branding: $branding,
        isExpanded: $isExpanded,
        showsTextureControl: true
    )
    .frame(width: 420)
    .padding(CrestSpacing.large)
}
