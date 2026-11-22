import SwiftUI

/// Device appearance edits the visible sidebar in a browser tab. Sheets retain
/// detached component previews because their browser is covered.
///
/// The page keeps the choices that change how Crest reads and behaves; the
/// fine tuning waits in More Customization at the end.
struct BrowserLookAndFeelSettingsPane: View {
    let browser: BrowserStore
    var space: BrowserSpaceAppearance? = nil
    @Environment(\.browserSettingsUsesLiveSidebar) private var usesLiveSidebar
    @State private var showsMore = false

    var body: some View {
        if usesLiveSidebar {
            // The page beside the live sidebar changes size as the window
            // border is dragged, so it measures nothing that would rebuild the
            // form on every step.
            form(showsInlinePreviews: false)
                .frame(maxWidth: .infinity)
        } else {
            columns
        }
    }

    /// The pinned preview beside the form where the pane has room for both,
    /// or previews in each group where it does not.
    private var columns: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            HStack(alignment: .top, spacing: 0) {
                if let columns = BrowserLookAndFeelColumns(width: width) {
                    BrowserLookAndFeelPreview(space: space, focus: .window, fillsHeight: true)
                        .frame(width: columns.preview)
                        .padding(.leading, BrowserLookAndFeelColumns.previewLeadingPadding)
                        .padding(.vertical, CrestSpacing.extraLarge)
                    form(showsInlinePreviews: false)
                        .frame(width: columns.form)
                } else {
                    form(showsInlinePreviews: true)
                }
            }
            .frame(width: width, alignment: .leading)
        }
    }

    private func form(showsInlinePreviews: Bool) -> some View {
        BrowserSettingsPane(.lookAndFeel) {
            BrowserPlatformAddressBarSettingsSection()
            Group {
                BrowserSpaceIconsAppearanceGroup()
                groups(showsInlinePreviews: showsInlinePreviews)
            }
            .environment(\.browserAppearanceSettingFilter, .page)
            BrowserPlatformAppIconSettingsSection()
            BrowserMoreCustomizationHeader(isExpanded: $showsMore)
            if showsMore {
                Group {
                    BrowserSpaceIconsAppearanceGroup()
                    groups(showsInlinePreviews: showsInlinePreviews)
                }
                .environment(\.browserAppearanceSettingFilter, .more)
            }
            BrowserPlatformLookAndFeelResetSection()
        }
    }

    /// Every group whose rows may wait in More Customization, each showing
    /// the rows its part of the page keeps.
    @ViewBuilder private func groups(showsInlinePreviews: Bool) -> some View {
        BrowserPlatformAppearanceSettingsSection(space: space, showsPreview: showsInlinePreviews)
        if !usesLiveSidebar {
            BrowserDefaultPageZoomSettingsSection(
                preferences: .shared, space: space, showsPreview: showsInlinePreviews)
        }
        BrowserTabAppearanceGroup(space: space, showsPreview: showsInlinePreviews)
        BrowserTabStatusAppearanceGroup()
        BrowserAddressAppearanceGroup(space: space, showsPreview: showsInlinePreviews, links: browser.linkPreferences)
        BrowserFolderAppearanceGroup(space: space, showsPreview: showsInlinePreviews)
        BrowserGroupAppearanceGroup()
        BrowserHoverPreviewAppearanceGroup()
        if usesLiveSidebar {
            BrowserDefaultPageZoomSettingsSection(preferences: .shared, space: space, showsPreview: false)
        }
    }
}
