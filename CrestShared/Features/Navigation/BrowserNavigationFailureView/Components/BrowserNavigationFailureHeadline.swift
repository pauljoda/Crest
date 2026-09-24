import SwiftUI

struct BrowserNavigationFailureHeadline: View {
    let failure: BrowserNavigationFailure
    let presentation: BrowserNavigationFailurePresentation
    let alignment: HorizontalAlignment
    let textAlignment: TextAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: CrestSpacing.medium) {
            Text(presentation.title)
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(textAlignment)

            presentation.message
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(textAlignment)
                .fixedSize(horizontal: false, vertical: true)

            // Selectable text is an AppKit view: a label with no value recurses when assistive apps read it.
            Text(failure.browserCode)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .accessibilityLabel("Error code")
                .accessibilityValue(failure.browserCode)
        }
    }
}

#if DEBUG
    #Preview("Offline headline") {
        let failure = BrowserNavigationFailurePreviewFixture.offline
        BrowserNavigationFailureHeadline(
            failure: failure, presentation: BrowserNavigationFailurePresentation(failure: failure), alignment: .leading,
            textAlignment: .leading
        )
        .padding().frame(width: 420)
    }
#endif
