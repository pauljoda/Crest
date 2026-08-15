import SwiftUI

struct BrowserOnboardingPreviewCardLabel: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(BrowserOnboardingTypography.sans(10, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(BrowserOnboardingPalette.inkSoft)
            Spacer()
            Text(detail)
                .font(
                    BrowserOnboardingTypography.sans(11, weight: .medium)
                )
                .foregroundStyle(
                    BrowserOnboardingPalette.inkSoft.opacity(0.72)
                )
        }
        .padding(.horizontal, 6)
    }
}

#Preview("Import Preview Label") {
    BrowserOnboardingPreviewCardLabel(
        title: "BEFORE",
        detail: "Click anything you don’t want"
    )
    .frame(width: 340)
    .padding()
}
