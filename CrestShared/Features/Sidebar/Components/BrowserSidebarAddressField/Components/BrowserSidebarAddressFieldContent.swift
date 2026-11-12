import SwiftUI

/// The single row inside the address field: leading glyph or site control, the
/// address itself, the clear control, and the trailing site control.
struct BrowserSidebarAddressFieldContent<
    LeadingAccessory: View,
    TrailingAccessory: View
>: View {
    let configuration: BrowserSidebarAddressFieldConfiguration
    private let leadingAccessory: LeadingAccessory
    private let trailingAccessory: TrailingAccessory

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        configuration: BrowserSidebarAddressFieldConfiguration,
        @ViewBuilder leadingAccessory: () -> LeadingAccessory,
        @ViewBuilder trailingAccessory: () -> TrailingAccessory
    ) {
        self.configuration = configuration
        self.leadingAccessory = leadingAccessory()
        self.trailingAccessory = trailingAccessory()
    }

    var body: some View {
        // The field stays put as it shows another Space: the address and
        // the site's controls pop out and the new Space's pop in, unless
        // both Spaces show only the prompt.
        HStack(spacing: configuration.metrics.contentSpacing) {
            if configuration.showsLeadingAccessory || configuration.showsPlaceholderGlyph {
                BrowserAddressSwap(swapID: configuration.swapID) { leadingControl }
            }

            BrowserAddressContent(
                text: configuration.text,
                isEditing: configuration.isEditing,
                focusRequest: configuration.focusRequest,
                activate: configuration.activate,
                editorAccessibilityLabel: configuration
                    .addressAccessibilityLabel,
                editorAccessibilityIdentifier: configuration
                    .addressAccessibilityIdentifier,
                summaryAccessibilityIdentifier: configuration
                    .addressDisplayAccessibilityIdentifier,
                prompt: configuration.prompt,
                swapID: configuration.swapID,
                display: BrowserDeviceAppearanceStore.shared.address.display,
                submit: configuration.submit
            )

            if configuration.showsClearControl {
                BrowserSidebarAddressClearButton(
                    text: configuration.text,
                    font: configuration.metrics.clearControlFont
                )
            }

            if configuration.showsTrailingAccessory {
                // A row of its own: the swap stacks what it holds in one
                // place, which would draw two controls over each other.
                BrowserAddressSwap(swapID: configuration.swapID) {
                    HStack(spacing: configuration.metrics.accessorySpacing) { trailingAccessory }
                }
            }
        }
        // The site's controls can follow the Space a moment later, once its
        // page is ready. They pop with the address's timing, and it moves
        // aside for them as smoothly.
        .animation(siteControlsAnimation, value: configuration.hasActiveSite)
        .animation(CrestMotion.addressSwap.unlessReducingMotion(reduceMotion), value: configuration.swapID)
    }

    /// The site's controls popping in as the address does, or out as the
    /// old address does.
    private var siteControlsAnimation: Animation? {
        let animation = configuration.hasActiveSite ? CrestMotion.addressSwapIn : CrestMotion.addressSwapOut
        return animation.unlessReducingMotion(reduceMotion)
    }

    @ViewBuilder
    private var leadingControl: some View {
        if configuration.showsLeadingAccessory {
            leadingAccessory
        } else if configuration.showsPlaceholderGlyph {
            BrowserSidebarAddressPlaceholderGlyph(
                isSecure: configuration.isSecure,
                metrics: configuration.metrics
            )
        }
    }
}
