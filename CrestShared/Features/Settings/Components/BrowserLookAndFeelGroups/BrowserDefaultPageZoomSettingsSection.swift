import SwiftUI

/// The zoom every page starts at, on every Space on this device.
///
/// Both platform settings shells route through the Appearance pane, so this
/// one row and its reset cannot drift into duplicate controls. The menu offers
/// the zoom levels the page zoom commands step through, plus a level saved
/// before the menu existed.
struct BrowserDefaultPageZoomSettingsSection: View {
    static let controlIdentifier = "default-page-zoom-slider"

    @Bindable var preferences: BrowserDefaultPageZoomStore
    var space: BrowserSpaceAppearance? = nil
    var showsPreview = false

    @Environment(\.browserAppearanceSettingFilter) private var filter

    /// Whether the group has rows for `filter`'s part of the page.
    static func hasRows(in filter: BrowserAppearanceSettingFilter) -> Bool {
        filter.shows(.defaultPageZoom)
    }

    var body: some View {
        // Drawn even with nothing to show, as an empty section, so a search
        // result can still scroll to it and to the groups after it.
        group
    }

    private var group: some View {
        CrestSettingsGroup(
            "Page",
            settings: [zoom.resettable("Default page zoom")],
            isShown: Self.hasRows(in: filter)
        ) {
            if showsPreview {
                BrowserLookAndFeelPreview(space: space, focus: .page)
            }
        } content: {
            CrestSettingRow("Default page zoom", setting: zoom.resettable("Default page zoom")) {
                Picker("Default page zoom", selection: zoom.binding) {
                    ForEach(levels, id: \.self) { level in
                        Text(CGFloat(level).pageZoomPercentage).tag(level)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier(Self.controlIdentifier)
            }
            .browserAppearanceSetting(.defaultPageZoom)
        }
    }

    /// The zoom levels, with the saved level among them.
    private var levels: [Double] {
        let levels = CGFloat.pageZoomLevels.map(Double.init)
        let saved = zoom.wrappedValue
        guard !levels.contains(where: { CGFloat($0).matchesPageZoom(CGFloat(saved)) }) else {
            return levels
        }
        return (levels + [saved]).sorted()
    }

    private var zoom: CrestSettingValue<Double> {
        CrestSettingValue(
            Binding(
                get: { levelMatching(preferences.defaultZoom) },
                set: { preferences.defaultZoom = CGFloat($0) }
            ),
            default: Double(BrowserDefaultPageZoomStore.defaultLevel)
        )
    }

    /// The menu's level for a stored zoom that differs from it by rounding.
    private func levelMatching(_ zoom: CGFloat) -> Double {
        CGFloat.pageZoomLevels.first { $0.matchesPageZoom(zoom) }.map(Double.init)
            ?? Double(zoom)
    }
}
