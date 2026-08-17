import SwiftUI

struct SidebarAddressFieldConfiguration {
    let text: Binding<String>
    let isEditing: Binding<Bool>
    let focusRequest: Int
    let isSecure: Bool
    let hasResidentPage: Bool
    let activate: (() -> Void)?
    let submit: () -> Void
    let siteControl: BrowserSiteControlConfiguration?
    let addressAccessibilityLabel: LocalizedStringKey
    let addressAccessibilityIdentifier: String
    let addressDisplayAccessibilityIdentifier: String
    let prompt: LocalizedStringKey
}

struct SidebarAddressFieldContent: View {
    let configuration: SidebarAddressFieldConfiguration

    var body: some View {
        HStack(spacing: 7) {
            BrowserAddressLeadingControl(configuration: configuration)
            BrowserAddressEditor(configuration: configuration)

            if BrowserSiteControlPresentationPolicy.isVisible(
                isAddressEditing: configuration.isEditing.wrappedValue,
                hasActiveSite: configuration.siteControl != nil
            ), let siteControl = configuration.siteControl {
                BrowserSiteControlButton(configuration: siteControl)
            }
        }
    }
}

private struct BrowserAddressEditor: View {
    let configuration: SidebarAddressFieldConfiguration

    var body: some View {
        Group {
            BrowserAddressContent(
                text: configuration.text,
                isEditing: configuration.isEditing,
                focusRequest: configuration.focusRequest,
                activate: configuration.activate,
                editorAccessibilityLabel: configuration.addressAccessibilityLabel,
                editorAccessibilityIdentifier: configuration.addressAccessibilityIdentifier,
                summaryAccessibilityIdentifier: configuration.addressDisplayAccessibilityIdentifier,
                prompt: configuration.prompt,
                submit: configuration.submit
            )

            if configuration.isEditing.wrappedValue,
                !configuration.text.wrappedValue.isEmpty
            {
                BrowserAddressClearButton(text: configuration.text)
            }
        }
    }
}

private struct BrowserAddressClearButton: View {
    @Binding var text: String

    var body: some View {
        Button("Clear", systemImage: "xmark.circle.fill") {
            text = ""
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(.tertiary)
    }
}

private struct BrowserAddressLeadingControl: View {
    let configuration: SidebarAddressFieldConfiguration

    @ViewBuilder
    var body: some View {
        if BrowserAddressSecurityControlPolicy.isVisible(
            isAddressEditing: configuration.isEditing.wrappedValue,
            hasActiveSite: configuration.siteControl != nil
        ), let siteControl = configuration.siteControl {
            BrowserAddressSecurityButton(
                page: siteControl.page,
                isSecure: configuration.isSecure
            )
        } else if BrowserAddressLeadingControlPolicy.showsPlaceholderGlyph(
            isAddressEditing: configuration.isEditing.wrappedValue,
            hasActiveSite: configuration.siteControl != nil,
            hasResidentPage: configuration.hasResidentPage
        ) {
            BrowserAddressPlaceholderGlyph(isSecure: configuration.isSecure)
        }
    }
}

private struct BrowserAddressPlaceholderGlyph: View {
    let isSecure: Bool

    var body: some View {
        Image(systemName: isSecure ? "lock.fill" : "magnifyingglass")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(
                width: BrowserAddressSecurityControlPolicy.controlSize,
                height: BrowserAddressSecurityControlPolicy.controlSize
            )
            .accessibilityHidden(true)
    }
}

private struct BrowserAddressSecurityButton: View {
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

enum BrowserAddressLeadingControlPolicy {
    static func showsPlaceholderGlyph(
        isAddressEditing: Bool,
        hasActiveSite: Bool,
        hasResidentPage: Bool
    ) -> Bool {
        guard
            !BrowserAddressSecurityControlPolicy.isVisible(
                isAddressEditing: isAddressEditing,
                hasActiveSite: hasActiveSite
            )
        else {
            return false
        }
        return isAddressEditing || hasResidentPage
    }
}

enum BrowserAddressSecurityControlPolicy {
    static let controlSize = BrowserTabTrailingControlPolicy.minimumHitTarget

    static func isVisible(
        isAddressEditing: Bool,
        hasActiveSite: Bool
    ) -> Bool {
        !isAddressEditing && hasActiveSite
    }
}
