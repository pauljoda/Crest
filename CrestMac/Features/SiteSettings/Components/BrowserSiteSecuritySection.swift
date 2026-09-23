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
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var canReviewCertificate: Bool {
        page.canReviewCertificate
    }

    /// An HTTPS page the engine judged secure but whose verified trust it could
    /// not hand over. Without a certificate to show, the page is not called
    /// secure; the engine's warnings for other states still stand.
    private var isUnconfirmedSecure: Bool {
        page.securityState == .secure
            && page.displayURL?.scheme?.lowercased() == "https"
            && !canReviewCertificate
    }

    private var securityLabel: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
    }

    private var title: LocalizedStringKey {
        if isUnconfirmedSecure { return "Connection Details Unavailable" }
        return switch page.securityState {
        case .secure: "Secure"
        case .mixedContent: "Partly Secure"
        case .certificateError: "Certificate Not Trusted"
        case .dangerous: "Dangerous Site"
        case .insecure, .none: "Not Secure"
        }
    }

    private var symbol: String {
        if isUnconfirmedSecure { return "lock" }
        return switch page.securityState {
        case .secure: "lock.fill"
        case .mixedContent: "lock.trianglebadge.exclamationmark.fill"
        case .certificateError: "exclamationmark.lock.fill"
        case .dangerous: "exclamationmark.octagon.fill"
        case .insecure, .none: "lock.open.fill"
        }
    }

    private var tint: Color {
        if isUnconfirmedSecure { return .secondary }
        return switch page.securityState {
        case .secure: .green
        case .mixedContent, .insecure, .none: .orange
        case .certificateError, .dangerous: .red
        }
    }

    private var detail: LocalizedStringKey? {
        switch page.securityState {
        case .mixedContent:
            "Some content on this page was not delivered securely."
        case .certificateError:
            "This site’s certificate is not trusted. Information you send could be read by others."
        case .dangerous:
            "This site may try to harm your Mac or steal your information."
        case .secure, .insecure, .none:
            nil
        }
    }

    private func presentCertificate() {
        if let reviewCertificate {
            reviewCertificate()
            return
        }
        page.reviewCertificate()
    }
}
