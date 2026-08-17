import SwiftUI

struct BrowserOnboardingImportSelectionAction: View {
    let hasSelection: Bool
    let skip: () -> Void
    let continueImport: () -> Void

    var body: some View {
        if hasSelection {
            Button("Continue", action: continueImport)
                .buttonStyle(BrowserOnboardingPrimaryButtonStyle())
                .accessibilityIdentifier("onboarding-import-continue")
        } else {
            Button("Skip Import", action: skip)
                .buttonStyle(BrowserOnboardingSecondaryButtonStyle())
                .accessibilityIdentifier("onboarding-import-continue")
        }
    }
}
