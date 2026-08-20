import SwiftUI

/// The certificate affordance a live site puts in the address field's leading
/// slot.
///
/// It stays on the windowed shell because it reads a `BrowserPage`'s server
/// trust and hands it to a platform certificate panel — neither of which the
/// compact shell has.
struct BrowserAddressSecurityButton: View {
    let page: BrowserPage
    let isSecure: Bool

    var body: some View {
        Button(action: reviewCertificate) {
            BrowserAddressSecurityIcon(isSecure: isSecure)
        }
        .buttonStyle(buttonStyle)
        .foregroundStyle(
            isSecure ? Color(nsColor: .secondaryLabelColor) : Color.orange
        )
        .disabled(!canReviewCertificate)
        .accessibilityLabel(
            canReviewCertificate ? "Review Certificate" : "Connection Not Secure"
        )
        .accessibilityIdentifier("browser-address-security")
        .help(canReviewCertificate ? "Review Certificate" : "Connection Not Secure")
    }

    private var buttonStyle: CrestChromeButtonStyle {
        CrestChromeButtonStyle(
            controlSize: CGSize(
                width: BrowserAddressSecurityControlPolicy.controlSize,
                height: BrowserAddressSecurityControlPolicy.controlSize
            )
        )
    }

    private var canReviewCertificate: Bool {
        BrowserSiteCertificatePresentationPolicy.isAvailable(
            url: page.displayURL,
            hasServerTrust: page.webView.serverTrust != nil
        )
    }

    private func reviewCertificate() {
        guard let trust = page.webView.serverTrust else { return }
        BrowserSiteCertificatePresenter.present(
            trust: trust,
            for: page.webView.window
        )
    }
}

private struct BrowserAddressSecurityIcon: View {
    let isSecure: Bool

    var body: some View {
        Image(systemName: isSecure ? "lock.fill" : "lock.open.fill")
            .font(
                .system(
                    size: BrowserTabTrailingControlPolicy.glyphSize,
                    weight: .medium
                )
            )
            .frame(
                width: BrowserAddressSecurityControlPolicy.controlSize,
                height: BrowserAddressSecurityControlPolicy.controlSize
            )
            .contentShape(.rect)
    }
}
