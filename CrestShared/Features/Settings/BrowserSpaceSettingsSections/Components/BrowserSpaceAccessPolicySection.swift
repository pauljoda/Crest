import SwiftUI

/// The lock on a Space, and the one toggle that puts it there, named for the
/// biometry this device has. A private window's Space never locks, so it
/// offers no lock.
///
/// Both shells had written this section, its in-flight flag, and the same
/// three-step change — unlock before opening a locked Space, write the policy,
/// lock again after closing one — and the copies agreed on all of it except the
/// toggle's own sentence. Owning the flag here is what keeps the shells from
/// needing the state at all.
struct BrowserSpaceAccessPolicySection: View {
    let browser: BrowserStore
    let space: SpaceModel
    let spaceAccess: BrowserSpaceAccessController

    @State private var isUpdating = false

    var body: some View {
        if browser.family.workspace?.kind.locksSpaces == true {
            Section {
                Toggle(isOn: requiresAuthentication) {
                    Text(BrowserSpaceLockMethod.current.toggleTitle)
                }
                .disabled(isUpdating)
                .accessibilityIdentifier("private-space-toggle")

                if isUpdating {
                    ProgressView("Updating Space protection…")
                        .controlSize(.small)
                }

            } header: {
                Text("Lock")
            } footer: {
                CrestFormFootnote("Locks again when Crest goes to the background.")
            }
        }
    }

    private var requiresAuthentication: Binding<Bool> {
        Binding {
            space.settings.requiresAuthentication
        } set: { isRequired in
            Task { await updateAccessPolicy(isRequired: isRequired) }
        }
    }

    private func updateAccessPolicy(isRequired: Bool) async {
        isUpdating = true
        defer { isUpdating = false }

        await spaceAccess.updatePolicy(
            isRequired ? .deviceOwnerAuthentication : .open,
            matching: BrowserSpaceRuntimeAssignment(space: space),
            in: browser
        )
    }
}
