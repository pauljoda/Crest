import SwiftUI

struct MobileOnboardingTitle: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: MobileOnboardingLayout.titleSpacing) {
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: MobileOnboardingLayout.titleMaximumWidth)
    }
}

#Preview("Onboarding Title") {
    MobileOnboardingTitle(
        title: "Everything in its Space",
        detail: "Each Space keeps its own tabs, history, and identity."
    )
    .padding()
}
