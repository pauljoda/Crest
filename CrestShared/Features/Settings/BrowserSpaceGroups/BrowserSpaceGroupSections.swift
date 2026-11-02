import SwiftUI

/// The note at the end of a pane whose settings a Space's whole group shares,
/// shown while the Space belongs to a group.
struct BrowserSpaceGroupSharingNote: View {
    let browser: BrowserStore
    let spaceID: UUID?

    var body: some View {
        if let space = spaceID.flatMap({ browser.spaceModel($0) }), browser.groupMembers(of: space).count > 1 {
            Section {
            } footer: {
                Text("Shared by \(browser.primary(of: space).settings.name)’s Sub-Spaces.").crestFormFootnote()
            }
        }
    }
}

/// Whether the Sub-Spaces of a Space's group show their own pinned tabs, which
/// one switch decides for the whole group; shown while the Space belongs to
/// one.
struct BrowserSpaceGroupPinnedTabsSection: View {
    let browser: BrowserStore
    let space: SpaceModel

    var body: some View {
        if browser.groupMembers(of: space).count > 1 {
            Section {
                Toggle(
                    "Separate Pinned Tabs",
                    isOn: Binding(
                        get: { space.settings.separatesPinnedTabs },
                        set: { browser.setSeparatePinnedTabs($0, in: space.id) })
                )
                .accessibilityIdentifier("space-separate-pinned-tabs")
            } footer: {
                Text(footnote).crestFormFootnote()
            }
        }
    }

    private var footnote: String {
        let primary = browser.primary(of: space).settings.name
        return space.settings.separatesPinnedTabs
            ? String(localized: "Each Space of \(primary)’s group shows its own pinned tabs.")
            : String(localized: "Every Space of \(primary)’s group shows \(primary)’s pinned tabs.")
    }
}
