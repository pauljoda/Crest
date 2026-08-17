import SwiftUI

/// One forge step, including its current value and the controls that shape it.
struct BrowserSpaceForgeSection<Content: View>: View {
    let step: BrowserSpaceForgeStep
    var value: String?
    var caption: LocalizedStringKey?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            VStack(alignment: .leading, spacing: CrestSpacing.small) {
                HStack(alignment: .firstTextBaseline, spacing: CrestSpacing.medium) {
                    Text(step.titleKey)
                        .font(CrestTypography.displaySection)
                        .foregroundStyle(CrestBrandTheme.textDisplay)

                    Spacer(minLength: CrestSpacing.small)

                    if let value {
                        Text(value)
                            .font(CrestTypography.metadata)
                            .foregroundStyle(CrestColor.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Rectangle()
                    .fill(CrestBrandTheme.line)
                    .frame(height: CrestLayout.hairline)

                if let caption {
                    Text(caption)
                        .font(CrestTypography.metadata)
                        .foregroundStyle(CrestColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(step.accessibilityIdentifier)
    }
}
