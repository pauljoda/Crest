import SwiftUI

/// One password the prompt offers, as a row: what it is, the password itself,
/// and what the site asked of it, with a button to draw another.
struct BrowserStrongPasswordOfferRow: View {
    let offer: BrowserStrongPasswordOffer
    let title: LocalizedStringResource
    let isSelected: Bool
    let isWorking: Bool
    let metrics: BrowserCredentialPromptMetrics
    let redraw: () -> Void
    let choose: () -> Void

    var body: some View {
        HStack(spacing: BrowserCredentialPromptMetrics.saveActionSpacing) {
            Button(action: choose) {
                HStack(spacing: BrowserCredentialPromptMetrics.suggestionRowSpacing) {
                    CrestIconTile(
                        systemImage: "key.horizontal.fill",
                        color: CrestBrandTheme.accent,
                        size: BrowserCredentialPromptMetrics.headerIdentitySize,
                        symbolSize: BrowserCredentialPromptMetrics.headerIdentitySymbolSize
                    )
                    VStack(alignment: .leading, spacing: BrowserCredentialPromptMetrics.suggestionRowTextSpacing) {
                        Text(title)
                            .font(.callout.weight(.semibold))
                        Text(verbatim: offer.password)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let rules {
                            Text(verbatim: rules)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: BrowserCredentialPromptMetrics.suggestionRowSpacerLength)
                    if isWorking, isSelected {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Creating strong password")
                    } else if isSelected, metrics.showsKeyHints {
                        Image(systemName: "return")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
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
                    isSelected: isSelected,
                    highlightCornerRadius: metrics.suggestionRowHighlightCornerRadius
                )
            )
            .disabled(isWorking)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            Button(action: redraw) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(CrestChromeButtonStyle())
            .disabled(isWorking)
            .help("Another Password")
            .accessibilityLabel("Another Password")
        }
    }

    /// What the site asked of the password, where it said: its length, and
    /// the symbols it allows when it limits them.
    private var rules: String? {
        var parts: [String] = []
        switch (offer.recipe.siteMinLength, offer.recipe.siteMaxLength) {
        case (let shortest?, let longest?):
            parts.append(String(localized: "\(shortest)–\(longest) characters"))
        case (let shortest?, nil):
            parts.append(String(localized: "At least \(shortest) characters"))
        case (nil, let longest?):
            parts.append(String(localized: "Up to \(longest) characters"))
        case (nil, nil):
            break
        }
        if let symbols = offer.recipe.siteSymbols {
            parts.append(
                symbols.isEmpty
                    ? String(localized: "No symbols")
                    : String(localized: "Only \(symbols.map(String.init).joined(separator: " "))"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
