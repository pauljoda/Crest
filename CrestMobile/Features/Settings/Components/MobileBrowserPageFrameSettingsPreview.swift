import SwiftUI

struct MobileBrowserPageFrameSettingsPreview: View {
    let isEnabled: Bool

    private var isBorderless: Bool {
        MobileSidebarPageFramePolicy.usesBorderlessFrame(
            preferenceIsEnabled: isEnabled,
            sidebarPresentation: .floating,
            presentsSplitView: false,
            browserPresentation: .regular)
    }

    var body: some View {
        BrowserSettingsPagePreview()
            .clipShape(.rect(cornerRadius: isBorderless ? 0 : 8))
            .padding(isBorderless ? 0 : 8)
            .background { BrowserSpaceBannerBackground(branding: .init(colors: [.ink, .ocean, .gold])) }
            .clipShape(.rect(cornerRadius: 12))
            .frame(maxWidth: 340)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Undocked sidebar page preview")
            .accessibilityValue(isBorderless ? "Borderless" : "Themed border")
            .accessibilityIdentifier("collapsed-sidebar-frame-preview")
    }
}
