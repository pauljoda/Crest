import SwiftUI

/// The link button a live site puts in the address field's trailing slot, beside
/// Site Controls, when the person turned it on in Appearance.
struct BrowserAddressCopyURLButton: View {
    let page: BrowserPage

    var body: some View {
        Button(action: copy) {
            Image(systemName: "link")
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
        .accessibilityLabel("Copy URL")
        .accessibilityIdentifier("browser-address-copy-url")
        .help("Copy URL")
    }

    private func copy() {
        guard page.copyPageLink() else { return }
        BrowserNoticeCenter.shared.post(.urlCopied)
    }
}
