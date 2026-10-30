import SwiftUI

/// One row of the prompt's list: a glyph, what the row is, and the arrow that
/// says choosing it goes on.
struct BrowserCredentialPromptRow: View {
    let symbol: String
    let title: String
    let detail: String?
    /// The glyph that says choosing the row goes on; nil for a row that leaves Crest.
    var trailingSymbol: String? = "arrow.right.circle.fill"
    let metrics: BrowserCredentialPromptMetrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: BrowserCredentialPromptMetrics.suggestionRowSpacing) {
                Image(systemName: symbol)
                    .font(
                        .system(
                            size: BrowserCredentialPromptMetrics
                                .suggestionRowIconSize
                        )
                    )
                    .foregroundStyle(.secondary)
                VStack(
                    alignment: .leading,
                    spacing: BrowserCredentialPromptMetrics
                        .suggestionRowTextSpacing
                ) {
                    Text(title)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(
                    minLength: BrowserCredentialPromptMetrics
                        .suggestionRowSpacerLength
                )
                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .foregroundStyle(.tint)
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
            BrowserCredentialSuggestionRowStyle(
                highlightCornerRadius: metrics.suggestionRowHighlightCornerRadius
            )
        )
        .padding(.vertical, metrics.suggestionRowVerticalPadding)
    }
}

/// The row's resting and pressed treatment, where its shell draws one.
///
/// A plain button style everywhere else: a band's rows are aimed at with a
/// finger, which never rests, and a highlight that only ever appears under the
/// thumb already covering it is noise.
private struct BrowserCredentialSuggestionRowStyle: ButtonStyle {
    let highlightCornerRadius: CGFloat?

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if let highlightCornerRadius {
            configuration.label
                .crestHoverSurface(
                    cornerRadius: highlightCornerRadius,
                    isPressed: configuration.isPressed
                )
        } else {
            configuration.label
        }
    }
}
