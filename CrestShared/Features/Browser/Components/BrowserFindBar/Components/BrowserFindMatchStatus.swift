import SwiftUI

/// What the page can say about the search, spelled the way the shell has room
/// for.
///
/// Both spellings answer the same question with the width each shell can spare:
/// a floating panel can afford "No match" in words, while a bar that already
/// spans a phone's chrome spends that width on the query instead. Neither draws
/// anything before a search has been asked for.
struct BrowserFindMatchStatus: View {
    let state: BrowserFindMatchState
    let metrics: BrowserFindBarMetrics

    @ViewBuilder
    var body: some View {
        switch metrics.matchStatusStyle {
        case .label:
            spelledOut
        case .symbol:
            drawn
        }
    }

    /// The state in words, red only where the page has nothing to show.
    @ViewBuilder
    private var spelledOut: some View {
        if let label = state.accessibilityLabel {
            Text(label)
                .font(.caption)
                .foregroundStyle(state == .notFound ? .red : .secondary)
                .frame(
                    minWidth: metrics.matchStatusWidth,
                    alignment: .trailing
                )
                .accessibilityIdentifier("find-result")
        }
    }

    /// The same states as a symbol, each in the same narrow column, carrying
    /// the words as their accessibility label instead.
    @ViewBuilder
    private var drawn: some View {
        if let label = state.accessibilityLabel {
            symbol
                .frame(
                    width: metrics.matchStatusWidth,
                    height: metrics.barHeight
                )
                .accessibilityLabel(Text(label))
                .accessibilityIdentifier("find-result")
        }
    }

    @ViewBuilder
    private var symbol: some View {
        switch state {
        case .idle:
            EmptyView()
        case .searching:
            ProgressView()
                .controlSize(.small)
        case .found:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .notFound:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
