import SwiftUI

/// The offer to keep an address or card a form was just sent with: "Save
/// card?" or "Save address?", what it is, and Save or Not Now. It grows from
/// the page's top leading corner like the password save card, and steps aside
/// when the person already keeps the same one.
struct BrowserAutofillSavePrompt: View {
    let candidate: BrowserAutofillSaveCandidate
    let port: BrowserCredentialSavePort
    let browser: BrowserStore
    let metrics: BrowserCredentialPromptMetrics

    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        BrowserCredentialPromptSurface(
            accessibilityLabel: Text(title),
            accessibilityIdentifier: "crest-autofill-save",
            width: metrics.savePromptWidth,
            metrics: metrics
        ) {
            VStack(alignment: .leading, spacing: BrowserCredentialPromptMetrics.savePromptContentSpacing) {
                HStack(alignment: .top, spacing: BrowserCredentialPromptMetrics.headerSpacing) {
                    CrestIconTile(
                        systemImage: candidate.card != nil ? "creditcard.fill" : "house.fill",
                        color: CrestBrandTheme.accent, size: BrowserCredentialPromptMetrics.headerIdentitySize,
                        symbolSize: BrowserCredentialPromptMetrics.headerIdentitySymbolSize
                    )
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: BrowserCredentialPromptMetrics.headerTextSpacing) {
                        Text(title).font(CrestTypography.display(15, relativeTo: .headline))
                        Text(verbatim: detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                if let errorMessage {
                    BrowserCredentialPromptError(verbatim: errorMessage)
                }
                HStack(spacing: BrowserCredentialPromptMetrics.saveActionSpacing) {
                    Text("Shared with all Spaces")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: BrowserCredentialPromptMetrics.saveHeaderSpacerLength)
                    Button("Not Now", action: port.dismissAutofill)
                        .buttonStyle(.crestSecondary)
                        .disabled(isSaving)
                    Button("Save", action: save)
                        .buttonStyle(.crestPrimary)
                        .disabled(isSaving)
                        .accessibilityIdentifier("crest-autofill-save-button")
                }
            }
        }
        .task(id: candidate.id) {
            // A card or address already kept asks nothing.
            if await browser.autofillSaveCandidate(alreadyKept: candidate) { port.dismissAutofill() }
        }
    }

    private var title: LocalizedStringKey {
        candidate.card != nil ? "Save card?" : "Save address?"
    }

    private var detail: String {
        if let card = candidate.card {
            let summary = browser.cardDetails(card.number)
            return [
                summary.map { "\(String(localized: $0.network.displayName)) ·••• \($0.lastFour)" },
                card.cardholder.nilIfEmpty, String(format: "%02d/%02d", card.expiryMonth, card.expiryYear % 100),
            ].compactMap(\.self).joined(separator: " · ")
        }
        return candidate.address?.oneLine ?? ""
    }

    private func save() {
        Task { @MainActor in
            isSaving = true
            defer { isSaving = false }
            do {
                if let address = candidate.address {
                    var labeled = address
                    if labeled.label.isEmpty { labeled.label = String(localized: "Address") }
                    try await browser.saveAddress(labeled)
                }
                if let card = candidate.card { try await browser.saveCard(card) }
                port.dismissAutofill()
                BrowserNoticeCenter.shared.post(candidate.card != nil ? .cardSaved : .addressSaved)
            } catch {
                errorMessage = String(localized: "Crest couldn’t save this.")
            }
        }
    }
}
