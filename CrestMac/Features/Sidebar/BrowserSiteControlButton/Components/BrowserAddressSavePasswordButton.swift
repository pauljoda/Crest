import SwiftUI

/// The key a page keeps in the address field's trailing slot after the person
/// answered Not Now to saving its password, so they can still save it while
/// the page stays on that site.
struct BrowserAddressSavePasswordButton: View {
    let page: BrowserPage

    var body: some View {
        Button(action: page.reofferCredentialSaveCandidate) {
            Image(systemName: "key.fill")
                .font(
                    .system(
                        size: BrowserTabTrailingControlMetrics.pointer.glyphSize,
                        weight: .medium
                    )
                )
                .frame(
                    width: BrowserSiteControlMetrics.triggerSize.width,
                    height: BrowserSiteControlMetrics.triggerSize.height
                )
                .contentShape(.rect)
        }
        .buttonStyle(
            CrestChromeButtonStyle(
                controlSize: BrowserSiteControlMetrics.triggerSize
            )
        )
        .foregroundStyle(.secondary)
        .transition(.opacity.combined(with: .scale(scale: CrestMotion.entranceScale)))
        .accessibilityLabel("Save Password")
        .accessibilityIdentifier("browser-address-save-password")
        .help("Save Password")
    }
}
