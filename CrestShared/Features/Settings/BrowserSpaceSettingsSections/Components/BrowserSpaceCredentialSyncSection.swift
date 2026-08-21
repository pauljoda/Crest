import SwiftUI

/// Whether a Space uses Crest Passwords, and whether those passwords ride
/// iCloud Keychain.
///
/// Turning synchronization on or off rewrites the Space's existing Keychain
/// items, so it is an operation with a progress state and a failure rather than
/// a plain preference binding — which is why the toggle keeps its own state
/// here instead of going through ``BrowserStore/credentialPreferenceBinding``.
///
/// The `Group` is load-bearing: inside a `Form` it keeps its children as their
/// own rows while still handing every one of them the disabled state.
struct BrowserSpaceCredentialSyncSection: View {
    let browser: BrowserStore
    let space: BrowserSpace

    @State private var isSynchronizing = false
    @State private var synchronizationError: String?

    var body: some View {
        Section("Crest Passwords") {
            Toggle(
                "Use Crest Passwords in this Space",
                isOn: browser.credentialPreferenceBinding(
                    \.isEnabled,
                    in: space
                )
            )
            .accessibilityIdentifier("space-crest-passwords-enabled")

            Group {
                Toggle(
                    "Sync this Space’s Crest passwords with iCloud Keychain",
                    isOn: synchronization
                )
                .disabled(isSynchronizing)

                if isSynchronizing {
                    ProgressView("Updating existing Keychain items…")
                        .controlSize(.small)
                }

                if let synchronizationError {
                    Label(
                        synchronizationError,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.red)
                }

                Text(
                    "Crest Passwords remain private to this Space. System Passwords and passkeys are provider-managed and may appear in any Space for the matching site."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .disabled(!currentSpace.credentialPreferences.isEnabled)

            if !currentSpace.credentialPreferences.isEnabled {
                Text(
                    "Saved passwords stay in this Space and can still be viewed or deleted from Passwords settings."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var currentSpace: BrowserSpace {
        browser.liveSpace(space)
    }

    private var synchronization: Binding<Bool> {
        Binding {
            currentSpace.credentialPreferences.syncsCrestPasswordsWithICloud
        } set: { enabled in
            synchronizationError = nil
            isSynchronizing = true
            Task { @MainActor in
                defer { isSynchronizing = false }
                do {
                    try await browser.setCrestPasswordSynchronization(
                        enabled,
                        in: space.id
                    )
                } catch {
                    synchronizationError =
                        "Crest couldn’t update iCloud synchronization."
                }
            }
        }
    }
}
