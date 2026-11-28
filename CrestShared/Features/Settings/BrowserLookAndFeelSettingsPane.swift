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
            BrowserSettingsSectionSlot(.addressBar) { BrowserPlatformAddressBarSettingsSection() }
            groups(.page, showsInlinePreviews: showsInlinePreviews)
            BrowserSettingsSectionSlot(.appIcon) { BrowserPlatformAppIconSettingsSection() }
            BrowserSettingsSectionSlot(.moreCustomization) { BrowserMoreCustomizationHeader(isExpanded: $showsMore) }
            if showsMore {
                groups(.more, showsInlinePreviews: showsInlinePreviews)
            }
            BrowserSettingsSectionSlot(.resetAppearance) { BrowserPlatformLookAndFeelResetSection() }
        }
    }

    /// Every group whose rows may wait in More Customization, each showing
    /// the rows `filter`'s part of the page keeps. A search result scrolls to
    /// the group on the page, not to its rows in More Customization.
    private func groups(
        _ filter: BrowserAppearanceSettingFilter, showsInlinePreviews: Bool
    ) -> BrowserSettingsSectionList<some View> {
        let anchors = !filter.isMore
        return BrowserSettingsSectionList {
            // A group with no rows for this part of the page stays out of the
            // form here, as an empty section would add a gap. On the page
            // itself, where search results scroll to them, both always show.
            if BrowserSpaceIconsAppearanceGroup.hasRows(in: filter) {
                BrowserSettingsSectionSlot(.spaceIcons, anchors: anchors) {
                    BrowserSpaceIconsAppearanceGroup()
                        .environment(\.browserAppearanceSettingFilter, filter)
                }
            }
            BrowserSettingsSectionSlot(.windowAppearance, anchors: anchors) {
                BrowserPlatformAppearanceSettingsSection(space: space, showsPreview: showsInlinePreviews)
                    .environment(\.browserAppearanceSettingFilter, filter)
            }
            if !usesLiveSidebar, BrowserDefaultPageZoomSettingsSection.hasRows(in: filter) {
                BrowserSettingsSectionSlot(.pageZoom, anchors: anchors) {
                    BrowserDefaultPageZoomSettingsSection(
                        preferences: .shared, space: space, showsPreview: showsInlinePreviews
                    )
                    .environment(\.browserAppearanceSettingFilter, filter)
                }
            }
            BrowserSettingsSectionSlot(.tabAppearance, anchors: anchors) {
                BrowserTabAppearanceGroup(space: space, showsPreview: showsInlinePreviews)
                    .environment(\.browserAppearanceSettingFilter, filter)
            }
            BrowserSettingsSectionSlot(.tabStatus, anchors: anchors) {
                BrowserTabStatusAppearanceGroup()
                    .environment(\.browserAppearanceSettingFilter, filter)
            }
            BrowserSettingsSectionSlot(.addressAppearance, anchors: anchors) {
                BrowserAddressAppearanceGroup(
                    space: space, showsPreview: showsInlinePreviews, links: browser.linkPreferences
                )
                .environment(\.browserAppearanceSettingFilter, filter)
            }
            BrowserSettingsSectionSlot(.folderAppearance, anchors: anchors) {
                BrowserFolderAppearanceGroup(space: space, showsPreview: showsInlinePreviews)
                    .environment(\.browserAppearanceSettingFilter, filter)
            }
            BrowserSettingsSectionSlot(.groupAppearance, anchors: anchors) {
                BrowserGroupAppearanceGroup()
                    .environment(\.browserAppearanceSettingFilter, filter)
            }
            BrowserSettingsSectionSlot(.hoverPreviews, anchors: anchors) {
                BrowserHoverPreviewAppearanceGroup()
                    .environment(\.browserAppearanceSettingFilter, filter)
            }
            if usesLiveSidebar, BrowserDefaultPageZoomSettingsSection.hasRows(in: filter) {
                BrowserSettingsSectionSlot(.pageZoom, anchors: anchors) {
                    BrowserDefaultPageZoomSettingsSection(preferences: .shared, space: space, showsPreview: false)
                        .environment(\.browserAppearanceSettingFilter, filter)
                }
            }
        }
    }
}
