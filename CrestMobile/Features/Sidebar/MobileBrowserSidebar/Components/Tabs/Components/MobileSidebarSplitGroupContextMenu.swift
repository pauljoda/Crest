import SwiftUI

/// The menu for the group as a whole: the two ways a split ends.
///
/// The same two actions the macOS group row offers, because a split created on
/// one device has to be undoable on the other. Drag-to-split has no mobile
/// counterpart in this release, so this menu — reached from the group's count
/// affordance — is how a phone manages a group at all.
struct MobileSidebarSplitGroupContextMenu: View {
    let configuration: MobileSidebarSplitGroupRowConfiguration

    var body: some View {
        Button("Separate All Tabs", systemImage: "rectangle.split.2x1.slash") {
            guard configuration.isCurrentAndUnlocked,
                let first = configuration.members.first
            else { return }
            configuration.browser.dissolveSplit(
                containing: first.id,
                matching: configuration.assignment
            )
        }
        .disabled(!configuration.isCurrentAndUnlocked)

        if configuration.canClose {
            Divider()

            Button("Close Split", systemImage: "xmark", role: .destructive) {
                guard configuration.isCurrentAndUnlocked else { return }
                // Closing the second-to-last member dissolves the group through
                // the domain's survivor rule, which is exactly what should happen
                // — the final close then takes an ordinary tab.
                for member in configuration.members {
                    configuration.browser.closeTab(
                        member.id,
                        matching: configuration.assignment
                    )
                }
            }
            .disabled(!configuration.isCurrentAndUnlocked)
        }
    }
}
