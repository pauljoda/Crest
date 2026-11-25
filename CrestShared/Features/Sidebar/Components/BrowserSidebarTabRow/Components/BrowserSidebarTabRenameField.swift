import SwiftUI

/// The tab row while its title is being edited.
///
/// Renaming happens in place, where the title already is, so the row keeps its
/// favicon and its shape and only the text becomes editable. Return commits,
/// Escape abandons the edit, and an empty commit hands the tab back to its
/// page title. The field takes the keyboard's focus as it appears, and
/// leaving it commits the edit too.
struct BrowserSidebarTabRenameField: View {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID
    let metrics: BrowserSidebarTabRowMetrics
    var leadingInset: CGFloat = 0
    @Binding var draftTitle: String
    let commitTitle: () -> Void
    let cancelTitleEditing: () -> Void

    var body: some View {
        Label {
            TextField("Tab Name", text: $draftTitle)
                .textFieldStyle(.plain)
                .browserSidebarRenameFocus(commit: commitTitle)
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
                favicons: favicons,
                profileID: profileID,
                metrics: metrics
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
