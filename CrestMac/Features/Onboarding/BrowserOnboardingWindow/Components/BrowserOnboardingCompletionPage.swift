import SwiftUI

struct BrowserOnboardingCompletionPage: View {
    let summary: LocalizedStringResource?
    let openCrest: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 70))
                .foregroundStyle(BrowserOnboardingPalette.sage)
            VStack(spacing: 8) {
                Text("Your browser is ready")
                    .font(BrowserOnboardingTypography.display(42))
                    .foregroundStyle(BrowserOnboardingPalette.ink)
                if let summary {
                    Text(summary)
                        .font(
                            BrowserOnboardingTypography.sans(
                                16,
                                weight: .medium
                            )
                        )
                        .foregroundStyle(BrowserOnboardingPalette.inkSoft)
                }
            }
            Button("Open Crest", action: openCrest)
                .buttonStyle(BrowserOnboardingPrimaryButtonStyle())
                .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrowserOnboardingPalette.parchment)
    }
}

#Preview("Onboarding Complete") {
    BrowserOnboardingCompletionPage(
        summary: "Imported 1 Space and 1 tab.",
        openCrest: {}
    )
    .frame(width: 980, height: 604)
}
