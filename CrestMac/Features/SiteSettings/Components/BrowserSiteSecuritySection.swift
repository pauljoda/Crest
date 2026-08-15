import SwiftUI

struct BrowserSiteSecuritySection: View {
    let page: BrowserPage
    let origin: BrowserSiteOrigin
    var reviewCertificate: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.small) {
            Text(origin.displayName)
                .font(.caption.monospaced())
                .lineLimit(1)
            if canReviewCertificate {
                Button(action: presentCertificate) {
                    HStack(spacing: CrestSpacing.small) {
                        securityLabel
                        Spacer(minLength: CrestSpacing.small)
                        Text("Certificate")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Review Certificate")
                .accessibilityLabel("Review Certificate")
            } else {
                securityLabel
            }
        }
    }

    private var canReviewCertificate: Bool {
        BrowserSiteCertificatePresentationPolicy.isAvailable(
            url: page.displayURL,
            hasServerTrust: page.webView.serverTrust != nil
        )
    }

    private var securityLabel: some View {
        Label(
            page.hasOnlySecureContent ? "Secure" : "Not Secure",
            systemImage: page.hasOnlySecureContent
                ? "lock.fill"
                : "lock.open.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(page.hasOnlySecureContent ? .green : .orange)
    }

    private func presentCertificate() {
        if let reviewCertificate {
            reviewCertificate()
            return
        }
        guard let trust = page.webView.serverTrust else { return }
        BrowserSiteCertificatePresenter.present(
            trust: trust,
            for: page.webView.window
        )
    }
}

#Preview("Site Security") {
    let preview = BrowserSiteSettingsPreviewFixture.makePage()
    BrowserSiteSecuritySection(
        page: preview.page,
        origin: BrowserSiteSettingsPreviewFixture.origin
    )
    .padding()
    .frame(width: 300)
}
