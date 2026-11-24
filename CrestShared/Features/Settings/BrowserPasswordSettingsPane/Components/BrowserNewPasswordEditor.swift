import SwiftUI

// MARK: - Types

/// A password the person typed in by hand, ready to save.
struct BrowserNewPassword: Sendable {
    let site: CredentialOrigin
    let address: URL
    let username: String
    let password: String
    let title: String?
}

/// A password added by hand: the site it signs in to, the account and the
/// password, and a title if the person wants one. `save` answers what went
/// wrong, or nil once the password is saved.
struct BrowserNewPasswordEditor: View {
    let makeStrongPassword: () -> String?
    let save: (BrowserNewPassword) async -> String?
    let cancel: () -> Void

    @State private var website = ""
    @State private var title = ""
    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Website", text: $website, prompt: Text(verbatim: "example.com"))
                        .accessibilityIdentifier("new-password-website")
                    TextField("Title", text: $title)
                }
                Section("Account") {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .accessibilityIdentifier("new-password-username")
                    HStack {
                        TextField("Password", text: $password)
                            .font(.body.monospaced())
                            .accessibilityIdentifier("new-password-password")
                        Button("Use Strong Password", systemImage: "key.horizontal.fill") {
                            if let strong = makeStrongPassword() { password = strong }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(CrestChromeButtonStyle())
                        .help(Text("Use Strong Password"))
                    }
                }
                if let errorMessage {
                    BrowserCredentialErrorSection(message: errorMessage)
                }
            }
            .formStyle(.grouped)
            // What's saved is what was typed when Save was pressed.
            .disabled(isSaving)
            .navigationTitle("New Password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await commit() } }
                        .disabled(isSaving || website.isEmpty || password.isEmpty)
                        .accessibilityIdentifier("save-new-password")
                }
            }
        }
        .crestSheetSize(minWidth: 420, idealWidth: 480, minHeight: 320, idealHeight: 380)
    }

    // MARK: - Actions

    /// Saves the password once its site reads as a web address.
    private func commit() async {
        let typed = website.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let site = CredentialOrigin(typed: typed),
            let address = URL(string: typed.contains("://") ? typed : "https://\(typed)")
        else {
            errorMessage = String(localized: "“\(typed)” isn’t a website address.")
            return
        }
        guard !password.isEmpty else {
            errorMessage = String(localized: "A login needs a password.")
            return
        }
        isSaving = true
        defer { isSaving = false }
        errorMessage = await save(
            BrowserNewPassword(
                site: site, address: address, username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password, title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty))
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserNewPasswordEditor(makeStrongPassword: { "kvqhet-Mzawp7-rbnoxc" }, save: { _ in nil }, cancel: {})
    }
#endif
