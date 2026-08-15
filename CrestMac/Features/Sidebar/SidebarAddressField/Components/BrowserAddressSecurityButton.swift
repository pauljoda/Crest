import SwiftUI

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

#Preview {
    BrowserAddressSecurityButton(
        page: SidebarAddressFieldPreviewFixture.makeSiteControl().page,
        isSecure: true
    )
    .padding()
}
