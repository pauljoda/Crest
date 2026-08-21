import SwiftUI

/// The title row a credential fill prompt opens with: the Space's key, what the
/// prompt is for, the origin it was asked from, and the way out.
struct BrowserCredentialPromptHeader: View {
    let kind: BrowserCredentialPromptHeaderKind
    let request: BrowserCredentialFillRequest
    let space: BrowserSpace?
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: BrowserCredentialPromptMetrics.headerSpacing) {
            Image(systemName: kind.symbol)
                .foregroundStyle(space?.accent.color ?? .accentColor)
                .accessibilityHidden(true)
            VStack(
                alignment: .leading,
                spacing: BrowserCredentialPromptMetrics.headerTextSpacing
            ) {
                Text(kind.title(spaceName: space?.name ?? "this Space"))
                    .font(.callout.weight(.semibold))
                Text(request.origin.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: BrowserCredentialPromptMetrics.headerSpacerLength)
            Button("Close", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .frame(
                    width: BrowserCredentialPromptMetrics.controlHitTarget,
                    height: BrowserCredentialPromptMetrics.controlHitTarget
                )
        }
    }
}
