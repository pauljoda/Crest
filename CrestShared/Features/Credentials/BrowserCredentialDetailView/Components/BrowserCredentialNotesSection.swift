import SwiftUI

/// The login's notes: hidden until the person authenticates, and a text
/// field in Edit. Notes are secret, kept with the password.
struct BrowserCredentialNotesSection: View {
    @Bindable var model: BrowserCredentialDetailModel

    var body: some View {
        if let draft = $model.draft.editing {
            Section("Notes") {
                TextEditor(text: draft.notes)
                    .frame(minHeight: 72)
                    .accessibilityIdentifier("credential-notes-field")
            }
        } else if let extras = model.revealedExtras {
            if !extras.notes.isEmpty {
                Section("Notes") {
                    Text(verbatim: extras.notes)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else if model.hasNotes {
            Section("Notes") {
                Button("Show Notes", systemImage: "note.text") {
                    Task { await model.revealExtras() }
                }
                .disabled(model.isAuthenticating)
                .accessibilityIdentifier("reveal-credential-notes")
            }
        }
    }
}
