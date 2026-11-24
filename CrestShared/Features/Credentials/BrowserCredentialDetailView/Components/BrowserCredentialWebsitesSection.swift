import SwiftUI

/// Where the login signs in: the site it was saved for, then the ones the
/// person added, which Edit lets them add to and remove. A site without
/// HTTPS says it isn't filled, and the site's own page for changing the
/// password is a click away.
struct BrowserCredentialWebsitesSection: View {
    let descriptor: CredentialDescriptor
    @Binding var draft: BrowserCredentialDraft?
    let changePasswordOnWebsite: ((CredentialOrigin) -> Void)?
    /// What the core found wrong with the password, said above the way to
    /// change it.
    var concerns: [PasswordConcern] = []

    var body: some View {
        Section("Websites") {
            LabeledContent("Saved for", value: descriptor.origin.description)
            if let draft = $draft.editing {
                ForEach(draft.wrappedValue.sites.indices, id: \.self) { index in
                    HStack {
                        TextField("Website", text: site(index, of: draft), prompt: Text("example.com"))
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("credential-site-field-\(index)")
                        Button {
                            if draft.wrappedValue.sites.indices.contains(index) {
                                draft.wrappedValue.sites.remove(at: index)
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(CrestChromeButtonStyle())
                        .foregroundStyle(.secondary)
                        .help("Remove Website")
                        .accessibilityLabel("Remove Website")
                    }
                }
                if draft.wrappedValue.sites.count < CredentialDescriptor.maximumSites {
                    Button("Add Website", systemImage: "plus") {
                        draft.wrappedValue.sites.append("")
                    }
                    .accessibilityIdentifier("add-credential-site")
                }
            } else {
                ForEach(descriptor.sites, id: \.self) { site in
                    Text(site.description)
                }
            }
            ForEach(concerns, id: \.self) { concern in
                Label {
                    Text(concern.message)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.footnote)
                .foregroundStyle(CrestColor.warning)
            }
            if let changePasswordOnWebsite, draft == nil, descriptor.scope == .webForm {
                Button("Change Password on Website", systemImage: "arrow.up.forward.app") {
                    changePasswordOnWebsite(descriptor.origin)
                }
                .accessibilityIdentifier("change-password-on-website")
            }
        }
    }

    /// The site typed at `index`, as its field edits it, reading nothing once
    /// the site was removed.
    private func site(_ index: Int, of draft: Binding<BrowserCredentialDraft>) -> Binding<String> {
        Binding {
            draft.wrappedValue.sites.indices.contains(index) ? draft.wrappedValue.sites[index] : ""
        } set: { value in
            if draft.wrappedValue.sites.indices.contains(index) { draft.wrappedValue.sites[index] = value }
        }
    }
}
