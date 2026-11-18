import SwiftUI

/// Where the windows show a page's address, as one preview button for each
/// place: a Crest window with the field in its sidebar,
/// or with the bar along the top of its page card. The choice is this
/// device's, for every Space and window.
struct BrowserPlatformAddressBarSettingsSection: View {
    // MARK: - Variables

    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let placement = CrestSettingValue(
            $appearance.addressBarPlacement, default: BrowserLookAndFeelDefaults.addressBarPlacement)
        let resettable = CrestResettableSetting(title: "Address bar", isDefault: placement.isDefault) {
            choose(BrowserLookAndFeelDefaults.addressBarPlacement)
        }
        CrestSettingsGroup("Address bar", settings: [resettable]) {
            HStack(alignment: .top, spacing: BrowserAppearancePreviewMetrics.spacing) {
                ForEach(BrowserAddressBarPlacement.all) { candidate in
                    CrestPreviewButton(
                        title: Text(candidate.title), isSelected: candidate == appearance.addressBarPlacement,
                        previewSize: BrowserAppearancePreviewMetrics.previewSize
                    ) {
                        choose(candidate)
                    } preview: {
                        BrowserOnboardingWindowPreview(
                            branding: look.previewBranding, symbol: look.previewSymbol,
                            name: String(localized: "Personal"),
                            spaceIcons: appearance.spaceIcons,
                            companionLook: look,
                            addressBarPlacement: candidate
                        ) {
                            EmptyView()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("address-bar-placement")
        }
    }

    /// The look both previews wear: a house's, as a new Space's is.
    private var look: SetupLook { .heraldic }

    // MARK: - Actions - Choice

    private func choose(_ placement: BrowserAddressBarPlacement) {
        withAnimation(CrestMotion.chrome.unlessReducingMotion(reduceMotion)) {
            appearance.addressBarPlacement = placement
        }
    }
}
