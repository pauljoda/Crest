import SwiftUI

struct BrowserCredentialAccountSection: View {
    let descriptor: CredentialDescriptor
    let spaceName: String

    var body: some View {
        Section("Account") {
            LabeledContent("Website", value: descriptor.origin.description)
            LabeledContent("Username", value: descriptor.username)
            if let scope = descriptor.scope.settingsLabel {
                LabeledContent("Type", value: scope)
            }
            LabeledContent("Space", value: spaceName)
        }
    }
}
