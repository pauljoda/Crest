import SwiftUI

struct BrowserAdvancedSetupActionButton: View {
    let setupAction: BrowserAdvancedSetupAction

    @ViewBuilder
    var body: some View {
        if let help = setupAction.help {
            button.help(help)
        } else {
            button
        }
    }

    private var button: some View {
        Button(setupAction.title, systemImage: setupAction.symbol) {
            setupAction.action()
        }
        .buttonStyle(.crestTertiary)
        .crestAccessibilityIdentifier(setupAction.identifier)
    }
}

#Preview("Advanced Setup Action") {
    Form {
        BrowserAdvancedSetupActionButton(
            setupAction: BrowserAdvancedSetupAction(
                id: "review-setup",
                title: "Review Crest Setup",
                symbol: "sparkles",
                help: "Review Spaces and tabs"
            ) {}
        )
    }
    .formStyle(.grouped)
}
