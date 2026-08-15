import SwiftUI

struct MobileOnboardingFeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: MobileOnboardingLayout.featureRowSpacing) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(
                    width: MobileOnboardingLayout.featureSymbolSize,
                    height: MobileOnboardingLayout.featureSymbolSize
                )
            VStack(
                alignment: .leading,
                spacing: MobileOnboardingLayout.featureRowTextSpacing
            ) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, MobileOnboardingLayout.featureRowVerticalPadding)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Onboarding Feature Row", traits: .fixedLayout(width: 390, height: 100)) {
    MobileOnboardingFeatureRow(
        symbol: "lock.shield.fill",
        title: "Private by design",
        detail: "History, passwords, and site data remain isolated."
    )
    .padding(.horizontal)
}
