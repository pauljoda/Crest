import SwiftUI

// MARK: - Types

/// What every row of one popup shares: where its logins come from, how to mark
/// them, and what a fill will put in.
struct BrowserCredentialSuggestionContext {
    /// The site's own icon, where the popup may show it.
    let iconData: Data?

    /// The Space's name and the site the popup fills, which a row's second
    /// line names.
    let source: String

    /// Whether a fill writes the username alone, on a step that asks only for
    /// it, which the selected row says.
    let fillsUsernameOnly: Bool
}

/// One saved account the popup can put into the form.
///
/// The name the credential was saved under carries the row and where it comes
/// from sits under it: the Space and the site. The selected row says what a
/// fill will do where that differs from filling both fields, and wears the
/// selection the arrow keys move.
struct BrowserCredentialSuggestionRow: View {
    let suggestion: CredentialDescriptor
    let isSelected: Bool
    let context: BrowserCredentialSuggestionContext
    let metrics: BrowserCredentialPromptMetrics
    let fill: () -> Void

    var body: some View {
        Button(action: fill) {
            HStack(spacing: BrowserCredentialPromptMetrics.suggestionRowSpacing) {
                BrowserCredentialPromptIdentity(
                    kind: .suggestions,
                    iconData: context.iconData,
                    showsSiteIcon: context.iconData != nil,
                    fallbackOrigins: suggestion.origins,
                    tint: CrestBrandTheme.accent
                )
                VStack(
                    alignment: .leading,
                    spacing: BrowserCredentialPromptMetrics.suggestionRowTextSpacing
                ) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if metrics.suggestionRowShowsAccountDetail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: BrowserCredentialPromptMetrics.suggestionRowSpacerLength)
                if isSelected, metrics.showsKeyHints {
                    Image(systemName: "return")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, metrics.suggestionRowHighlightBleed)
            .frame(
                maxWidth: .infinity,
                minHeight: metrics.suggestionRowMinimumHeight,
                alignment: .leading
            )
            .contentShape(.rect)
        }
        .buttonStyle(
            BrowserCredentialPopupRowStyle(
                isSelected: isSelected,
                highlightCornerRadius: metrics.suggestionRowHighlightCornerRadius
            )
        )
        .padding(.vertical, metrics.suggestionRowVerticalPadding)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// What the row is filed under: the name the credential was saved with,
    /// falling back to the login it signs in with.
    private var title: String {
        guard
            let displayName = suggestion.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !displayName.isEmpty
        else {
            return suggestion.username
        }
        return displayName
    }

    /// The second line: what a fill does on a username step, for the row it
    /// would take, and otherwise where the login comes from, with the login
    /// itself when the name is not already it.
    private var detail: String {
        let shown =
            isSelected && context.fillsUsernameOnly
            ? String(localized: "Fills the username now, the password on the next step") : context.source
        guard title != suggestion.username else { return shown }
        return "\(suggestion.username) · \(shown)"
    }
}

#if DEBUG
    #Preview("Pointer and touch") {
        let context = BrowserCredentialSuggestionContext(
            iconData: nil, source: "Work · example.test", fillsUsernameOnly: false)
        VStack(spacing: 20) {
            BrowserCredentialSuggestionRow(
                suggestion: BrowserCredentialDetailPreviewFixture.descriptor, isSelected: true, context: context,
                metrics: .pointer, fill: {})
            BrowserCredentialSuggestionRow(
                suggestion: BrowserCredentialDetailPreviewFixture.descriptor, isSelected: false, context: context,
                metrics: .touch, fill: {})
        }.padding().frame(width: 380)
    }
#endif
