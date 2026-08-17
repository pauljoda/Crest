import SwiftUI

struct BrowserSpaceBannerSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let identifier: String
    let help: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(CrestColor.textSecondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: BrowserSpaceForgeMetrics.normalizedControlRange) {
                Text(title)
            }
            .labelsHidden()
            .accessibilityValue(
                Text(value, format: .percent.precision(.fractionLength(0)))
            )
            .accessibilityIdentifier(identifier)
            Text(help)
                .font(CrestTypography.metadata)
                .foregroundStyle(CrestColor.textSecondary)
        }
    }
}
