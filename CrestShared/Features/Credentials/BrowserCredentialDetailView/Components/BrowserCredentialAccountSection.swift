import SwiftUI

/// What the login is: its title and username, which Edit makes fields, and
/// the kind of sign-in and the Space it belongs to.
struct BrowserCredentialAccountSection: View {
    let descriptor: CredentialDescriptor
    let spaceName: String
    @Binding var draft: BrowserCredentialDraft?

    var body: some View {
        Section("Account") {
            if let draft = $draft.editing {
                TextField("Title", text: draft.title, prompt: Text(descriptor.origin.host))
                    .accessibilityIdentifier("credential-title-field")
                TextField("Username", text: draft.username)
                    .textContentType(.username)
                    .accessibilityIdentifier("credential-username-field")
            } else {
                if let title = descriptor.displayName {
                    LabeledContent("Title", value: title)
                }
                LabeledContent("Username", value: descriptor.username)
            }
            if let scope = descriptor.scope.settingsLabel {
                LabeledContent("Type", value: scope)
            }
            LabeledContent("Space", value: spaceName)
        }
    }
}

#if DEBUG
    #Preview("Component") {
        Form {
            BrowserCredentialAccountSection(
                descriptor: BrowserCredentialDetailPreviewFixture.descriptor, spaceName: "Design", draft: .constant(nil)
            )
        }.crestSettingsForm().frame(width: 420, height: 300)
    }
#endif
