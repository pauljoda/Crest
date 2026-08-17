import SwiftUI

struct MobileOnboardingAddSpaceCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: MobileOnboardingLayout.addSpaceContentSpacing) {
                Image(systemName: "plus.circle.fill")
                    .font(
                        .system(size: MobileOnboardingLayout.addSpaceSymbolSize)
                    )
                    .symbolRenderingMode(.hierarchical)
                Text("Add New Space")
                    .font(.headline)
                Text("Create another separate place for the browsing that belongs together.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(
                        .horizontal,
                        MobileOnboardingLayout.addSpaceDescriptionHorizontalPadding
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.tint)
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: .rect(
                    cornerRadius: MobileOnboardingLayout.addSpaceCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: MobileOnboardingLayout.addSpaceCornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    Color.secondary.opacity(
                        MobileOnboardingLayout.addSpaceBorderOpacity
                    ),
                    style: StrokeStyle(
                        lineWidth: MobileOnboardingLayout.addSpaceBorderWidth,
                        dash: MobileOnboardingLayout.addSpaceDash
                    )
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            BrowserManualSetupAccessibilityID.addSpace
        )
    }
}
