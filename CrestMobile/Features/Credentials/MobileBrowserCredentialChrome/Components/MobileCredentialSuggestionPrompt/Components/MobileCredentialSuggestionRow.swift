import SwiftUI

struct MobileCredentialSuggestionRow: View {
    let suggestion: CredentialDescriptor
    let fill: () -> Void

    var body: some View {
        Button(action: fill) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)
                Text(suggestion.username)
                    .lineLimit(1)
                Spacer(minLength: 10)
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.tint)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 44,
                alignment: .leading
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Credential Suggestion Row") {
    let fixture = MobileBrowserCredentialChromePreviewFixture()

    MobileCredentialSuggestionRow(
        suggestion: fixture.suggestion,
        fill: {}
    )
    .padding()
    .frame(width: 390)
}
