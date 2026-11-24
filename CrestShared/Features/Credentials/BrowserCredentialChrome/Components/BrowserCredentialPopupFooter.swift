import SwiftUI

/// The foot of a fill popup: the way into the Space's passwords in Settings,
/// and on a shell with a keyboard, the keys that work the popup.
struct BrowserCredentialPopupFooter: View {
    let title: LocalizedStringResource
    let metrics: BrowserCredentialPromptMetrics
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrowserCredentialPromptMetrics.contentSpacing) {
            Divider()
            Button(action: open) {
                HStack(spacing: BrowserCredentialPromptMetrics.suggestionRowSpacing) {
                    Image(systemName: "key")
                        .foregroundStyle(.secondary)
                    Text(title)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: BrowserCredentialPromptMetrics.suggestionRowSpacerLength)
                    if metrics.showsKeyHints {
                        Text(verbatim: "↑↓  ⏎")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                .font(.caption)
                .padding(.horizontal, metrics.suggestionRowHighlightBleed)
                .padding(.vertical, metrics.suggestionRowVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(
                BrowserCredentialPopupRowStyle(
                    isSelected: false,
                    highlightCornerRadius: metrics.suggestionRowHighlightCornerRadius
                )
            )
            .padding(.horizontal, -metrics.suggestionRowHighlightBleed)
        }
    }
}
