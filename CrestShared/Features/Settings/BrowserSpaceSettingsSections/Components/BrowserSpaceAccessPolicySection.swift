import SwiftUI

/// The lock on a Space, and the one toggle that puts it there.
///
/// Both shells had written this section, its in-flight flag, and the same
/// three-step change — unlock before opening a locked Space, write the policy,
/// lock again after closing one — and the copies agreed on all of it except the
/// toggle's own sentence. Owning the flag here is what keeps the shells from
/// needing the state at all.
struct BrowserSpaceAccessPolicySection: View {
    let browser: BrowserStore
    let space: BrowserSpace
    let spaceAccess: BrowserSpaceAccessController

    @State private var isUpdating = false

    var body: some View {
        Section("Private Space") {
            Toggle(
                "Require device authentication to view this Space",
                isOn: requiresAuthentication
            )
            .disabled(isUpdating)
            .accessibilityIdentifier("private-space-toggle")

            if isUpdating {
                ProgressView("Updating Space protection…")
                    .controlSize(.small)
            }

            Text(
                "Crest uses Face ID, Touch ID, or the normal device passcode or password. Private Spaces lock again when Crest leaves the foreground."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var requiresAuthentication: Binding<Bool> {
        Binding {
            browser.liveSpace(space).accessPolicy.requiresAuthentication
        } set: { isRequired in
            Task { await updateAccessPolicy(isRequired: isRequired) }
        }
    }

    private func updateAccessPolicy(isRequired: Bool) async {
        isUpdating = true
        defer { isUpdating = false }

        if !isRequired {
            guard await spaceAccess.unlock(browser.liveSpace(space)) else {
                return
            }
        }
        browser.updateSpaceAccessPolicy(
            isRequired ? .deviceOwnerAuthentication : .open,
            in: space.id
        )
        if isRequired {
            spaceAccess.lock(space.id)
        }
    }
}
