import SwiftUI

/// The tab row while its title is being edited.
///
/// Renaming happens in place, where the title already is, so the row keeps its
/// favicon and its shape and only the text becomes editable. Return commits,
/// Escape abandons the edit, and an empty commit hands the tab back to its
/// page title.
struct BrowserSidebarTabRenameField: View {
    let tab: BrowserTab
    /// The Space the row is listed in. Carried for the same reason the favicon
    /// is: renaming a tab does not release the side panel bound to it, so the
    /// icon keeps its badge while the title is being edited.
    let spaceID: SpaceID
    let profileID: UUID
    let metrics: BrowserSidebarTabRowMetrics
    var leadingInset: CGFloat = 0
    @Binding var draftTitle: String
    var isTitleFocused: FocusState<Bool>.Binding
    let commitTitle: () -> Void
    let cancelTitleEditing: () -> Void

    var body: some View {
        Label {
            TextField("Tab Name", text: $draftTitle)
                .textFieldStyle(.plain)
                .focused(isTitleFocused)
                .submitLabel(.done)
                .onSubmit(commitTitle)
                .onKeyPress(.escape) {
                    cancelTitleEditing()
                    return .handled
                }
                .accessibilityIdentifier("tab-rename-field")
        } icon: {
            BrowserSidebarTabFavicon(
                tab: tab,
                profileID: profileID,
                metrics: metrics,
                sidePanelSpaceID: spaceID
            )
        }
        .padding(.leading, leadingInset)
        .frame(
            maxWidth: .infinity,
            maxHeight: metrics.fillsRowHeight ? .infinity : nil,
            alignment: .leading
        )
    }
}
