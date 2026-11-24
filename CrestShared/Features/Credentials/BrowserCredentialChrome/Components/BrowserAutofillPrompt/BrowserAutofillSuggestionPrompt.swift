import SwiftUI

// MARK: - Types

/// One of the person's addresses or cards, as the popup lists it.
struct BrowserAutofillSuggestion: Identifiable, Equatable {
    let id: UUID
    let title: String
    let detail: String
    let systemImage: String
}

/// The popup under a field of an address or card section: the person's
/// addresses or cards, shared by every Space. Choosing one fills the whole
/// section the core read; a card asks for Touch ID or the device password
/// first, every time. It shows only when the person has saved one.
struct BrowserAutofillSuggestionPrompt: View {
    let request: BrowserCredentialFillRequest
    let offer: BrowserAutofillOffer
    let port: BrowserCredentialFillPort
    let browser: BrowserStore
    let metrics: BrowserCredentialPromptMetrics

    @State private var suggestions: [BrowserAutofillSuggestion]?
    @State private var addresses: [UUID: AddressRecord] = [:]
    @State private var selectedID: UUID?
    @State private var errorMessage: String?
    @State private var isFilling = false

    var body: some View {
        // A zero-size anchor keeps the view on screen while it loads, so its
        // task runs: SwiftUI runs no task on a view with nothing in it.
        ZStack {
            Color.clear.frame(width: 0, height: 0)
            if let suggestions, !suggestions.isEmpty {
                BrowserCredentialPromptSurface(
                    accessibilityLabel: Text(offer.takesCard ? "Crest payment cards" : "Crest addresses"),
                    accessibilityIdentifier: offer.takesCard ? "crest-card-suggestions" : "crest-address-suggestions",
                    width: metrics.fillPromptWidth,
                    metrics: metrics
                ) {
                    VStack(alignment: .leading, spacing: BrowserCredentialPromptMetrics.contentSpacing) {
                        VStack(spacing: 0) {
                            ForEach(suggestions) { suggestion in
                                row(suggestion)
                            }
                        }
                        if let errorMessage {
                            BrowserCredentialPromptError(verbatim: errorMessage)
                        }
                        if let openPasswords = port.openPasswords {
                            BrowserCredentialPopupFooter(
                                title: offer.takesCard ? "Payment Cards…" : "Addresses…", metrics: metrics,
                                open: openPasswords)
                        }
                    }
                }
            }
        }
        .task(id: request.id) { await load() }
        .onChange(of: port.keyPress) { _, press in
            press.map { answer($0.key) }
        }
        .onDisappear { port.holdKeys(false, request.id) }
    }

    private func row(_ suggestion: BrowserAutofillSuggestion) -> some View {
        let isSelected = suggestion.id == selectedID
        return Button {
            fill(suggestion)
        } label: {
            HStack(spacing: BrowserCredentialPromptMetrics.suggestionRowSpacing) {
                CrestIconTile(
                    systemImage: suggestion.systemImage, color: CrestBrandTheme.accent,
                    size: BrowserCredentialPromptMetrics.headerIdentitySize,
                    symbolSize: BrowserCredentialPromptMetrics.headerIdentitySymbolSize)
                VStack(alignment: .leading, spacing: BrowserCredentialPromptMetrics.suggestionRowTextSpacing) {
                    Text(verbatim: suggestion.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(verbatim: suggestion.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: BrowserCredentialPromptMetrics.suggestionRowSpacerLength)
                if isFilling, isSelected {
                    ProgressView().controlSize(.small)
                } else if offer.takesCard {
                    Image(systemName: "touchid")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, metrics.suggestionRowHighlightBleed)
            .padding(.vertical, metrics.suggestionRowVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: metrics.suggestionRowMinimumHeight, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(
            BrowserCredentialPopupRowStyle(
                isSelected: isSelected, highlightCornerRadius: metrics.suggestionRowHighlightCornerRadius)
        )
        .disabled(isFilling)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func load() async {
        suggestions = nil
        var found: [BrowserAutofillSuggestion] = []
        if offer.takesCard {
            for card in (try? await browser.savedCards()) ?? [] {
                found.append(
                    BrowserAutofillSuggestion(
                        id: card.id, title: card.title,
                        detail: "\(String(localized: card.network.displayName)) ·••• \(card.lastFour) · \(card.expiry)",
                        systemImage: "creditcard.fill"))
            }
        } else {
            let saved = (try? await browser.savedAddresses()) ?? []
            addresses = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
            for address in saved {
                found.append(
                    BrowserAutofillSuggestion(
                        id: address.id, title: address.label.nilIfEmpty ?? address.oneLine,
                        detail: address.oneLine, systemImage: "house.fill"))
            }
        }
        guard !Task.isCancelled else { return }
        suggestions = found
        selectedID = found.first?.id
        if found.isEmpty {
            port.dismiss()
        } else {
            port.holdKeys(true, request.id)
        }
    }

    private func answer(_ key: BrowserCredentialPopupKey) {
        guard let suggestions, !suggestions.isEmpty else { return }
        if key.dismissesPopup {
            port.dismiss()
        } else if key.choosesSelection {
            if let selected = suggestions.first(where: { $0.id == selectedID }) {
                fill(selected)
            } else {
                port.dismiss()
            }
        } else {
            let index = suggestions.firstIndex { $0.id == selectedID } ?? 0
            selectedID = suggestions[min(max(index + key.step, 0), suggestions.count - 1)].id
        }
    }

    private func fill(_ suggestion: BrowserAutofillSuggestion) {
        selectedID = suggestion.id
        Task { @MainActor in
            isFilling = true
            defer { isFilling = false }
            do {
                let values: [BrowserAutofillValue]?
                if offer.takesCard {
                    guard
                        try await BrowserCredentialSensitiveAccess(browser: browser).authenticate(
                            reason: String(localized: "Authenticate to fill \(suggestion.title)."))
                    else { return }
                    values = try await browser.card(id: suggestion.id).flatMap {
                        browser.cardValues($0, into: offer.fields, focused: offer.focused)
                    }
                } else {
                    values = addresses[suggestion.id].flatMap {
                        browser.addressValues($0, into: offer.fields, focused: offer.focused)
                    }
                }
                guard let values, !values.isEmpty else {
                    errorMessage = String(localized: "Crest couldn’t fill this form.")
                    return
                }
                try await port.fillValues(values, request.id)
            } catch {
                errorMessage = String(localized: "The form changed before Crest could fill it.")
            }
        }
    }
}

extension AddressRecord {
    /// The address on one line: its name, first street line and city.
    var oneLine: String {
        let name = [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return [name, streetLines.first ?? "", [postalCode, city].filter { !$0.isEmpty }.joined(separator: " ")]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
