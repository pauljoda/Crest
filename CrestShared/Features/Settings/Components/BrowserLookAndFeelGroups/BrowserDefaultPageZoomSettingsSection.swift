import SwiftUI

/// The zoom every page starts at, on every Space on this device.
///
/// Both platform settings shells route through the Look and Feel pane, so this
/// one row and its reset cannot drift into duplicate controls. The slider keeps
/// the continuous multiplier, while the readout rounds to a whole percentage.
struct BrowserDefaultPageZoomSettingsSection: View {
    static let controlIdentifier = "default-page-zoom-slider"

    @Bindable var preferences: BrowserDefaultPageZoomStore
    var space: BrowserSpace? = nil
    var showsPreview = false

    var body: some View {
        CrestSettingsGroup(
            "Page",
            systemImage: "doc.text",
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
                range: zoomRange,
                readout: .multiplier,
                identifier: Self.controlIdentifier
            )
        }
    }

    private var zoomRange: ClosedRange<Double> {
        let range = BrowserPageZoomPolicy.defaultRange
        return Double(range.lowerBound)...Double(range.upperBound)
    }

    private var zoom: CrestSettingValue<Double> {
        CrestSettingValue(
            Binding(
                get: { Double(preferences.defaultZoom) },
                set: { preferences.defaultZoom = CGFloat($0) }
            ),
            default: Double(BrowserPageZoomPolicy.defaultLevel)
        )
    }
}
