import SwiftUI

/// The menu for the group as a whole: the two ways a split ends.
///
/// Everything that belongs to one pane rather than to the run — moving a member
/// along the carousel, taking it out of the split, and every ordinary tab
/// action beside them — is on the member row's own menu, so there is one place
/// that owns tab organization and one that owns the group.
struct BrowserSidebarSplitGroupContextMenu: View {
    let configuration: BrowserSidebarSplitGroupRowConfiguration
    let interaction: BrowserSidebarSplitGroupRowInteractionContext

    var body: some View {
        Group {
            Button("Rename Split View…", systemImage: "pencil") {
                interaction.beginRenaming()
            }
            .disabled(!configuration.isCurrentAndUnlocked)

            Button("Change Icon…", systemImage: "face.smiling") {
                interaction.beginChangingIcon()
            }
            .disabled(!configuration.isCurrentAndUnlocked)

            Button("Change Color…", systemImage: "paintpalette") {
                interaction.beginChangingTint()
            }
            .disabled(!configuration.isCurrentAndUnlocked)

            Divider()

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
        .crestMenuActionLabelStyle()
    }
}
