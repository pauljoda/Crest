import SwiftUI

struct BrowserCredentialPasswordActions: View {
    let model: BrowserCredentialDetailModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: CrestSpacing.medium) { actions }
            VStack(spacing: CrestSpacing.medium) { actions }
        }
    }

    @ViewBuilder
    private var actions: some View {
        action(
            model.visiblePassword == nil ? "Reveal Password" : "Hide Password",
            systemImage: model.visiblePassword == nil ? "eye" : "eye.slash",
            identifier: "reveal-credential-password"
        ) {
            Task { await model.toggleReveal() }
        }
        action("Copy Password", systemImage: "doc.on.doc", identifier: "copy-credential-password") {
            Task { await model.copy() }
        }
    }

    /// One action, as wide as the row gives it.
    private func action(
        _ title: LocalizedStringKey, systemImage: String, identifier: String, perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.crestSecondary)
        .disabled(model.isAuthenticating)
        .accessibilityIdentifier(identifier)
    }
}

#if DEBUG
    #Preview("Reveal and copy") {
        Form { BrowserCredentialPasswordActions(model: BrowserCredentialDetailPreviewFixture.makeModel()) }
            .crestSettingsForm().frame(width: 420, height: 180)
    }
#endif
