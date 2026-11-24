import SwiftUI

/// One saved login in Settings: what it is and where it signs in, its
/// password behind authentication, its websites and notes, and in Edit the
/// fields to change them. Deleting it asks first.
struct BrowserCredentialDetailContent: View {
    @Bindable var model: BrowserCredentialDetailModel
    let dismiss: () -> Void
    /// Opens the site's own page for changing the password, where the shell
    /// can open pages from Settings.
    var changePasswordOnWebsite: ((CredentialOrigin) -> Void)? = nil
    /// Deletes the login, after the person confirms.
    var delete: (() -> Void)? = nil
    /// The store that reads and makes one-time codes; nil in previews.
    var browser: BrowserStore? = nil
    var scanPage: (() async -> CGImage?)? = nil
    var scanWithCamera: (() async -> String?)? = nil

    @State private var confirmsDeletion = false

    var body: some View {
        Form {
            BrowserCredentialAccountSection(
                descriptor: model.descriptor,
                spaceName: model.spaceName,
                draft: $model.draft
            )
            if model.draft != nil {
                BrowserCredentialPasswordEditSection(draft: $model.draft, makePassword: model.makeStrongPassword)
            } else {
                BrowserCredentialPasswordSection(model: model)
            }
            BrowserCredentialWebsitesSection(
                descriptor: model.descriptor,
                draft: $model.draft,
                changePasswordOnWebsite: changePasswordOnWebsite,
                concerns: model.request.concerns
            )
            BrowserCredentialCodeSection(
                model: model, browser: browser, scanPage: scanPage, scanWithCamera: scanWithCamera)
            BrowserCredentialNotesSection(model: model)
            BrowserCredentialErrorSection(message: model.errorMessage)
            if let delete, model.draft == nil {
                Section {
                    Button("Delete Password…", role: .destructive) { confirmsDeletion = true }
                        .accessibilityIdentifier("delete-credential")
                        .confirmationDialog(
                            "Delete Password?", isPresented: $confirmsDeletion, titleVisibility: .visible
                        ) {
                            Button("Delete", role: .destructive, action: delete)
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text(model.descriptor.deletionMessage(spaceName: model.spaceName))
                        }
                } footer: {
                    Text(dates).crestFormFootnote()
                }
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("credential-detail-form")
        .navigationTitle(model.descriptor.displayName ?? model.descriptor.origin.host)
        .toolbar {
            if model.draft != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: model.cancelEditing)
                        .disabled(model.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await model.commitEditing() } }
                        .disabled(model.isSaving)
                        .accessibilityIdentifier("save-credential-edit")
                }
            } else {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Edit") { Task { await model.beginEditing() } }
                        .disabled(model.isAuthenticating)
                        .accessibilityIdentifier("edit-credential")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss)
                }
            }
        }
    }

    /// When the login was saved, its password last changed, and it was last used.
    private var dates: String {
        let descriptor = model.descriptor
        var parts = [String(localized: "Saved \(descriptor.createdAt.formatted(date: .abbreviated, time: .omitted))")]
        if let changed = descriptor.passwordChangedAt {
            parts.append(String(localized: "changed \(changed.formatted(date: .abbreviated, time: .omitted))"))
        }
        if let used = descriptor.lastUsedAt {
            parts.append(String(localized: "used \(used.formatted(date: .abbreviated, time: .omitted))"))
        }
        return parts.joined(separator: " · ")
    }
}

extension Binding where Value == BrowserCredentialDraft? {
    /// The edit in progress as a binding that outlives it: once the draft is
    /// gone it reads the draft as it last was and writes nowhere, so a field
    /// still on screen as Save ends the edit never reads a draft that isn't
    /// there. Nil while nothing is being edited.
    @MainActor var editing: Binding<BrowserCredentialDraft>? {
        guard let current = wrappedValue else { return nil }
        let draft = self
        return Binding<BrowserCredentialDraft>(
            get: { draft.wrappedValue ?? current },
            set: { if draft.wrappedValue != nil { draft.wrappedValue = $0 } })
    }
}
