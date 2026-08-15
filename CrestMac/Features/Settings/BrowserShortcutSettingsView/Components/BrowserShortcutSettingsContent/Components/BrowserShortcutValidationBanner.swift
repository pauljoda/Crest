import SwiftUI

struct BrowserShortcutValidationBanner: View {
    @Environment(\.locale) private var locale

    let issue: BrowserShortcutValidationIssue

    var body: some View {
        Label(
            issue.messageResource(locale: locale),
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.footnote)
        .foregroundStyle(.orange)
        .accessibilityIdentifier(
            BrowserShortcutSettingsAccessibilityID.validationMessage
        )
    }
}

#Preview("Invalid Shortcut") {
    BrowserShortcutValidationBanner(issue: .invalidShortcut)
        .padding()
}
