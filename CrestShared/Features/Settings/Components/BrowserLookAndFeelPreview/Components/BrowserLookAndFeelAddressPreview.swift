import SwiftUI

/// The shipping address field on this Space's atmosphere, holding a friendly
/// sample rather than whatever is open behind the settings window.
struct BrowserLookAndFeelAddressPreview: View {
    var space: BrowserSpace?
    var showsBackground = true

    @Namespace private var namespace

    var body: some View {
        if showsBackground {
            field
                .padding(CrestSpacing.medium)
                .frame(maxWidth: .infinity)
                .background { BrowserSpaceBannerBackground(branding: branding) }
                .clipShape(.rect(cornerRadius: BrowserLookAndFeelPreviewMetrics.cardCornerRadius))
                .environment(\.colorScheme, BrowserSpaceForegroundPolicy.colorScheme(for: branding))
        } else {
            field
        }
    }

    private var field: some View {
        BrowserSidebarAddressField(
            configuration: .init(
                text: .constant(BrowserLookAndFeelPreviewMetrics.sampleAddress),
                isEditing: .constant(false),
                isSecure: true,
                progress: 0,
                isLoading: false,
                capabilities: .init(
                    supportsTouch: BrowserSidebarDensityPolicy.usesTouch,
                    pairsRowWithPromotedSurface: false),
                activate: {},
                submit: {},
                morphNamespace: namespace,
                morphID: "look-and-feel-address-preview",
                branding: branding)
        )
        .labelsHidden()
        .frame(maxWidth: BrowserChromeLayout.sidebarMaximumWidth)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Address field preview")
        .accessibilityValue(BrowserLookAndFeelPreviewMetrics.sampleAddress)
    }

    private var branding: BrowserSpaceBranding {
        space?.branding ?? .house(.winter, symbol: "paintpalette")
    }
}
