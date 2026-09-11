import SwiftUI

/// App-wide visual preferences. Space branding remains in the Space editor.
///
/// Wide enough, the pane pins one live crop of the window — the sidebar and the
/// page's near edge, at real size — beside a compact form. The form keeps one
/// width so its controls stay put; the preview takes whatever the window adds.
/// Narrower, each group carries the part of the window it changes at the top
/// of its own card.
struct BrowserLookAndFeelSettingsPane: View {
    var space: BrowserSpace? = nil

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            HStack(alignment: .top, spacing: 0) {
                if BrowserLookAndFeelLayoutPolicy.mode(forWidth: width) == .pinnedPreview {
                    let columns = BrowserLookAndFeelLayoutPolicy.columns(forWidth: width)
                    BrowserLookAndFeelPreview(space: space, focus: .window, fillsHeight: true)
                        .frame(width: columns.preview)
                        .padding(.leading, BrowserLookAndFeelLayoutPolicy.previewLeadingPadding)
                        .padding(.vertical, CrestSpacing.extraLarge)
                    form(showsInlinePreviews: false)
                        .frame(width: columns.form)
                } else {
                    form(showsInlinePreviews: true)
                }
            }
            .frame(width: width, alignment: .leading)
            .browserPlatformSettingsAtmosphere()
        }
    }

    private func form(showsInlinePreviews: Bool) -> some View {
        BrowserSettingsPane(.lookAndFeel) {
            BrowserPlatformAppearanceSettingsSection(space: space, showsPreview: showsInlinePreviews)
            BrowserDefaultPageZoomSettingsSection(preferences: .shared, space: space, showsPreview: showsInlinePreviews)
            BrowserTabAppearanceGroup(space: space, showsPreview: showsInlinePreviews)
            BrowserAddressAppearanceGroup(space: space, showsPreview: showsInlinePreviews)
            BrowserFolderAppearanceGroup(space: space, showsPreview: showsInlinePreviews)
            BrowserPlatformAppIconSettingsSection()
            BrowserPlatformLookAndFeelResetSection()
        }
    }
}
