import SwiftUI

struct BrowserAdvancedSetupSection: View {
    let setupActions: [BrowserAdvancedSetupAction]

    var body: some View {
        Section("Setup") {
            ForEach(setupActions) { setupAction in
                BrowserAdvancedSetupActionButton(setupAction: setupAction)
            }
        }
    }
}

#Preview("Advanced Setup Section") {
    Form {
        BrowserAdvancedSetupSection(
            setupActions: [
                BrowserAdvancedSetupAction(
                    id: "review-setup",
                    title: "Review Crest Setup",
                    symbol: "sparkles"
                ) {}
            ]
        )
    }
    .formStyle(.grouped)
}
