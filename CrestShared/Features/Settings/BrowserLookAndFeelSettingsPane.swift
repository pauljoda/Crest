import SwiftUI

/// Device appearance edits the visible sidebar in a browser tab. Sheets retain
/// detached component previews because their browser is covered.
///
/// The customization style leads the page and decides which rows follow it;
/// the rows it leaves out wait in Advanced at the end.
struct BrowserLookAndFeelSettingsPane: View {
    let browser: BrowserStore
    var space: BrowserSpaceAppearance? = nil
    @Environment(\.browserSettingsUsesLiveSidebar) private var usesLiveSidebar
    @State private var showsAdvanced = false
    private let appearance = BrowserDeviceAppearanceStore.shared

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
        let style = appearance.customizationStyle
        return BrowserSettingsPane(.lookAndFeel) {
            BrowserCustomizationStyleGroup(browser: browser)
            Group {
                BrowserSpaceIconsAppearanceGroup()
                groups(showsInlinePreviews: showsInlinePreviews)
            }
            .environment(
                \.browserAppearanceSettingFilter, BrowserAppearanceSettingFilter(style: style, isAdvanced: false))
            BrowserPlatformAppIconSettingsSection()
            if style.hidesSettings {
                BrowserAppearanceAdvancedHeader(isExpanded: $showsAdvanced)
                if showsAdvanced {
                    Group {
                        BrowserSpaceIconsAppearanceGroup()
                        groups(showsInlinePreviews: showsInlinePreviews)
                    }
                    .environment(
                        \.browserAppearanceSettingFilter,
                        BrowserAppearanceSettingFilter(style: style, isAdvanced: true))
                }
            }
            BrowserPlatformLookAndFeelResetSection()
        }
    }

    /// Every group whose rows a style can leave out, each showing the rows
    /// the page's filter keeps.
    @ViewBuilder private func groups(showsInlinePreviews: Bool) -> some View {
        BrowserPlatformAppearanceSettingsSection(space: space, showsPreview: showsInlinePreviews)
        if !usesLiveSidebar {
            BrowserDefaultPageZoomSettingsSection(
                preferences: .shared, space: space, showsPreview: showsInlinePreviews)
        }
        BrowserTabAppearanceGroup(space: space, showsPreview: showsInlinePreviews)
        BrowserTabStatusAppearanceGroup()
        BrowserAddressAppearanceGroup(space: space, showsPreview: showsInlinePreviews)
        BrowserFolderAppearanceGroup(space: space, showsPreview: showsInlinePreviews)
        if usesLiveSidebar {
            BrowserDefaultPageZoomSettingsSection(preferences: .shared, space: space, showsPreview: false)
        }
    }
}
