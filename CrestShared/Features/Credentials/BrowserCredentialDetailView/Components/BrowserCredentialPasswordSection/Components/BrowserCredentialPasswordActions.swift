import SwiftUI

struct BrowserCredentialPasswordActions: View {
    let model: BrowserCredentialDetailModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: CrestSpacing.medium) {
                Button(
                    model.visiblePassword == nil
                        ? "Reveal Password" : "Hide Password",
                    systemImage: model.visiblePassword == nil ? "eye" : "eye.slash"
                ) {
                    Task { await model.toggleReveal() }
                }
                .buttonStyle(BrowserSettingsLabeledActionButtonStyle())
                .disabled(model.isAuthenticating)
                .accessibilityIdentifier("reveal-credential-password")

                Button("Copy Password", systemImage: "doc.on.doc") {
                    Task { await model.copy() }
                }
                .buttonStyle(BrowserSettingsLabeledActionButtonStyle())
                .disabled(model.isAuthenticating)
                .accessibilityIdentifier("copy-credential-password")
            }

            VStack(spacing: CrestSpacing.medium) {
                Button(
                    model.visiblePassword == nil
                        ? "Reveal Password" : "Hide Password",
                    systemImage: model.visiblePassword == nil ? "eye" : "eye.slash"
                ) {
                    Task { await model.toggleReveal() }
                }
                .buttonStyle(BrowserSettingsLabeledActionButtonStyle())
                .disabled(model.isAuthenticating)
                .accessibilityIdentifier("reveal-credential-password")

                Button("Copy Password", systemImage: "doc.on.doc") {
                    Task { await model.copy() }
                }
                .buttonStyle(BrowserSettingsLabeledActionButtonStyle())
                .disabled(model.isAuthenticating)
                .accessibilityIdentifier("copy-credential-password")
            }
        }
    }
}

#Preview("Credential Password Actions", traits: .sizeThatFitsLayout) {
    BrowserCredentialPasswordActions(
        model: BrowserCredentialDetailPreviewFixture.makeModel()
    )
    .frame(width: 420)
    .padding()
}
