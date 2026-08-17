import SwiftUI

struct MobileCredentialPromptHeader: View {
    let kind: MobileCredentialPromptHeaderKind
    let request: BrowserCredentialFillRequest
    let space: BrowserSpace?
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: kind.symbol)
                .foregroundStyle(space?.accent.color ?? .accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title(spaceName: space?.name ?? "this Space"))
                    .font(.callout.weight(.semibold))
                Text(request.origin.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Close", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
        }
    }
}
