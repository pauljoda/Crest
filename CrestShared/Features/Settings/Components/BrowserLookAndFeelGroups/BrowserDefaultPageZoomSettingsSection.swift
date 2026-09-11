import SwiftUI

/// The zoom every page starts at, on every Space on this device.
///
/// Both platform settings shells route through the Look and Feel pane, so this
/// one row and its reset cannot drift into duplicate controls. The slider walks
/// the same discrete levels the Page Zoom commands do, and the pinned window
/// crop's sample page grows and shrinks with it.
struct BrowserDefaultPageZoomSettingsSection: View {
    static let controlIdentifier = "default-page-zoom-slider"

    @Bindable var preferences: BrowserDefaultPageZoomStore
    var space: BrowserSpace? = nil
    var showsPreview = false

    var body: some View {
        CrestSettingsGroup(
            "Page",
            settings: [zoom.resettable("Default page zoom")],
            footnote:
                "Pages using the default update immediately. Page Zoom commands override it while you browse, and Actual Size returns here."
        ) {
            if showsPreview {
                BrowserLookAndFeelPreview(space: space, focus: .page)
            }
        } content: {
            CrestSettingSlider(
                "Default page zoom",
                value: zoom,
                range: 0...Double(BrowserPageZoomPolicy.levels.count - 1),
                step: 1,
                readout: CrestSettingSliderReadout { index in
                    BrowserPageZoomPolicy.percentageLabel(for: BrowserPageZoomPolicy.level(atIndex: index))
                },
                identifier: Self.controlIdentifier
            )
        }
    }

    private var zoom: CrestSettingValue<Double> {
        CrestSettingValue($preferences.defaultZoomLevelIndex, default: BrowserPageZoomPolicy.defaultLevelIndex)
    }
}
