import SwiftUI

struct BrowserOnboardingFailureMessage: View {
    let message: BrowserOnboardingFailureText

    var body: some View {
        switch message {
        case .localized(let resource):
            Text(resource)
        case .verbatim(let text):
            Text(verbatim: text)
        }
    }
}

#Preview("Onboarding Failure") {
    BrowserOnboardingFailureMessage(
        message: .verbatim("The preview import could not be completed.")
    )
    .padding()
}
